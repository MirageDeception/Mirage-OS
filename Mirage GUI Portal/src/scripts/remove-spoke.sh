#!/bin/bash
set -e

SCENARIO_ID=$1
ACCOUNT_ID=$2

# Ensure we have the required arguments
if [ -z "$SCENARIO_ID" ] || [ -z "$ACCOUNT_ID" ]; then
    echo "Usage: remove-spoke.sh <scenario-id> <account-id>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
STATE_DIR="$PROJECT_ROOT/states/$ACCOUNT_ID/$SCENARIO_ID"

# Check if isolated directory exists (created during deployment)
if [ ! -d "$STATE_DIR" ]; then
    echo "Error: Deployment directory not found at $STATE_DIR. Cannot destroy."
    exit 1
fi

echo "Destroying $SCENARIO_ID from Spoke Account $ACCOUNT_ID using isolated state file..."

cd "$STATE_DIR"

# Destroy terraform with the required account variable
terraform destroy -auto-approve -var="account_id=$ACCOUNT_ID"

echo "Teardown for $SCENARIO_ID completed successfully!"

# Clean up the local isolated directory to keep the server clean
cd ..
rm -rf "$SCENARIO_ID"
