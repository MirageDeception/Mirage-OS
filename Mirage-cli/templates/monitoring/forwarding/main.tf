data "aws_iam_policy_document" "forwarding_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "forwarding_role" {
  name               = "${var.rule_name}-role"
  assume_role_policy = data.aws_iam_policy_document.forwarding_assume_role.json
}

data "aws_iam_policy_document" "forwarding_policy" {
  statement {
    actions   = ["events:PutEvents"]
    resources = [var.hub_event_bus_arn]
  }
}

resource "aws_iam_role_policy" "forwarding_policy" {
  name   = "put-events-to-hub"
  role   = aws_iam_role.forwarding_role.id
  policy = data.aws_iam_policy_document.forwarding_policy.json
}

resource "aws_cloudwatch_event_rule" "cloudtrail_forwarder" {
  name        = "${var.rule_name}-cloudtrail"
  description = "Forward all CloudTrail events to Mirage Hub Bus"
  
  event_pattern = jsonencode({
    source = ["aws.cloudtrail"]
  })
}

resource "aws_cloudwatch_event_target" "hub_target_ct" {
  rule      = aws_cloudwatch_event_rule.cloudtrail_forwarder.name
  target_id = "MirageHubBus"
  arn       = var.hub_event_bus_arn
  role_arn  = aws_iam_role.forwarding_role.arn
}

resource "aws_cloudwatch_event_rule" "console_signin_forwarder" {
  name        = "${var.rule_name}-signin"
  description = "Forward all AWS Console Sign In events to Mirage Hub Bus"
  
  event_pattern = jsonencode({
    source = ["aws.signin"]
  })
}

resource "aws_cloudwatch_event_target" "hub_target_signin" {
  rule      = aws_cloudwatch_event_rule.console_signin_forwarder.name
  target_id = "MirageHubBus"
  arn       = var.hub_event_bus_arn
  role_arn  = aws_iam_role.forwarding_role.arn
}
