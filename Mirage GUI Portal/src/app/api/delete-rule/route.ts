import { NextResponse } from 'next/server';
import { STSClient, AssumeRoleCommand } from '@aws-sdk/client-sts';
import { EventBridgeClient, DeleteRuleCommand, RemoveTargetsCommand } from '@aws-sdk/client-eventbridge';
import { getRules, saveRuleState } from '@/lib/db';
import fs from 'fs/promises';
import path from 'path';

export async function POST(req: Request) {
  try {
    const { accountId, roleArn, ruleName, forwardingRoleArn } = await req.json();

    if (!accountId || !roleArn || !ruleName) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 });
    }

    const rules = await getRules(accountId);
    const ruleRecord = rules.find(r => r.ruleName === ruleName);
    
    if (!ruleRecord) {
      return NextResponse.json({ error: 'Rule not found locally' }, { status: 404 });
    }

    if (ruleRecord.status === 'deployed' || ruleRecord.status === 'update_available' || ruleRecord.status === 'failed') {
      console.log(`Deleting rule ${ruleName} from AWS Account ${accountId}`);

      const stsClient = new STSClient({ region: 'us-east-1' });
      const assumeRoleCommand = new AssumeRoleCommand({
        RoleArn: roleArn,
        RoleSessionName: 'MiragePlusRuleDeletion',
      });
      
      let credentials;
      try {
        const stsResponse = await stsClient.send(assumeRoleCommand);
        credentials = {
          accessKeyId: stsResponse.Credentials?.AccessKeyId!,
          secretAccessKey: stsResponse.Credentials?.SecretAccessKey!,
          sessionToken: stsResponse.Credentials?.SessionToken,
        };
      } catch (stsError: any) {
        console.error("STS AssumeRole failed:", stsError);
        return NextResponse.json({ error: `Failed to assume spoke role: ${stsError.message}` }, { status: 403 });
      }

      try {
        const ebClient = new EventBridgeClient({ region: 'us-west-2', credentials });
        
        // AWS requires targets to be removed before a rule can be deleted
        await ebClient.send(new RemoveTargetsCommand({
          Rule: ruleName,
          Ids: ["V2CentralBus"] // Hardcoded target ID from deploy-rule/route.ts
        }));
        
        await ebClient.send(new DeleteRuleCommand({
          Name: ruleName
        }));
        console.log(`Successfully deleted rule ${ruleName} from AWS.`);
      } catch (awsError: any) {
        // If the rule or target doesn't exist, ignore the error and proceed to local cleanup
        if (awsError.name !== 'ResourceNotFoundException') {
          console.error("AWS EventBridge Error:", awsError);
          return NextResponse.json({ error: `AWS EventBridge deletion failed: ${awsError.message}` }, { status: 500 });
        }
      }

      // Cleanup Trust Policy if forwardingRoleArn is provided
      if (forwardingRoleArn) {
        try {
          const { IAMClient, GetRoleCommand, UpdateAssumeRolePolicyCommand } = await import('@aws-sdk/client-iam');
          const iamClient = new IAMClient({ region: 'us-east-1', credentials });
          const roleNameMatch = forwardingRoleArn.match(/\/([^/]+)$/);
          if (roleNameMatch) {
            const roleName = roleNameMatch[1];
            const getRoleResponse = await iamClient.send(new GetRoleCommand({ RoleName: roleName }));
            if (getRoleResponse.Role?.AssumeRolePolicyDocument) {
              const policyDocString = decodeURIComponent(getRoleResponse.Role.AssumeRolePolicyDocument);
              const policyDoc = JSON.parse(policyDocString);
              let modified = false;
              const ruleArn = `arn:aws:events:us-west-2:${accountId}:rule/${ruleName}`;

              for (let i = policyDoc.Statement.length - 1; i >= 0; i--) {
                const statement = policyDoc.Statement[i];
                if (statement.Principal?.Service === "events.amazonaws.com" || 
                    (Array.isArray(statement.Principal?.Service) && statement.Principal.Service.includes("events.amazonaws.com"))) {
                  if (statement.Condition && (statement.Condition.ArnEquals || statement.Condition.StringEquals)) {
                    const arnEquals = statement.Condition.ArnEquals || statement.Condition.StringEquals;
                    if (arnEquals["aws:SourceArn"]) {
                      const sourceArns = Array.isArray(arnEquals["aws:SourceArn"]) 
                        ? arnEquals["aws:SourceArn"] 
                        : [arnEquals["aws:SourceArn"]];
                      
                      const filteredArns = sourceArns.filter((arn: string) => arn !== ruleArn);
                      if (filteredArns.length !== sourceArns.length) {
                        if (filteredArns.length === 0) {
                          delete arnEquals["aws:SourceArn"];
                          if (Object.keys(arnEquals).length === 0) {
                            if (statement.Condition.ArnEquals) delete statement.Condition.ArnEquals;
                            if (statement.Condition.StringEquals) delete statement.Condition.StringEquals;
                            if (Object.keys(statement.Condition).length === 0) {
                              policyDoc.Statement.splice(i, 1);
                            }
                          }
                        } else {
                          arnEquals["aws:SourceArn"] = filteredArns;
                        }
                        modified = true;
                      }
                    }
                  }
                }
              }

              if (modified) {
                await iamClient.send(new UpdateAssumeRolePolicyCommand({
                  RoleName: roleName,
                  PolicyDocument: JSON.stringify(policyDoc)
                }));
                console.log(`Removed rule ${ruleArn} from trust policy of ${roleName}`);
              }
            }
          }
        } catch (iamError: any) {
          console.error("Failed to clean up IAM Trust Policy:", iamError);
        }
      }
    }

    // Remove from local database
    const updatedRules = rules.filter(r => r.ruleName !== ruleName);
    const RULES_FILE = path.join(process.cwd(), 'db_rules.json');
    await fs.writeFile(RULES_FILE, JSON.stringify(updatedRules, null, 2));

    return NextResponse.json({ success: true, message: `Rule ${ruleName} deleted successfully.` });
  } catch (error) {
    console.error("Error in /api/delete-rule:", error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
