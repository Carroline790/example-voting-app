#!/usr/bin/env bash
set -euo pipefail

REGION=${1:-ap-south-1}

echo "=== Using AWS region: $REGION ==="

echo
echo "=== 1) Show EKS clusters in this region ==="
aws eks list-clusters --region "$REGION" || echo "aws eks list-clusters failed"

echo
echo "=== 2) Show eksctl clusters in this region (if any) ==="
eksctl get cluster --region "$REGION" || echo "no eksctl clusters found (ok)"

echo
echo "=== 3) Kubeconfig contexts BEFORE cleanup ==="
kubectl config get-contexts || echo "kubectl config get-contexts failed"

echo
echo "=== 4) Deleting dead EKS contexts from kubeconfig (those whose clusters no longer exist) ==="

# Get list of EKS clusters that still exist in this region
EXISTING_CLUSTERS_JSON=$(aws eks list-clusters --region "$REGION" --output json || echo '{"clusters": []}')
EXISTING_CLUSTERS=$(echo "$EXISTING_CLUSTERS_JSON" | jq -r '.clusters[]?')

# Get all kubeconfig contexts
CONTEXTS=$(kubectl config get-contexts -o name 2>/dev/null || true)

for ctx in $CONTEXTS; do
  # Only touch contexts that look like AWS EKS ARNs
  if [[ "$ctx" == arn:aws:eks:* ]]; then
    CLUSTER_NAME=$(echo "$ctx" | awk -F'/' '{print $NF}')
    if ! grep -q "^$CLUSTER_NAME$" <<< "$EXISTING_CLUSTERS"; then
      echo " - Context '$ctx' points to deleted EKS cluster '$CLUSTER_NAME'. Deleting context."
      kubectl config delete-context "$ctx" || true
      kubectl config delete-cluster "$ctx" || true
    else
      echo " - Context '$ctx' points to existing cluster '$CLUSTER_NAME' (keeping)."
    fi
  fi
done

echo
echo "=== 5) Kubeconfig contexts AFTER cleanup ==="
kubectl config get-contexts || echo "kubectl config get-contexts failed"

echo
echo "=== 6) Check for leftover AWS resources (you delete manually if needed) ==="

echo
echo "--- Load Balancers (ELBv2) in $REGION ---"
aws elbv2 describe-load-balancers --region "$REGION" --output table || echo "No ELBv2 load balancers or command failed"

echo
echo "--- Target Groups in $REGION ---"
aws elbv2 describe-target-groups --region "$REGION" --output table || echo "No target groups or command failed"

echo
echo "--- EBS Volumes in $REGION ---"
aws ec2 describe-volumes --region "$REGION" --output table || echo "No volumes or command failed"

echo
echo "--- Security Groups in $REGION ---"
aws ec2 describe-security-groups --region "$REGION" --output table || echo "No security groups or command failed"

echo
echo "--- CloudFormation stacks in $REGION ---"
aws cloudformation list-stacks --region "$REGION" --output table || echo "No stacks or command failed"

echo
echo "=== Done. Review the above resource lists and delete anything you know is safe to remove via the AWS console (or CLI). ==="
