#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# session.sh — start or stop a lab session
# Destroys expensive resources at end of day, recreates them next session
#
# Usage:
#   ./scripts/session.sh up    — bring up all billable resources
#   ./scripts/session.sh down  — destroy all billable resources
#   ./scripts/session.sh disable-guardduty  — disable GuardDuty to stop costs
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Add new lab directories and their expensive resources here as you progress
declare -A LAB_TARGETS=(
  ["projects/01-vpc-foundation"]="aws_nat_gateway.main aws_eip.nat"
  ["projects/02-resilient-data"]="aws_db_instance.mysql aws_elasticache_cluster.redis"
)

usage() {
  echo "Usage: $0 [up|down|disable-guardduty]"
  echo ""
  echo "  up              Recreate billable resources for today's session"
  echo "  down            Destroy billable resources to stop the cost clock"
  echo "  disable-guardduty Disable GuardDuty to stop costs"
  exit 1
}

session_up() {
  echo "==> Starting lab session..."
  for lab in "${!LAB_TARGETS[@]}"; do
    local targets="${LAB_TARGETS[$lab]}"
    local target_args=""
    for t in $targets; do
      target_args="$target_args -target=$t"
    done

    echo ""
    echo "--> Bringing up: $lab"
    echo "    Resources: $targets"
    cd "$REPO_ROOT/$lab"
    terraform apply $target_args --auto-approve
  done
  echo ""
  echo "==> Session ready."
}

session_down() {
  echo "==> Ending lab session..."
  for lab in "${!LAB_TARGETS[@]}"; do
    local targets="${LAB_TARGETS[$lab]}"
    local target_args=""
    for t in $targets; do
      target_args="$target_args -target=$t"
    done

    echo ""
    echo "--> Tearing down: $lab"
    echo "    Resources: $targets"
    cd "$REPO_ROOT/$lab"
    terraform destroy $target_args --auto-approve
  done
  echo ""
  echo "==> Session ended. Cost clock stopped."
}

# Add this function to session.sh
disable_guardduty() {
  echo "==> Disabling GuardDuty (post-trial cost control)..."
  cd "$REPO_ROOT/projects/03-observability"

  terraform destroy \
    -target=aws_guardduty_detector_feature.s3_logs \
    -target=aws_guardduty_detector_feature.malware_protection \
    -target=aws_guardduty_detector.main \
    --auto-approve

  echo ""
  echo "==> GuardDuty disabled. Run 'terraform apply' in 03-observability to re-enable."
}


# Require AWS_PROFILE to be set so you never run as wrong identity
if [[ -z "${AWS_PROFILE:-}" ]]; then
  echo "ERROR: AWS_PROFILE is not set."
  echo "       Run: export AWS_PROFILE=aws-arch-lab-deployer"
  exit 1
fi

case "${1:-}" in
  up)   session_up ;;
  down) session_down ;;
  disable-guardduty) disable_guardduty ;;
  *)    usage ;;
esac
