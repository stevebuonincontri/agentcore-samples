#!/usr/bin/env bash
# Verifies Getting Started prerequisites. Read-only: creates nothing in AWS or on disk.
# Usage: ./verify-prereqs.sh   (run from this folder; reads ./.env)
cd "$(dirname "$0")" || exit 1
export AWS_PAGER=""
fail=0
ok()   { printf '  [ok]   %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=1; }

[ -f .env ] || { echo "Missing .env - run: cp .env.example .env"; exit 1; }
set -a; . ./.env; set +a
echo "Profile: ${AWS_PROFILE:?}  Region: ${AWS_REGION:?}"

echo "Tools"
node -e 'process.exit(+process.versions.node.split(".")[0] >= 20 ? 0 : 1)' 2>/dev/null \
  && ok "Node $(node -v)" || bad "Node 20+ required (nvm install 20 && nvm use 20)"
command -v uv >/dev/null && ok "$(uv --version)" || bad "uv missing"
command -v aws >/dev/null && ok "$(aws --version 2>&1 | cut -d' ' -f1)" || bad "AWS CLI missing"
command -v git >/dev/null && ok "$(git --version)" || bad "git missing"
if command -v agentcore >/dev/null && agentcore --version 2>/dev/null | head -1 | grep -q '^0\.'; then
  ok "AgentCore CLI $(agentcore --version 2>/dev/null | head -1)"
else
  bad "AgentCore CLI v0 required: npm install -g @aws/agentcore@0.30.0 (is a Python venv shadowing it? run: deactivate)"
fi

echo "AWS"
if id=$(aws sts get-caller-identity --query '[Account,Arn]' --output text 2>&1); then
  ok "Credentials valid: $id"
else
  bad "sts get-caller-identity failed: $id"
fi
n=$(aws bedrock list-foundation-models --by-provider anthropic --query 'length(modelSummaries)' --output text 2>&1) \
  && ok "Bedrock reachable, $n Anthropic models listed in $AWS_REGION" || bad "Bedrock list-foundation-models failed: $n"
aws bedrock-agentcore-control list-agent-runtimes --max-results 1 >/dev/null 2>&1 \
  && ok "AgentCore control plane reachable" || bad "AgentCore API not reachable in $AWS_REGION"
aws cloudformation list-stacks --max-items 1 >/dev/null 2>&1 \
  && ok "CloudFormation access" || bad "CloudFormation access denied"

echo
[ "$fail" -eq 0 ] && echo "All prerequisites OK. Ready for Step 1." || echo "Some checks failed."
exit "$fail"
