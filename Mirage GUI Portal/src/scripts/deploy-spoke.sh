#!/bin/bash
set -e

SCENARIO_ID=$1
ACCOUNT_ID=$2

# Ensure we have the required arguments
if [ -z "$SCENARIO_ID" ] || [ -z "$ACCOUNT_ID" ]; then
    echo "Usage: deploy-spoke.sh <scenario-id> <account-id>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
STATE_DIR="$PROJECT_ROOT/states/$ACCOUNT_ID/$SCENARIO_ID"

# Check if isolated directory exists (Node.js should have created it)
if [ ! -d "$STATE_DIR" ]; then
    echo "Error: Deployment directory not found at $STATE_DIR"
    exit 1
fi

echo "Deploying $SCENARIO_ID to Spoke Account $ACCOUNT_ID in isolated folder $STATE_DIR..."

cd "$STATE_DIR"

# Initialize terraform
terraform init -upgrade -input=false

# Apply terraform with the required account variable and any contextual UI variables
terraform apply -auto-approve -input=false -var="account_id=$ACCOUNT_ID"

echo "Deployment for $SCENARIO_ID completed successfully!"
