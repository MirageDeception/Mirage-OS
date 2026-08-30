import { NextResponse } from 'next/server';
import { STSClient, AssumeRoleCommand } from '@aws-sdk/client-sts';
import { exec } from 'child_process';
import fs from 'fs/promises';
import path from 'path';
import util from 'util';
import { getLatestActiveRule, getNextRuleName, saveRuleState, saveInventory, getInventory, RuleRecord, InventoryRecord } from '@/lib/db';
import { appendHistory } from '@/lib/history';

const execAsync = util.promisify(exec);

export async function POST(req: Request) {
  try {
    const { accountId, roleArn, hubBusArn, forwardingRoleArn, scenarioIds, scenarioNames, parameters, individualRule } = await req.json();

    // Generate a sessionId to group all events from this deployment batch
    const sessionId = Date.now().toString();

    if (!accountId || !roleArn || !hubBusArn || !forwardingRoleArn || !scenarioIds || !Array.isArray(scenarioIds)) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 });
    }

    console.log(`Starting deployment to Spoke Account: ${accountId}`);

    // 1. Assume Spoke Role
    const stsClient = new STSClient({ region: 'us-east-1' });
    const assumeRoleCommand = new AssumeRoleCommand({
      RoleArn: roleArn,
      RoleSessionName: 'MiragePlusSpokeDeployment',
    });
    
    let credentials;
    try {
      const stsResponse = await stsClient.send(assumeRoleCommand);
      credentials = {
        AWS_ACCESS_KEY_ID: stsResponse.Credentials?.AccessKeyId,
        AWS_SECRET_ACCESS_KEY: stsResponse.Credentials?.SecretAccessKey,
        AWS_SESSION_TOKEN: stsResponse.Credentials?.SessionToken,
      };
      console.log(`Successfully assumed role: ${roleArn}`);
    } catch (stsError: any) {
      console.error("STS AssumeRole failed:", stsError);
      return NextResponse.json({ error: `Failed to assume spoke role: ${stsError.message}` }, { status: 403 });
    }

    const typeMapping: Record<string, string> = {
      s3: 'bucketName', secretsmanager: 'secretId', sts: 'roleName', ssm: 'name', iam: 'roleName',
      ecr: 'repositoryName', lambda: 'functionName', dynamodb: 'tableName', sqs: 'queueUrl',
      sns: 'topicArn', kms: 'keyId', cloudformation: 'stackName'
    };

    const getBasePattern = (orArray: any[], sources: string[]) => ({
      source: sources,
      "detail-type": ["AWS API Call via CloudTrail"],
      detail: { requestParameters: { $or: orArray } }
    });

    // Returns true if a new value was actually inserted, false if it was already present
    const addCondition = (conditions: any[], key: string, value: string): boolean => {
      const existing = conditions.find(c => c[key] !== undefined);
      if (existing) {
        if (!existing[key].includes(value)) {
          existing[key].push(value);
          return true;
        }
        return false;
      } else {
        conditions.push({ [key]: [value] });
        return true;
      }
    };

    const removeCondition = (conditions: any[], key: string, value: string) => {
      const existing = conditions.find(c => c[key] !== undefined);
      if (existing) {
        existing[key] = existing[key].filter((v: string) => v !== value);
        if (existing[key].length === 0) {
          conditions.splice(conditions.indexOf(existing), 1);
        }
      }
    };

    const MAX_PATTERN_CHARS = 4000;

    // Helper to process decoy resources into EventBridge Rules
    // Returns array of rule names that were generated (for history logging)
    async function processResourcesToRules(resourcesToProcess: any[], isIndividual: boolean): Promise<string[]> {
      if (resourcesToProcess.length === 0) return [];
      const generatedRuleNames: string[] = [];

      let latestRule: RuleRecord | null = null;
      if (!isIndividual) {
        latestRule = await getLatestActiveRule(accountId);
      }
      
      if (!latestRule) {
        latestRule = {
          accountId,
          ruleName: await getNextRuleName(accountId),
          eventPattern: "",
          status: 'pending',
          charCount: 220,
          limitReached: isIndividual ? true : false
        };
      } else {
        if (latestRule.status === 'deployed') {
          latestRule.status = 'update_available';
        }
      }

      let currentConditions: any[] = [];
      const activeSources = new Set<string>();
      
      if (latestRule.eventPattern) {
        try {
          const parsed = JSON.parse(latestRule.eventPattern);
          if (parsed.detail?.requestParameters?.$or) {
            currentConditions = parsed.detail.requestParameters.$or;
          }
          if (parsed.source) {
            parsed.source.forEach((s: string) => activeSources.add(s));
          }
        } catch (e) {}
      }

      const inventoryRecords: InventoryRecord[] = [];
      
      for (const entry of resourcesToProcess) {
        const catRaw = entry.category.toLowerCase().trim();
        const key = typeMapping[catRaw] || catRaw;
        const resources = entry.resources.split(',').map((r: string) => r.trim()).filter((r: string) => r.length > 0);
        
        for (const r of resources) {
          inventoryRecords.push({ accountId, scenarioId: entry.scenarioId, ruleName: latestRule.ruleName, decoyName: r, decoyCategory: catRaw });
          const wasAdded = addCondition(currentConditions, key, r);
          // Only register the source if this resource is genuinely new in the pattern
          if (wasAdded) {
            activeSources.add(`aws.${catRaw}`);
          }
          
          const testPattern = getBasePattern(currentConditions, Array.from(activeSources));
          const patternStr = JSON.stringify(testPattern);
          
          if (patternStr.length > MAX_PATTERN_CHARS) {
            removeCondition(currentConditions, key, r);
            latestRule.limitReached = true;
            
            const finalPattern = getBasePattern(currentConditions, Array.from(activeSources));
            latestRule.eventPattern = JSON.stringify(finalPattern, null, 2);
            await saveRuleState(latestRule);
            
            latestRule = {
              accountId,
              ruleName: await getNextRuleName(accountId),
              eventPattern: "",
              status: 'pending',
              charCount: 220,
              limitReached: isIndividual ? true : false // Keep isolated if individual
            };
            currentConditions = [];
            activeSources.clear();
            
            addCondition(currentConditions, key, r);
            activeSources.add(`aws.${catRaw}`);
            inventoryRecords[inventoryRecords.length - 1].ruleName = latestRule.ruleName;
          } else {
            latestRule.charCount = patternStr.length;
          }
        }
      }
      
      if (currentConditions.length > 0) {
        const finalPattern = getBasePattern(currentConditions, Array.from(activeSources));
        latestRule.eventPattern = JSON.stringify(finalPattern, null, 2);
        await saveRuleState(latestRule);
        if (!generatedRuleNames.includes(latestRule.ruleName)) {
          generatedRuleNames.push(latestRule.ruleName);
        }
      }
      
      await saveInventory(inventoryRecords);
      console.log(`Generated EventBridge tracking rules for deployed resources.`);
      return generatedRuleNames;
    }

    // 2. Process scenarios
    const allGroupedResources: any[] = [];
    const deployedScenarios: string[] = [];
    const failedScenarios: { id: string, error: string }[] = [];
    const duplicateWarnings: { scenarioId: string, resources: string[] }[] = [];

    // Load the existing inventory once for duplicate detection
    const existingInventory = await getInventory();
    const existingResourceKeys = new Set(
      existingInventory
        .filter(r => r.accountId === accountId)
        .map(r => `${r.decoyCategory}::${r.decoyName}`)
    );
    
    for (const scenarioId of scenarioIds) {
      console.log(`Preparing isolated deployment environment for ${scenarioId}...`);
      
      const templateDir = path.join(process.cwd(), 'src', 'templates', 'mirage-os', 'aws', 'scenarios_terraform', scenarioId);
      const stateDir = path.join(process.cwd(), 'states', accountId, scenarioId);

      await fs.mkdir(stateDir, { recursive: true });
      await fs.cp(templateDir, stateDir, { recursive: true });

      console.log(`Executing Terraform for ${scenarioId}...`);
      const scriptPath = path.join(process.cwd(), 'src', 'scripts', 'deploy-spoke.sh');
      try {
        const { stdout } = await execAsync(`bash "${scriptPath}" ${scenarioId} ${accountId}`, {
          maxBuffer: 10 * 1024 * 1024,
          env: {
            ...process.env,
            ...credentials,
            AWS_DEFAULT_REGION: 'us-west-2',
            AWS_REGION: 'us-west-2'
          }
        });
        console.log(`Deployed ${scenarioId}:\n`, stdout);

        const { stdout: tfOutput } = await execAsync(`terraform output -json`, {
          cwd: stateDir,
          maxBuffer: 10 * 1024 * 1024,
          env: {
            ...process.env,
            ...credentials,
            AWS_DEFAULT_REGION: 'us-west-2',
            AWS_REGION: 'us-west-2'
          }
        });

        const outputs = JSON.parse(tfOutput);
        
        let scenarioResources: any[] = [];
        if (outputs.decoy_resources && outputs.decoy_resources.value) {
          const decoyResourcesStr = outputs.decoy_resources.value;
          const decoyResources = JSON.parse(decoyResourcesStr);
          for (const d of decoyResources) {
            scenarioResources.push({ ...d, scenarioId });
          }
        }

        // --- Duplicate Resource Check ---
        const duplicatesForScenario: string[] = [];
        const freshResources: any[] = [];
        for (const resource of scenarioResources) {
          const resourceNames = resource.resources.split(',').map((r: string) => r.trim());
          for (const name of resourceNames) {
            const key = `${resource.category.toLowerCase()}::${name}`;
            if (existingResourceKeys.has(key)) {
              duplicatesForScenario.push(`${resource.category}/${name}`);
            } else {
              // Add to fresh set and mark as known for subsequent scenarios in this batch
              existingResourceKeys.add(key);
              if (!freshResources.find(r => r === resource)) {
                freshResources.push(resource);
              }
            }
          }
        }
        if (duplicatesForScenario.length > 0) {
          console.log(`[${scenarioId}] Skipping ${duplicatesForScenario.length} already-registered resources: ${duplicatesForScenario.join(', ')}`);
          duplicateWarnings.push({ scenarioId, resources: duplicatesForScenario });
        }
        // Use only fresh (non-duplicate) resources for rule generation
        scenarioResources = freshResources;
        
        if (individualRule) {
          // If Individual, process rule immediately for just this scenario
          const ruleNames = await processResourcesToRules(scenarioResources, true);
          // Log a rule_generate history event for each rule created
          for (const ruleName of ruleNames) {
            await appendHistory({
              sessionId,
              type: 'rule_generate',
              scenarioId,
              scenarioName: (scenarioNames && scenarioNames[scenarioId]) || scenarioId,
              accountId,
              ruleName,
              status: 'success',
            });
          }
        } else {
          // If Grouped, aggregate them to process at the end
          allGroupedResources.push(...scenarioResources);
        }
        
        deployedScenarios.push(scenarioId);
      } catch (deployErr: any) {
        console.error(`Deployment failed for ${scenarioId}:\n`, deployErr.stderr || deployErr.message);
        failedScenarios.push({ id: scenarioId, error: deployErr.message });
        // Log a failed scenario_deploy history event
        await appendHistory({
          sessionId,
          type: 'scenario_deploy',
          scenarioId,
          scenarioName: (scenarioNames && scenarioNames[scenarioId]) || scenarioId,
          accountId,
          status: 'failed',
          error: deployErr.message,
        });
      }
    }

    // 3. Process grouped resources if not individual
    if (!individualRule && allGroupedResources.length > 0) {
      const groupedRuleNames = await processResourcesToRules(allGroupedResources, false);
      // Log rule_generate events for grouped deployments (one event per scenario)
      for (const scenarioId of deployedScenarios) {
        for (const ruleName of groupedRuleNames) {
          await appendHistory({
            sessionId,
            type: 'rule_generate',
            scenarioId,
            scenarioName: (scenarioNames && scenarioNames[scenarioId]) || scenarioId,
            accountId,
            ruleName,
            status: 'success',
          });
        }
      }
    }

    // Log scenario_deploy success events (done after all processing to keep timeline clean)
    for (const scenarioId of deployedScenarios) {
      await appendHistory({
        sessionId,
        type: 'scenario_deploy',
        scenarioId,
        scenarioName: (scenarioNames && scenarioNames[scenarioId]) || scenarioId,
        accountId,
        status: 'success',
      });
    }

    return NextResponse.json({ 
      success: true, 
      deployed: deployedScenarios,
      failed: failedScenarios,
      duplicates: duplicateWarnings,
      message: `Deployed ${deployedScenarios.length} scenarios successfully.` 
    });
  } catch (error) {
    console.error("Error in /api/deploy-spoke:", error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
