import { NextResponse } from 'next/server';
import { STSClient, AssumeRoleCommand } from '@aws-sdk/client-sts';
import { exec } from 'child_process';
import path from 'path';
import { getInventory, overwriteInventory, getRules, saveRuleState } from '@/lib/db';
import util from 'util';
import { appendHistory } from '@/lib/history';

const execAsync = util.promisify(exec);

export async function POST(req: Request) {
  try {
    const { scenarios, forwardingRoleArn } = await req.json();

    if (!scenarios || !Array.isArray(scenarios)) {
      return NextResponse.json({ error: 'Missing required fields or incorrect format' }, { status: 400 });
    }

    console.log(`Starting bulk teardown of ${scenarios.length} scenarios...`);

    // Group scenarios by unique Role ARN so we don't spam STS AssumeRole requests
    const roleGroups: Record<string, typeof scenarios> = {};
    for (const s of scenarios) {
      if (!s.roleArn) {
        console.warn(`Missing Role ARN for scenario ${s.scenarioId}, skipping.`);
        continue;
      }
      if (!roleGroups[s.roleArn]) roleGroups[s.roleArn] = [];
      roleGroups[s.roleArn].push(s);
    }

    for (const roleArn of Object.keys(roleGroups)) {
      console.log(`Assuming role for teardown operations: ${roleArn}`);
      
      const stsClient = new STSClient({ region: 'us-east-1' });
      const assumeRoleCommand = new AssumeRoleCommand({
        RoleArn: roleArn,
        RoleSessionName: 'MiragePlusSpokeTeardown',
      });

      let sdkCredentials;
      let tfCredentials;
      try {
        const stsResponse = await stsClient.send(assumeRoleCommand);
        sdkCredentials = {
          accessKeyId: stsResponse.Credentials?.AccessKeyId!,
          secretAccessKey: stsResponse.Credentials?.SecretAccessKey!,
          sessionToken: stsResponse.Credentials?.SessionToken,
        };
        tfCredentials = {
          AWS_ACCESS_KEY_ID: stsResponse.Credentials?.AccessKeyId,
          AWS_SECRET_ACCESS_KEY: stsResponse.Credentials?.SecretAccessKey,
          AWS_SESSION_TOKEN: stsResponse.Credentials?.SessionToken,
        };
        console.log(`Successfully assumed role: ${roleArn}`);
      } catch (stsError: any) {
        console.error(`STS AssumeRole failed for ${roleArn}:`, stsError);
        return NextResponse.json({ error: `Failed to assume spoke role: ${stsError.message}` }, { status: 403 });
      }

      const scriptPath = path.join(process.cwd(), 'src', 'scripts', 'remove-spoke.sh');

      for (const scenario of roleGroups[roleArn]) {
        console.log(`Starting cleanup and teardown for ${scenario.scenarioId} in account ${scenario.accountId}...`);

        // 1. Clean up local EventBridge rule state
        try {
          const inventory = await getInventory();
          const scenarioResources = inventory.filter(r => r.accountId === scenario.accountId && r.scenarioId === scenario.scenarioId);
          
          if (scenarioResources.length > 0) {
            // Group resources by ruleName
            const ruleGroups: Record<string, typeof scenarioResources> = {};
            for (const res of scenarioResources) {
              if (!ruleGroups[res.ruleName]) ruleGroups[res.ruleName] = [];
              ruleGroups[res.ruleName].push(res);
            }

            const allRules = await getRules(scenario.accountId);
            const typeMapping: Record<string, string> = {
              s3: 'bucketName', secretsmanager: 'secretId', sts: 'roleName', ssm: 'name', iam: 'roleName',
              ecr: 'repositoryName', lambda: 'functionName', dynamodb: 'tableName', sqs: 'queueUrl',
              sns: 'topicArn', kms: 'keyId', cloudformation: 'stackName'
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

            // Remove scenario resources from inventory first so we can recalculate sources
            const updatedInventory = inventory.filter(r => !(r.accountId === scenario.accountId && r.scenarioId === scenario.scenarioId));
            await overwriteInventory(updatedInventory);

            for (const [ruleName, resources] of Object.entries(ruleGroups)) {
              const ruleRecord = allRules.find(r => r.ruleName === ruleName);
              if (ruleRecord && ruleRecord.eventPattern) {
                try {
                  const parsed = JSON.parse(ruleRecord.eventPattern);
                  if (parsed.detail?.requestParameters?.$or) {
                    const conditions = parsed.detail.requestParameters.$or;
                    for (const res of resources) {
                      const key = typeMapping[res.decoyCategory] || res.decoyCategory;
                      removeCondition(conditions, key, res.decoyName);
                    }
                    
                    const remainingForRule = updatedInventory.filter(r => r.ruleName === ruleName);
                    if (remainingForRule.length === 0) {
                      // Rule has NO active scenarios. Delete it completely.
                      try {
                        const { EventBridgeClient, RemoveTargetsCommand, DeleteRuleCommand } = await import('@aws-sdk/client-eventbridge');
                        const ebClient = new EventBridgeClient({ region: 'us-west-2', credentials: sdkCredentials });
                        try {
                          await ebClient.send(new RemoveTargetsCommand({ Rule: ruleName, Ids: ["V2CentralBus"] }));
                          await ebClient.send(new DeleteRuleCommand({ Name: ruleName }));
                          console.log(`Deleted empty rule ${ruleName} from EventBridge`);
                          await appendHistory({
                            sessionId: Date.now().toString(),
                            type: 'rule_teardown',
                            scenarioId: scenario.scenarioId,
                            scenarioName: scenario.scenarioId,
                            accountId: scenario.accountId,
                            ruleName: ruleName,
                            status: 'success'
                          });
                        } catch (ebErr: any) {
                          if (ebErr.name !== 'ResourceNotFoundException') {
                            console.error(`Failed to delete empty rule ${ruleName} from EventBridge:`, ebErr);
                            await appendHistory({
                              sessionId: Date.now().toString(),
                              type: 'rule_teardown',
                              scenarioId: scenario.scenarioId,
                              scenarioName: scenario.scenarioId,
                              accountId: scenario.accountId,
                              ruleName: ruleName,
                              status: 'failed',
                              error: ebErr.message
                            });
                          }
                        }

                        // Cleanup Trust Policy
                        if (forwardingRoleArn) {
                          try {
                            const { IAMClient, GetRoleCommand, UpdateAssumeRolePolicyCommand } = await import('@aws-sdk/client-iam');
                            const iamClient = new IAMClient({ region: 'us-east-1', credentials: sdkCredentials });
                            const roleNameMatch = forwardingRoleArn.match(/\/([^/]+)$/);
                            if (roleNameMatch) {
                              const iamRoleName = roleNameMatch[1];
                              const getRoleResponse = await iamClient.send(new GetRoleCommand({ RoleName: iamRoleName }));
                              if (getRoleResponse.Role?.AssumeRolePolicyDocument) {
                                const policyDocString = decodeURIComponent(getRoleResponse.Role.AssumeRolePolicyDocument);
                                const policyDoc = JSON.parse(policyDocString);
                                let modified = false;
                                const ruleArn = `arn:aws:events:us-west-2:${scenario.accountId}:rule/${ruleName}`;

                                for (let i = policyDoc.Statement.length - 1; i >= 0; i--) {
                                  const statement = policyDoc.Statement[i];
                                  if (statement.Principal?.Service === "events.amazonaws.com" || 
                                      (Array.isArray(statement.Principal?.Service) && statement.Principal.Service.includes("events.amazonaws.com"))) {
                                    if (statement.Condition && (statement.Condition.ArnEquals || statement.Condition.StringEquals)) {
                                      const arnEquals = statement.Condition.ArnEquals || statement.Condition.StringEquals;
                                      if (arnEquals["aws:SourceArn"]) {
                                        const sourceArns = Array.isArray(arnEquals["aws:SourceArn"]) ? arnEquals["aws:SourceArn"] : [arnEquals["aws:SourceArn"]];
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
                                    RoleName: iamRoleName,
                                    PolicyDocument: JSON.stringify(policyDoc)
                                  }));
                                  console.log(`Removed rule ${ruleArn} from trust policy of ${iamRoleName}`);
                                  await appendHistory({
                                    sessionId: Date.now().toString(),
                                    type: 'trust_policy_teardown',
                                    scenarioId: scenario.scenarioId,
                                    scenarioName: scenario.scenarioId,
                                    accountId: scenario.accountId,
                                    ruleName: ruleName,
                                    status: 'success'
                                  });
                                }
                              }
                            }
                          } catch (iamErr: any) {
                            console.error(`Failed to clean up trust policy for rule ${ruleName}:`, iamErr);
                            await appendHistory({
                              sessionId: Date.now().toString(),
                              type: 'trust_policy_teardown',
                              scenarioId: scenario.scenarioId,
                              scenarioName: scenario.scenarioId,
                              accountId: scenario.accountId,
                              ruleName: ruleName,
                              status: 'failed',
                              error: iamErr.message
                            });
                          }
                        }

                        // To delete a rule from DB, we need a new helper or we overwrite rules array.
                        // Let's just set status to deleted and eventPattern to empty.
                        ruleRecord.status = 'deleted';
                        ruleRecord.eventPattern = "";
                      } catch (err: any) {
                        console.error("Error processing empty rule:", err);
                      }
                    } else {
                      const activeSources = new Set(remainingForRule.map(r => `aws.${r.decoyCategory}`));
                      parsed.source = Array.from(activeSources);
                      ruleRecord.eventPattern = JSON.stringify(parsed, null, 2);
                      ruleRecord.charCount = ruleRecord.eventPattern.length;
                      if (ruleRecord.status === 'deployed') {
                        ruleRecord.status = 'update_available';
                      }
                    }
                    if (ruleRecord.status !== 'deleted') {
                      await saveRuleState(ruleRecord);
                    } else {
                      // Actually, let's write a quick trick to delete the rule:
                      const fs = await import('fs/promises');
                      const path = await import('path');
                      const dbPath = path.join(process.cwd(), 'db_rules.json');
                      try {
                        const data = await fs.readFile(dbPath, 'utf8');
                        const r = JSON.parse(data);
                        const newR = r.filter((x: any) => x.ruleName !== ruleName);
                        await fs.writeFile(dbPath, JSON.stringify(newR, null, 2));
                      } catch (e) {}
                    }
                  }
                } catch (e) {
                  console.error(`Failed to parse event pattern for ${ruleName}`, e);
                }
              }
            }

          }
        } catch (dbErr: any) {
          console.error(`Failed to cleanup DB state for ${scenario.scenarioId}:`, dbErr);
          // Proceed with terraform destroy anyway
        }

        // 2. Terraform Destroy
        console.log(`Executing Terraform Destroy for ${scenario.scenarioId}...`);
        try {
          const { stdout, stderr } = await execAsync(`bash "${scriptPath}" ${scenario.scenarioId} ${scenario.accountId}`, {
            env: {
              ...process.env,
              ...tfCredentials,
              AWS_DEFAULT_REGION: 'us-west-2',
              AWS_REGION: 'us-west-2'
            }
          });
          console.log(`Successfully destroyed ${scenario.scenarioId}:\n`, stdout);
          await appendHistory({
            sessionId: Date.now().toString(),
            type: 'scenario_teardown',
            scenarioId: scenario.scenarioId,
            scenarioName: scenario.scenarioId,
            accountId: scenario.accountId,
            status: 'success',
          });
        } catch (destroyErr: any) {
          console.error(`Teardown failed for ${scenario.scenarioId}:\n`, destroyErr.stderr || destroyErr.message);
          await appendHistory({
            sessionId: Date.now().toString(),
            type: 'scenario_teardown',
            scenarioId: scenario.scenarioId,
            scenarioName: scenario.scenarioId,
            accountId: scenario.accountId,
            status: 'failed',
            error: destroyErr.message
          });
          return NextResponse.json({ error: `Teardown failed for ${scenario.scenarioId}: ${destroyErr.message}` }, { status: 500 });
        }
      }
    }

    return NextResponse.json({ success: true, message: `Tore down ${scenarios.length} scenarios successfully.` });

  } catch (error) {
    console.error("Error in /api/remove-spoke:", error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
