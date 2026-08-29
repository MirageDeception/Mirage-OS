# scenario-7

Description: Deception Scenario 7 - Lambda Code Injection. Adds InvokeFunction and UpdateFunctionCode permissions to the discovery role, enabling an attacker to inject code into the Lambda function and steal the execution role's temporary credentials. Can link to Scenario 6 or deploy standalone.

**Resources Deployed:**
- `lambda-inject-readonly-role` (aws_iam_role)
- `lambda-inject-readonly-policy` (aws_iam_role_policy)
- `prod-data-inject-exec-role` (aws_iam_role)
- `prod-data-inject-exec-policy` (aws_iam_role_policy)
- `prod-data-inject-processor` (aws_lambda_function)
- `lambda-code-inject-policy` (aws_iam_role_policy)
