#!/bin/bash
# Non-interactive full Kong AI Gateway showcase (OpenBao + monitoring + Kuma).
# Usage, env vars and prerequisites: docs/showcases/kong-ai-gateway.md
set -o errexit

cd "$(dirname "$0")" || exit 1

export NON_INTERACTIVE=1
export DEPLOY_OPENBAO="${DEPLOY_OPENBAO:-y}"
export DEPLOY_MONITORING="${DEPLOY_MONITORING:-y}"
export DEPLOY_KUMA="${DEPLOY_KUMA:-y}"

echo "Setting up the complete Kong AI Gateway showcase (non-interactive):"
echo "  OpenBao + cert-manager : ${DEPLOY_OPENBAO}"
echo "  Monitoring stack       : ${DEPLOY_MONITORING}"
echo "  Kuma service mesh      : ${DEPLOY_KUMA}"
echo "  Gemini provider        : $([ -n "${GEMINI_API_KEY:-}" ] && echo enabled || echo 'skipped (set GEMINI_API_KEY)')"
echo "  Anthropic provider     : $([ -n "${ANTHROPIC_API_KEY:-}" ] && echo enabled || echo 'skipped (set ANTHROPIC_API_KEY)')"
echo "  Enterprise (license)   : $([ -f license.json ] && echo detected || echo 'not present')"
echo ""

bash setup.sh
