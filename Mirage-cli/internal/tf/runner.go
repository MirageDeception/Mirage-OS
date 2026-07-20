// Package tf wraps the Terraform CLI for mirage's deploy/destroy operations.
// All infrastructure mutations go through Terraform — never raw AWS API calls.
// This ensures state tracking, drift detection, and idempotency.
package tf

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Runner executes Terraform commands in a given working directory.
// Env is injected per-invocation so cross-account credentials are scoped.
type Runner struct {
	// TerraformBin is the path to the terraform binary (default: "terraform").
	TerraformBin string
	// Verbose streams Terraform stdout/stderr to the user when true.
	Verbose bool
	// ExtraEnv is additional environment variables (e.g. AWS_* credentials).
	ExtraEnv []string
}

// NewRunner creates a Runner with sensible defaults.
func NewRunner(verbose bool) *Runner {
	return &Runner{
		TerraformBin: "terraform",
		Verbose:      verbose,
	}
}

// Result is the structured output from a Terraform operation.
type Result struct {
	Success  bool
	Outputs  map[string]string // parsed from terraform output -json
	PlanPath string            // path to the plan file (after Plan)
	Stdout   string
	Stderr   string
}

// CheckInstalled verifies terraform is in PATH and meets minimum version.
func CheckInstalled() error {
	out, err := exec.LookPath("terraform")
	if err != nil {
		return fmt.Errorf(
			"terraform not found in PATH\n\n" +
				"Install Terraform 1.5+ from: https://developer.hashicorp.com/terraform/install\n" +
				"Or via package manager:\n" +
				"  brew install terraform          (macOS)\n" +
				"  apt-get install terraform       (Ubuntu)\n" +
				"  winget install Hashicorp.Terraform  (Windows)",
		)
	}
	_ = out

	// Check version ≥ 1.5
	vOut, err := exec.Command("terraform", "version", "-json").Output()
	if err != nil {
		return nil // old version without -json flag — allow it
	}
	var vData struct {
		TerraformVersion string `json:"terraform_version"`
	}
	if err := json.Unmarshal(vOut, &vData); err == nil {
		parts := strings.Split(vData.TerraformVersion, ".")
		if len(parts) >= 2 && parts[0] == "0" {
			return fmt.Errorf("terraform version %s is too old: mirage requires 1.5+", vData.TerraformVersion)
		}
	}
	return nil
}

// Init runs `terraform init` in workDir.
func (r *Runner) Init(ctx context.Context, workDir string) (*Result, error) {
	return r.run(ctx, workDir, nil, "init", "-input=false", "-no-color", "-reconfigure")
}

// Plan runs `terraform plan` and saves the plan to a file. Returns the plan file path.
func (r *Runner) Plan(ctx context.Context, workDir, varFile string) (*Result, error) {
	planPath := filepath.Join(workDir, "mirage.tfplan")
	args := []string{"plan", "-input=false", "-no-color", "-out=" + planPath}
	if varFile != "" {
		args = append(args, "-var-file="+varFile)
	}
	result, err := r.run(ctx, workDir, nil, args...)
	if err != nil {
		return result, err
	}
	result.PlanPath = planPath
	return result, nil
}

// Apply runs `terraform apply` on a previously generated plan file.
func (r *Runner) Apply(ctx context.Context, workDir, planPath string) (*Result, error) {
	result, err := r.run(ctx, workDir, nil, "apply", "-input=false", "-no-color", planPath)
	if err != nil {
		return result, err
	}
	// Parse outputs.
	outputs, err := r.Output(ctx, workDir)
	if err == nil {
		result.Outputs = outputs
	}
	return result, nil
}

// ApplyWithVars is a convenience that generates a tfvars file, plans, and applies.
func (r *Runner) ApplyWithVars(ctx context.Context, workDir string, vars map[string]string, dryRun bool) (*Result, error) {
	varFile, err := WriteTempVarFile(workDir, vars)
	if err != nil {
		return nil, err
	}
	defer os.Remove(varFile)

	if _, err := r.Init(ctx, workDir); err != nil {
		return nil, fmt.Errorf("terraform init: %w", err)
	}

	planResult, err := r.Plan(ctx, workDir, varFile)
	if err != nil {
		return nil, fmt.Errorf("terraform plan: %w", err)
	}

	if dryRun {
		planResult.Success = true
		return planResult, nil
	}

	return r.Apply(ctx, workDir, planResult.PlanPath)
}

// DestroyWithVars runs `terraform destroy` with the provided variables.
func (r *Runner) DestroyWithVars(ctx context.Context, workDir string, vars map[string]string, dryRun bool) (*Result, error) {
	varFile, err := WriteTempVarFile(workDir, vars)
	if err != nil {
		return nil, err
	}
	defer os.Remove(varFile)

	if _, err := r.Init(ctx, workDir); err != nil {
		return nil, fmt.Errorf("terraform init: %w", err)
	}

	if dryRun {
		// Plan destroy to show what would be removed.
		return r.run(ctx, workDir, nil,
			"plan", "-destroy", "-input=false", "-no-color", "-var-file="+varFile)
	}

	return r.run(ctx, workDir, nil,
		"destroy", "-auto-approve", "-input=false", "-no-color", "-var-file="+varFile)
}

// Output parses `terraform output -json` into a flat string map.
func (r *Runner) Output(ctx context.Context, workDir string) (map[string]string, error) {
	oldVerbose := r.Verbose
	r.Verbose = false
	result, err := r.run(ctx, workDir, nil, "output", "-json")
	r.Verbose = oldVerbose
	
	if err != nil {
		return nil, err
	}

	// terraform output -json format: {"key": {"value": <val>, "type": "string"}}
	var raw map[string]struct {
		Value interface{} `json:"value"`
		Type  interface{} `json:"type"`
	}
	if err := json.Unmarshal([]byte(result.Stdout), &raw); err != nil {
		return nil, fmt.Errorf("parse terraform output: %w", err)
	}

	outputs := make(map[string]string, len(raw))
	for k, v := range raw {
		switch val := v.Value.(type) {
		case string:
			outputs[k] = val
		case float64:
			outputs[k] = fmt.Sprintf("%v", val)
		default:
			b, _ := json.Marshal(val)
			outputs[k] = string(b)
		}
	}
	return outputs, nil
}

// StateList returns the list of resources in the Terraform state.
func (r *Runner) StateList(ctx context.Context, workDir string) ([]string, error) {
	result, err := r.run(ctx, workDir, nil, "state", "list")
	if err != nil {
		return nil, err
	}
	var resources []string
	for _, line := range strings.Split(strings.TrimSpace(result.Stdout), "\n") {
		if line != "" {
			resources = append(resources, line)
		}
	}
	return resources, nil
}

// run is the internal command executor.
func (r *Runner) run(ctx context.Context, workDir string, extraEnv []string, args ...string) (*Result, error) {
	cmd := exec.CommandContext(ctx, r.TerraformBin, args...)
	cmd.Dir = workDir
	cmd.Env = append(os.Environ(), r.ExtraEnv...)
	cmd.Env = append(cmd.Env, extraEnv...)

	var stdout, stderr bytes.Buffer
	if r.Verbose {
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
	} else {
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr
	}

	err := cmd.Run()
	result := &Result{
		Success: err == nil,
		Stdout:  stdout.String(),
		Stderr:  stderr.String(),
	}

	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = err.Error()
		}
		return result, fmt.Errorf("terraform %s failed:\n%s", args[0], msg)
	}
	return result, nil
}

// WithCredentials returns a copy of the runner with AWS credential env vars set.
// Used to inject assumed-role credentials for cross-account Terraform operations.
func (r *Runner) WithCredentials(accessKeyID, secretKey, sessionToken, region string) *Runner {
	env := []string{
		"AWS_ACCESS_KEY_ID=" + accessKeyID,
		"AWS_SECRET_ACCESS_KEY=" + secretKey,
		"AWS_DEFAULT_REGION=" + region,
	}
	if sessionToken != "" {
		env = append(env, "AWS_SESSION_TOKEN="+sessionToken)
	}
	return &Runner{
		TerraformBin: r.TerraformBin,
		Verbose:      r.Verbose,
		ExtraEnv:     append(r.ExtraEnv, env...),
	}
}

// WriteTempVarFile writes a temporary .tfvars file from a string map.
// The caller is responsible for deleting the file (use defer os.Remove(path)).
func WriteTempVarFile(workDir string, vars map[string]string) (string, error) {
	var sb strings.Builder
	sb.WriteString("# Generated by mirage — do not edit\n")
	for k, v := range vars {
		sb.WriteString(fmt.Sprintf("%s = %q\n", k, v))
	}

	f, err := os.CreateTemp(workDir, "mirage-*.tfvars")
	if err != nil {
		// Fallback to system temp dir.
		f, err = os.CreateTemp("", "mirage-*.tfvars")
		if err != nil {
			return "", fmt.Errorf("create tfvars temp file: %w", err)
		}
	}
	defer f.Close()

	if _, err := f.WriteString(sb.String()); err != nil {
		return "", fmt.Errorf("write tfvars: %w", err)
	}
	return f.Name(), nil
}
