resource "aws_cloudwatch_event_bus" "deception_bus" {
  name = var.event_bus_name
}

resource "aws_sns_topic" "alerts" {
  name = var.sns_topic_name
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "brain_role" {
  name               = "${var.lambda_function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.brain_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_sns_publish" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "lambda_sns_publish" {
  name   = "sns-publish"
  role   = aws_iam_role.brain_role.id
  policy = data.aws_iam_policy_document.lambda_sns_publish.json
}

data "archive_file" "brain_zip" {
  type        = "zip"
  output_path = "${path.module}/brain.zip"
  source {
    content  = <<EOF
import json
import os
import boto3

sns = boto3.client('sns')

def handler(event, context):
    print("Received event: " + json.dumps(event))
    
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    message = f"🚨 DECEPTION ALERT 🚨\n\nEvent: {json.dumps(event, indent=2)}"
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Subject="Mirage Deception Alert",
            Message=message
        )
    except Exception as e:
        print(f"Error publishing to SNS: {e}")
        
    return {"statusCode": 200, "body": "Alert processed"}
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "brain" {
  filename         = data.archive_file.brain_zip.output_path
  function_name    = var.lambda_function_name
  role             = aws_iam_role.brain_role.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.brain_zip.output_base64sha256
  runtime          = "python3.9"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Allow EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.brain.function_name
  principal     = "events.amazonaws.com"
  source_arn    = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/${aws_cloudwatch_event_bus.deception_bus.name}/*"
}
