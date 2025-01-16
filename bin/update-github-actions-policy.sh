#!/bin/bash

# Get the policy ARN from the policy name
POLICY_NAME="github-actions-policy"
POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text)

if [ -z "$POLICY_ARN" ]; then
    echo "Error: Could not find policy named '${POLICY_NAME}'"
    exit 1
fi

# Clean up old versions first (keep only the default version)
echo "Cleaning up old policy versions..."
OLD_VERSIONS=$(aws iam list-policy-versions \
    --policy-arn "$POLICY_ARN" \
    --query "Versions[?!IsDefaultVersion].VersionId" \
    --output text)

for VERSION in $OLD_VERSIONS; do
    echo "Deleting version: $VERSION"
    aws iam delete-policy-version \
        --policy-arn "$POLICY_ARN" \
        --version-id "$VERSION"
done

# Update the policy
echo "Updating policy from github-actions-policy.json..."
aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document file://github-actions-policy.json \
    --set-as-default

if [ $? -eq 0 ]; then
    echo "Successfully updated policy"
else
    echo "Failed to update policy"
    exit 1
fi 