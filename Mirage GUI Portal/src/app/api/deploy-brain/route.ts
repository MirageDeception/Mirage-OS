import { NextResponse } from "next/server";
import { STSClient, AssumeRoleCommand } from "@aws-sdk/client-sts";
import { CloudFormationClient, DescribeStacksCommand } from "@aws-sdk/client-cloudformation";
import { SNSClient, SubscribeCommand } from "@aws-sdk/client-sns";
import { exec } from "child_process";
import path from "path";

// Initialize STS Client (uses base Mirage_admin credentials from ~/.aws)
const stsClient = new STSClient({ region: "us-west-2" });

export async function POST(request: Request) {
  try {
    const { accountId, roleArn, region = "us-west-2", whitelistedArns = "", email = "", webhookUrl = "" } = await request.json();

    if (!accountId || !roleArn) {
      return NextResponse.json(
        { error: "Missing accountId or roleArn" },
        { status: 400 }
      );
    }

    console.log(`[MIRAGE] Assuming role ${roleArn} in account ${accountId}...`);

    // 1. Assume the target Role in the Hub Account
    const assumeRoleResponse = await stsClient.send(
      new AssumeRoleCommand({
        RoleArn: roleArn,
        RoleSessionName: "MiragePlusHubDeploymentSession",
      })
    );

    if (!assumeRoleResponse.Credentials) {
      throw new Error("Failed to obtain temporary credentials from STS.");
    }

    const { AccessKeyId, SecretAccessKey, SessionToken } = assumeRoleResponse.Credentials;

    // 2. Pre-flight Check: Verify if the brain already exists
    const cfnClient = new CloudFormationClient({
      region,
      credentials: {
        accessKeyId: AccessKeyId!,
        secretAccessKey: SecretAccessKey!,
        sessionToken: SessionToken,
      },
    });

    try {
      const describeResponse = await cfnClient.send(
        new DescribeStacksCommand({ StackName: "deception-v2-monitoring-brain" })
      );
      
      const stackStatus = describeResponse.Stacks?.[0]?.StackStatus;
      if (stackStatus && stackStatus !== 'DELETE_COMPLETE') {
        console.log(`[MIRAGE] Brain already exists with status: ${stackStatus}`);
        return NextResponse.json(
          { error: `A Deploy Brain already exists with status: ${stackStatus}. Please teardown the existing brain first.` },
          { status: 409 }
        );
      }
    } catch (err: any) {
      // If the stack does not exist, AWS throws a ValidationError. We can safely proceed.
      if (err.name !== 'ValidationError' && !err.message.includes('does not exist')) {
        throw err;
      }
    }

    // 3. Trigger the Bash Script Execution
    const scriptPath = path.join(process.cwd(), "src", "scripts", "deploy-hub.sh");
    console.log(`[MIRAGE] Triggering bash script: ${scriptPath}`);

    await new Promise((resolve, reject) => {
      const childProc = exec(`bash "${scriptPath}" "${region}" "${whitelistedArns}"`, {
        cwd: process.cwd(),
        env: {
          ...process.env, // Inherit path so 'aws' CLI command works
          AWS_ACCESS_KEY_ID: AccessKeyId,
          AWS_SECRET_ACCESS_KEY: SecretAccessKey,
          AWS_SESSION_TOKEN: SessionToken,
          AWS_DEFAULT_REGION: region,
        }
      });

      childProc.stdout?.on('data', (data) => console.log(`[DEPLOY] ${data.trim()}`));
      childProc.stderr?.on('data', (data) => console.error(`[DEPLOY ERR] ${data.trim()}`));

      childProc.on('close', (code) => {
        if (code === 0) resolve(true);
        else reject(new Error(`Deployment script failed with exit code ${code}`));
      });
    });

    // 3. Handle Optional SNS Subscriptions (Email / Webhook)
    if ((email && email.trim() !== "") || (webhookUrl && webhookUrl.trim() !== "")) {
      console.log(`[MIRAGE] Optional subscriptions detected. Configuring SNS...`);
      
      const cfnClient = new CloudFormationClient({
        region,
        credentials: {
          accessKeyId: AccessKeyId!,
          secretAccessKey: SecretAccessKey!,
          sessionToken: SessionToken!,
        },
      });

      // Find the SNS Topic ARN from the Brain Stack Outputs
      const describeRes = await cfnClient.send(new DescribeStacksCommand({ StackName: "deception-v2-monitoring-brain" }));
      const snsOutput = describeRes.Stacks?.[0]?.Outputs?.find(o => o.OutputKey === "SNSTopicArn");
      
      if (snsOutput && snsOutput.OutputValue) {
        const snsClient = new SNSClient({
          region,
          credentials: {
            accessKeyId: AccessKeyId!,
            secretAccessKey: SecretAccessKey!,
            sessionToken: SessionToken!,
          },
        });
        
        const topicArn = snsOutput.OutputValue;

        // Subscribe Email if provided
        if (email && email.trim() !== "") {
          await snsClient.send(new SubscribeCommand({
            TopicArn: topicArn,
            Protocol: "email",
            Endpoint: email.trim()
          }));
          console.log(`[MIRAGE] Successfully subscribed ${email} to SNS!`);
        }

        // Subscribe Webhook if provided
        if (webhookUrl && webhookUrl.trim() !== "") {
          const protocol = webhookUrl.startsWith("https") ? "https" : "http";
          await snsClient.send(new SubscribeCommand({
            TopicArn: topicArn,
            Protocol: protocol,
            Endpoint: webhookUrl.trim()
          }));
          console.log(`[MIRAGE] Successfully subscribed webhook ${webhookUrl} to SNS!`);
        }

      } else {
        console.warn(`[MIRAGE] Could not find SNSTopicArn output to subscribe endpoints.`);
      }
    } else {
      console.log(`[MIRAGE] No email or webhook provided, skipping SNS subscription.`);
    }

    return NextResponse.json(
      { message: "Hub Deployment completed successfully!" },
      { status: 200 }
    );

  } catch (error: any) {
    console.error("[MIRAGE] Deployment Error:", error);
    return NextResponse.json(
      { error: error.message || "An unexpected error occurred during deployment." },
      { status: 500 }
    );
  }
}
