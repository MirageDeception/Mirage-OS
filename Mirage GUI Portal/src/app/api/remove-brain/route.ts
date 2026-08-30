import { NextResponse } from "next/server";
import { STSClient, AssumeRoleCommand } from "@aws-sdk/client-sts";
import { exec } from "child_process";
import path from "path";

const stsClient = new STSClient({ region: "us-west-2" });

export async function POST(request: Request) {
  try {
    const { accountId, roleArn, region = "us-west-2" } = await request.json();

    if (!accountId || !roleArn) {
      return NextResponse.json(
        { error: "Missing accountId or roleArn" },
        { status: 400 }
      );
    }

    console.log(`[MIRAGE] Assuming role ${roleArn} in account ${accountId} for REMOVAL...`);

    // 1. Assume the target Role in the Hub Account
    const assumeRoleResponse = await stsClient.send(
      new AssumeRoleCommand({
        RoleArn: roleArn,
        RoleSessionName: "MiragePlusHubRemovalSession",
      })
    );

    if (!assumeRoleResponse.Credentials) {
      throw new Error("Failed to obtain temporary credentials from STS.");
    }

    const { AccessKeyId, SecretAccessKey, SessionToken } = assumeRoleResponse.Credentials;

    // 2. Trigger the Bash Script Execution
    const scriptPath = path.join(process.cwd(), "src", "scripts", "remove-hub.sh");
    console.log(`[MIRAGE] Triggering removal bash script: ${scriptPath}`);

    await new Promise((resolve, reject) => {
      const childProc = exec(`bash "${scriptPath}" "${region}" ""`, {
        cwd: process.cwd(),
        env: {
          ...process.env, // Inherit path so 'aws' CLI command works
          AWS_ACCESS_KEY_ID: AccessKeyId,
          AWS_SECRET_ACCESS_KEY: SecretAccessKey,
          AWS_SESSION_TOKEN: SessionToken,
          AWS_DEFAULT_REGION: region,
        }
      });

      childProc.stdout?.on('data', (data) => console.log(`[REMOVE] ${data.trim()}`));
      childProc.stderr?.on('data', (data) => console.error(`[REMOVE ERR] ${data.trim()}`));

      childProc.on('close', (code) => {
        if (code === 0) resolve(true);
        else reject(new Error(`Removal script failed with exit code ${code}`));
      });
    });

    return NextResponse.json(
      { message: "Hub architecture successfully removed!" },
      { status: 200 }
    );

  } catch (error: any) {
    console.error("[MIRAGE] Removal Error:", error);
    return NextResponse.json(
      { error: error.message || "An unexpected error occurred during removal." },
      { status: 500 }
    );
  }
}
