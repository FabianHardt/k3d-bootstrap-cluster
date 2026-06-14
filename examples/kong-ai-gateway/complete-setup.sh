#!/bin/bash
# complete-setup.sh — non-interactive, full Kong AI Gateway showcase.
#
# Runs setup.sh with every optional component enabled, no prompts:
#   - OpenBao + cert-manager   (TLS certificates)
#   - Grafana / Prometheus / Tempo monitoring (AI metrics + distributed tracing)
#   - Kuma service mesh        (mTLS between all components)
# on top of the always-on base (Ollama + llama3.2:1b, OpenWebUI, SearXNG MCP).
#
# Enterprise features (Keycloak OIDC, AI semantic cache, provider failover,
# extra local models) activate automatically when ./license.json is present.
#
# External providers stay opt-in — export the keys before running to wire
# them in:
#   GEMINI_API_KEY=... ANTHROPIC_API_KEY=... bash complete-setup.sh
#
# Each component can also be turned off individually, e.g.:
#   DEPLOY_KUMA=n bash complete-setup.sh
#
# Prerequisite: a bootstrapped cluster with Kong already installed
# (run ../../create-sample.sh first).
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
