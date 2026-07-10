terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────
# IAM Role — mirage-forwarding-role
#   Trust: EventBridge service principal (spoke → hub bus forwarding)
#   Permission: PutEvents on the hub EventBus only
# ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "mirage_forwarding" {
  name        = var.forwarding_role_name
  description = "Mirage CLI: EventBridge uses this to forward spoke events to hub bus"
  path        = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EventBridgeAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name          = var.forwarding_role_name
    ManagedBy     = "mirage"
    SpokeAlias    = var.spoke_alias
    DeceptionRole = "forwarding"
  }
}

# Permission: PutEvents on the hub EventBus ONLY (least privilege).
resource "aws_iam_role_policy" "mirage_forwarding_permissions" {
  name = "mirage-event-forwarding"
  role = aws_iam_role.mirage_forwarding.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PutEventsToHubBus"
        Effect = "Allow"
        Action = ["events:PutEvents"]
        Resource = [
          "arn:aws:events:${var.hub_region}:${var.hub_account_id}:event-bus/${var.hub_event_bus_name}"
        ]
      }
    ]
  })
}
