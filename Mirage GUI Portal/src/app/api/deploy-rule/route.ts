import { NextResponse } from 'next/server';
import { STSClient, AssumeRoleCommand } from '@aws-sdk/client-sts';
import { EventBridgeClient, PutRuleCommand, PutTargetsCommand } from '@aws-sdk/client-eventbridge';
import { getRules, saveRuleState, getInventory } from '@/lib/db';
import { appendHistory } from '@/lib/history';

export async function POST(req: Request) {
  try {
    const { accountId, roleArn, hubBusArn, forwardingRoleArn, ruleName, eventPattern, sessionId } = await req.json();

    if (!accountId || !roleArn || !hubBusArn || !forwardingRoleArn || !ruleName || !eventPattern) {
      return NextResponse.json({ error: 'Missing required fields' }, { status: 400 });
    }

    console.log(`Starting rule deployment for ${ruleName} in account ${accountId}`);

    // 1. Assume Spoke Role
    const stsClient = new STSClient({ region: 'us-east-1' });
    const assumeRoleCommand = new AssumeRoleCommand({
      RoleArn: roleArn,
      RoleSessionName: 'MiragePlusRuleDeployment',
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

    // 2. Deploy EventBridge Rule
    try {
      const ebClient = new EventBridgeClient({ region: 'us-west-2', credentials });
      
      await ebClient.send(new PutRuleCommand({
        Name: ruleName,
        EventPattern: JSON.stringify(JSON.parse(eventPattern)),
        State: "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"
      }));
      
      await ebClient.send(new PutTargetsCommand({
        Rule: ruleName,
        Targets: [{ Id: "V2CentralBus", Arn: hubBusArn, RoleArn: forwardingRoleArn }]
      }));
      
      console.log(`Successfully deployed rule ${ruleName} to AWS.`);
    } catch (awsError: any) {
      console.error("AWS EventBridge Error:", awsError);
      const rules = await getRules(accountId);
      const ruleRecord = rules.find(r => r.ruleName === ruleName);
      if (ruleRecord) {
        ruleRecord.status = 'failed';
        await saveRuleState(ruleRecord);
      }
      // Resolve which scenarios this rule belongs to for history
      const inventory = await getInventory();
      const scenariosInRule = [...new Set(inventory.filter(i => i.ruleName === ruleName).map(i => i.scenarioId))];
      for (const scenarioId of scenariosInRule.length > 0 ? scenariosInRule : ['unknown']) {
        await appendHistory({
          sessionId: sessionId || Date.now().toString(),
          type: 'rule_push',
          scenarioId,
          scenarioName: scenarioId,
          accountId,
          ruleName,
          status: 'failed',
          error: awsError.message,
        });
      }
      return NextResponse.json({ error: `AWS EventBridge deployment failed: ${awsError.message}` }, { status: 500 });
    }

    // 3. Update local DB
    const rules = await getRules(accountId);
    const ruleRecord = rules.find(r => r.ruleName === ruleName);
    if (ruleRecord) {
      ruleRecord.status = 'deployed';
      ruleRecord.eventPattern = eventPattern;
      ruleRecord.deployedPattern = eventPattern; // snapshot for diff comparison
      ruleRecord.charCount = eventPattern.length;
      await saveRuleState(ruleRecord);
    }

    // 4. Log rule_push success to history (one entry per scenario in this rule)
    const inventory = await getInventory();
    const scenariosInRule = [...new Set(inventory.filter(i => i.ruleName === ruleName).map(i => i.scenarioId))];
    for (const scenarioId of scenariosInRule.length > 0 ? scenariosInRule : ['unknown']) {
      await appendHistory({
        sessionId: sessionId || Date.now().toString(),
        type: 'rule_push',
        scenarioId,
        scenarioName: scenarioId,
        accountId,
        ruleName,
        status: 'success',
      });
    }

    // 5. Update Trust Policy
    try {
      const { IAMClient, GetRoleCommand, UpdateAssumeRolePolicyCommand } = await import('@aws-sdk/client-iam');
      const iamClient = new IAMClient({ region: 'us-east-1', credentials });
      const roleNameMatch = forwardingRoleArn.match(/\/([^/]+)$/);
      if (roleNameMatch) {
        const roleName = roleNameMatch[1];
        const getRoleResponse = await iamClient.send(new GetRoleCommand({ RoleName: roleName }));
        if (getRoleResponse.Role?.AssumeRolePolicyDocument) {
          // AWS IAM returns the policy document as a URL-encoded JSON string
          const policyDocString = decodeURIComponent(getRoleResponse.Role.AssumeRolePolicyDocument);
          const policyDoc = JSON.parse(policyDocString);
          
          let modified = false;
          const ruleArn = `arn:aws:events:us-west-2:${accountId}:rule/${ruleName}`;

          for (const statement of policyDoc.Statement) {
            if (statement.Principal?.Service === "events.amazonaws.com" || 
                (Array.isArray(statement.Principal?.Service) && statement.Principal.Service.includes("events.amazonaws.com"))) {
              
              if (!statement.Condition) {
                statement.Condition = {};
              }
              if (!statement.Condition.ArnEquals) {
                if (statement.Condition.StringEquals) {
                   statement.Condition.ArnEquals = statement.Condition.StringEquals;
                   delete statement.Condition.StringEquals;
                } else {
                   statement.Condition.ArnEquals = {};
                }
              }
              if (!statement.Condition.ArnEquals["aws:SourceArn"]) {
                statement.Condition.ArnEquals["aws:SourceArn"] = [];
              }
              
              const sourceArns = Array.isArray(statement.Condition.ArnEquals["aws:SourceArn"]) 
                ? statement.Condition.ArnEquals["aws:SourceArn"] 
                : [statement.Condition.ArnEquals["aws:SourceArn"]];
                
              if (!sourceArns.includes(ruleArn)) {
                sourceArns.push(ruleArn);
                statement.Condition.ArnEquals["aws:SourceArn"] = sourceArns;
                modified = true;
              }
            }
          }

          if (modified) {
            await iamClient.send(new UpdateAssumeRolePolicyCommand({
              RoleName: roleName,
              PolicyDocument: JSON.stringify(policyDoc)
            }));
            
            console.log(`Updated trust policy for ${roleName} with new rule ${ruleArn}`);
            
            for (const scenarioId of scenariosInRule.length > 0 ? scenariosInRule : ['unknown']) {
              await appendHistory({
                sessionId: sessionId || Date.now().toString(),
                type: 'trust_policy_update',
                scenarioId,
                scenarioName: scenarioId,
                accountId,
                ruleName,
                status: 'success',
              });
            }
          }
        }
      }
    } catch (iamError: any) {
      console.error("Failed to update IAM Trust Policy:", iamError);
      // We don't fail the whole deployment if just the trust policy update fails, 
      // but we log it to history
      for (const scenarioId of scenariosInRule.length > 0 ? scenariosInRule : ['unknown']) {
        await appendHistory({
          sessionId: sessionId || Date.now().toString(),
          type: 'trust_policy_update',
          scenarioId,
          scenarioName: scenarioId,
          accountId,
          ruleName,
          status: 'failed',
          error: iamError.message,
        });
      }
    }

    return NextResponse.json({ success: true, message: `Deployed rule ${ruleName} successfully.` });
  } catch (error) {
    console.error("Error in /api/deploy-rule:", error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
