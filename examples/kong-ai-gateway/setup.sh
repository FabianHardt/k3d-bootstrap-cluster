#!/bin/bash
set -o errexit

LICENSE_FILE=license.json
GEMINI_ENABLED=false
ANTHROPIC_ENABLED=false
MONITORING_ENABLED=false

# --- Preconditions ---
echo "Checking prerequisites..."

KONG_NS=$(kubectl get ns kong 2>/dev/null || echo "false")
if [[ "${KONG_NS}" == "false" ]]; then
  echo "ERROR: Kong Ingress Controller not found."
  echo "Please run the kong-gateway example first:"
  echo "  cd ../kong-gateway && bash setup.sh"
  exit 1
fi

kubectl wait deployment kong-gateway -n kong --for=condition=Available=true --timeout=10s 2>/dev/null || {
  echo "ERROR: Kong Gateway deployment is not ready."
  exit 1
}

echo "Kong Ingress Controller found and ready."

# --- Namespace ---
kubectl create namespace ai-platform || true

# --- OpenBao + cert-manager (optional) ---
echo ""
read -r -p "Deploy OpenBao & cert-manager for TLS certificates? (y/N): " DEPLOY_OPENBAO

if [[ "${DEPLOY_OPENBAO}" =~ ^[Yy]$ ]]; then
  OPENBAO_EXISTS=$(kubectl get ns openbao 2>/dev/null || echo "false")
  if [[ "${OPENBAO_EXISTS}" == "false" ]]; then
    echo "Deploying OpenBao..."
    cd ../openbao/
    KONG_FLAG=Yes bash setup.sh
    cd ../kong-ai-gateway/
  else
    echo "OpenBao already deployed. Skipping."
  fi
fi

# --- Ollama (always deployed) ---
echo ""
echo "Deploying Ollama..."

kubectl apply -f ollama.yaml

echo "Waiting for Ollama to be ready..."
kubectl wait deployment ollama -n ai-platform --for=condition=Available=true --timeout=300s

echo "Pulling llama3.2:1b model (this may take a few minutes)..."
kubectl exec -n ai-platform deployment/ollama -- ollama pull llama3.2:1b

echo "Pulling nomic-embed-text embedding model for RAG..."
kubectl exec -n ai-platform deployment/ollama -- ollama pull nomic-embed-text

# Enterprise: Pull additional models for multi-model demo
if [[ -f ${LICENSE_FILE} ]]; then
  echo ""
  echo "Enterprise license detected — pulling additional local models..."
  echo "Pulling qwen2.5-coder:1.5b (code model, ~1GB)..."
  kubectl exec -n ai-platform deployment/ollama -- ollama pull qwen2.5-coder:1.5b

  echo "Pulling gemma3:1b (alternative chat model, ~815MB)..."
  kubectl exec -n ai-platform deployment/ollama -- ollama pull gemma3:1b

  echo "Ollama ready with llama3.2:1b, qwen2.5-coder:1.5b, gemma3:1b, and nomic-embed-text."
else
  echo "Ollama ready with llama3.2:1b and nomic-embed-text."
fi

# --- Gemini API Key (optional) ---
echo ""
read -r -s -p "Enter your Google Gemini API Key (optional, press Enter to skip): " GEMINI_API_KEY
echo ""

if [[ -n "${GEMINI_API_KEY}" ]]; then
  GEMINI_ENABLED=true
  GEMINI_SECRET_EXISTS=$(kubectl get secret gemini-api-key -n kong 2>/dev/null || echo "false")
  if [[ "${GEMINI_SECRET_EXISTS}" == "false" ]]; then
    kubectl create secret generic gemini-api-key \
      --namespace kong \
      --from-literal=api-key="${GEMINI_API_KEY}"
    echo "Gemini API Key secret created."
  else
    echo "Gemini API Key secret already exists. Updating..."
    kubectl delete secret gemini-api-key -n kong
    kubectl create secret generic gemini-api-key \
      --namespace kong \
      --from-literal=api-key="${GEMINI_API_KEY}"
  fi
fi

# --- Anthropic API Key (optional) ---
read -r -s -p "Enter your Anthropic API Key (optional, press Enter to skip): " ANTHROPIC_API_KEY
echo ""

if [[ -n "${ANTHROPIC_API_KEY}" ]]; then
  ANTHROPIC_ENABLED=true
  ANTHROPIC_SECRET_EXISTS=$(kubectl get secret anthropic-api-key -n kong 2>/dev/null || echo "false")
  if [[ "${ANTHROPIC_SECRET_EXISTS}" == "false" ]]; then
    kubectl create secret generic anthropic-api-key \
      --namespace kong \
      --from-literal=api-key="${ANTHROPIC_API_KEY}"
    echo "Anthropic API Key secret created."
  else
    echo "Anthropic API Key secret already exists. Updating..."
    kubectl delete secret anthropic-api-key -n kong
    kubectl create secret generic anthropic-api-key \
      --namespace kong \
      --from-literal=api-key="${ANTHROPIC_API_KEY}"
  fi
fi

# --- Kong env vault + API key env vars ---
HELM_EXTRA_ARGS=""
if [[ "${GEMINI_ENABLED}" == "true" ]]; then
  HELM_EXTRA_ARGS="${HELM_EXTRA_ARGS} --set gateway.customEnv.KONG_GEMINI_API_KEY.valueFrom.secretKeyRef.name=gemini-api-key --set gateway.customEnv.KONG_GEMINI_API_KEY.valueFrom.secretKeyRef.key=api-key"
fi
if [[ "${ANTHROPIC_ENABLED}" == "true" ]]; then
  HELM_EXTRA_ARGS="${HELM_EXTRA_ARGS} --set gateway.customEnv.KONG_ANTHROPIC_API_KEY.valueFrom.secretKeyRef.name=anthropic-api-key --set gateway.customEnv.KONG_ANTHROPIC_API_KEY.valueFrom.secretKeyRef.key=api-key"
fi

if [[ -n "${HELM_EXTRA_ARGS}" ]]; then
  echo "Configuring Kong env vault for API key references..."
  kubectl apply -f kong-vault-env.yaml
fi

# --- Kong Enterprise License (optional) ---
if [[ -f ${LICENSE_FILE} ]]; then
  echo ""
  echo "Kong Enterprise license found. Applying license..."

  echo "
apiVersion: configuration.konghq.com/v1alpha1
kind: KongLicense
metadata:
  name: kong-license
rawLicenseString: '$(cat "${LICENSE_FILE}")'
" | kubectl apply -f -

  echo "License applied."

  echo "Upgrading Kong with Enterprise features (Manager UI, Admin API)..."
  # shellcheck disable=SC2086
  helm upgrade kong kong/ingress --version 0.24.0 --values ../kong-gateway/values.yaml --namespace kong ${HELM_EXTRA_ARGS}
  kubectl wait deployment kong-gateway -n kong --for=condition=Available=true --timeout=120s

  echo "Applying Kong Manager and Admin routes..."
  kubectl apply -f ../kong-gateway/httproute-kong-manager.yaml

  # Add HTTP listener without hostname filter for internal cluster routes (OpenWebUI → Kong).
  # Gateway API listeners with hostname: *.example.com reject internal requests.
  echo "Adding internal HTTP listener to Gateway..."
  kubectl patch gateway kong -n kong --type=json -p='[
    {"op": "add", "path": "/spec/listeners/-", "value": {
      "name": "kong-http-internal",
      "port": 80,
      "protocol": "HTTP",
      "allowedRoutes": {"namespaces": {"from": "All"}}
    }}
  ]' 2>/dev/null || true

  echo "Kong Enterprise ready with Manager UI and Admin API."
fi

# --- Kong AI Plugins ---
echo ""
echo "Applying Kong AI Gateway plugins..."

kubectl apply -f kong-ai-plugins.yaml

if [[ "${GEMINI_ENABLED}" == "true" ]]; then
  echo "Applying Gemini AI proxy plugin..."
  kubectl apply -f kong-ai-plugin-gemini.yaml
fi

if [[ "${ANTHROPIC_ENABLED}" == "true" ]]; then
  echo "Applying Anthropic AI proxy plugin..."
  kubectl apply -f kong-ai-plugin-anthropic.yaml
fi

# Enterprise plugins (if license is present)
if [[ -f ${LICENSE_FILE} ]]; then
  echo "Applying Kong Enterprise AI plugins..."
  kubectl apply -f kong-ai-plugins-enterprise.yaml

  echo "Applying OIDC consumer mapping (key-auth OR OIDC token)..."
  kubectl apply -f kong-ai-oidc-plugin.yaml
  kubectl apply -f kong-ai-plugins-key-auth-anonymous.yaml

  # --- AI Proxy Advanced (Failover) ---
  echo ""
  echo "Building AI Proxy Advanced failover plugin..."

  FAILOVER_TARGETS='    - route_type: llm/v1/chat
      weight: 100
      model:
        provider: openai
        name: llama3.2:1b
        options:
          upstream_url: "http://ollama.ai-platform.svc.cluster.local:11434/v1/chat/completions"'

  if [[ "${GEMINI_ENABLED}" == "true" ]]; then
    FAILOVER_TARGETS="${FAILOVER_TARGETS}
    - route_type: llm/v1/chat
      weight: 50
      auth:
        param_name: key
        param_value: \"{vault://my-env/GEMINI_API_KEY}\"
        param_location: query
      model:
        provider: gemini
        name: gemini-2.5-flash"
  fi

  if [[ "${ANTHROPIC_ENABLED}" == "true" ]]; then
    FAILOVER_TARGETS="${FAILOVER_TARGETS}
    - route_type: llm/v1/chat
      weight: 10
      auth:
        header_name: x-api-key
        header_value: \"{vault://my-env/ANTHROPIC_API_KEY}\"
      model:
        provider: anthropic
        name: claude-haiku-3-5-20241022
        options:
          max_tokens: 4096
          anthropic_version: \"2023-06-01\""
  fi

  echo "apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: ai-proxy-advanced-failover
  namespace: kong
plugin: ai-proxy-advanced
config:
  balancer:
    algorithm: priority
    retries: 3
    max_fails: 2
    fail_timeout: 30000
    failover_criteria:
      - error
      - timeout
      - http_429
      - http_500
      - http_502
      - http_503
  targets:
${FAILOVER_TARGETS}" | kubectl apply -f -

  echo "Applying failover route..."
  kubectl apply -f kong-ai-route-failover.yaml

  echo "AI Gateway Failover enabled: Ollama$([ "${GEMINI_ENABLED}" == "true" ] && echo " → Gemini")$([ "${ANTHROPIC_ENABLED}" == "true" ] && echo " → Anthropic")"

  # --- AI Proxy Advanced (Multi-Model) ---
  echo ""
  echo "Applying AI Proxy Advanced multi-model plugin..."
  kubectl apply -f kong-ai-proxy-advanced-multimodel.yaml
  kubectl apply -f kong-ai-plugin-coder.yaml
  kubectl apply -f kong-ai-plugin-gemma.yaml

  echo "Applying multi-model routes..."
  kubectl apply -f kong-ai-route-coder.yaml
  kubectl apply -f kong-ai-route-coder-internal.yaml
  kubectl apply -f kong-ai-route-gemma.yaml
  kubectl apply -f kong-ai-route-gemma-internal.yaml
  kubectl apply -f kong-ai-route-models-extra.yaml

  echo "Updating model list for Enterprise (multi-model)..."
  kubectl apply -f kong-ai-models-response-enterprise.yaml
fi

# --- ACL Plugins ---
echo "Applying ACL plugins for consumer groups..."
kubectl apply -f kong-acl-plugins.yaml

# --- Kong Consumers ---
echo "Applying Kong Consumer configuration..."
kubectl apply -f kong-consumers.yaml

# --- AI Proxy Routes ---
echo "Applying AI Proxy HTTPRoutes..."
kubectl apply -f kong-ai-route.yaml
kubectl apply -f kong-ai-route-internal.yaml

# --- Per-user model filtering ---
echo "Applying per-user model filtering..."
kubectl apply -f kong-ai-models-filtered.yaml
kubectl apply -f kong-ai-model-acl-plugin.yaml
kubectl apply -f kong-ai-route-models.yaml


if [[ "${GEMINI_ENABLED}" == "true" ]]; then
  kubectl apply -f kong-ai-route-gemini.yaml
fi

if [[ "${ANTHROPIC_ENABLED}" == "true" ]]; then
  kubectl apply -f kong-ai-route-anthropic.yaml
fi

# --- Monitoring (optional) ---
echo ""
read -r -p "Deploy Monitoring (Prometheus + Grafana) for AI metrics? (y/N): " DEPLOY_MONITORING

if [[ "${DEPLOY_MONITORING}" =~ ^[Yy]$ ]]; then
  MONITORING_ENABLED=true

  echo "Applying Kong Prometheus plugin (global)..."
  kubectl apply -f kong-monitoring-plugin.yaml

  echo "Creating Kong metrics service..."
  kubectl apply -f kong-metrics-service.yaml

  kubectl create namespace monitoring || true

  echo "Deploying Prometheus..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update

  helm upgrade --install prometheus prometheus-community/prometheus \
    --namespace monitoring \
    --values prometheus-values.yaml

  echo "Waiting for Prometheus to be ready..."
  kubectl wait deployment prometheus-server -n monitoring --for=condition=Available=true --timeout=120s

  echo "Creating Grafana dashboard ConfigMap..."
  kubectl create configmap grafana-dashboard-ai \
    --namespace monitoring \
    --from-file=kong-ai-gateway.json=grafana-dashboard-ai.json \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "Deploying Grafana..."
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo update

  helm upgrade --install grafana grafana/grafana \
    --namespace monitoring \
    --values grafana-values.yaml

  echo "Waiting for Grafana to be ready..."
  kubectl wait deployment grafana -n monitoring --for=condition=Available=true --timeout=120s

  echo "Deploying AI Metrics Exporter..."
  kubectl apply -f ai-metrics-exporter.yaml

  echo "Waiting for AI Metrics Exporter to be ready..."
  kubectl wait deployment ai-metrics-exporter -n monitoring --for=condition=Available=true --timeout=120s

  echo "Applying Kong http-log plugin for token metrics..."
  kubectl apply -f kong-http-log-plugin.yaml

  echo "Applying Grafana route..."
  kubectl apply -f grafana-route.yaml

  echo "Monitoring stack deployed."
fi

# --- Keycloak (Enterprise: OIDC for OpenWebUI) ---
OIDC_HELM_ARGS=""
if [[ -f ${LICENSE_FILE} ]]; then
  echo ""
  echo "Enterprise license detected — deploying Keycloak for OpenID Connect..."

  kubectl apply -f keycloak.yaml

  echo "Waiting for Keycloak to be ready..."
  kubectl wait deployment keycloak -n ai-platform --for=condition=Available=true --timeout=300s

  WEBUI_VALUES_FILE="open-webui-values-oidc.yaml"
  echo "OpenWebUI will use Keycloak OIDC login:"
  echo "  dev   / dev   (Developer — Ollama only)"
  echo "  lead  / lead  (Team Lead — Ollama + Gemini)"
  echo "  admin / admin (Admin — All providers)"
else
  WEBUI_VALUES_FILE="open-webui-values.yaml"
fi

# --- Kuma Service Mesh / mTLS (optional) ---
echo ""
read -r -p "Enable Kuma Service Mesh with mTLS for confidential computing? (y/N): " DEPLOY_KUMA

KUMA_ENABLED=false
if [[ "${DEPLOY_KUMA}" =~ ^[Yy]$ ]]; then
  KUMA_ENABLED=true

  KUMA_CP=$(kubectl get ns kuma-cp 2>/dev/null || echo "false")
  if [[ "${KUMA_CP}" == "false" ]]; then
    echo "Kuma control plane not found. Installing..."
    cd ../kuma-mesh/
    bash setup.sh
    cd ../kong-ai-gateway/
  else
    echo "Kuma control plane already installed."
  fi

  echo "Enabling sidecar injection..."
  kubectl label ns kong kuma.io/sidecar-injection=enabled --overwrite
  kubectl label ns ai-platform kuma.io/sidecar-injection=enabled --overwrite

  echo "Applying mTLS mesh policies..."
  kubectl apply -f kuma-mesh-policies.yaml

  echo "Applying HTTP/1.1 proxy patches (Kuma defaults to HTTP/2, upstream services need HTTP/1.1)..."
  kubectl apply -f kuma-gateway-http1-patch.yaml

  echo "Restarting pods to inject Kuma sidecars..."
  kubectl rollout restart deployment/ollama -n ai-platform
  kubectl rollout restart deployment/kong-gateway -n kong

  if [[ -f ${LICENSE_FILE} ]]; then
    kubectl rollout restart deployment/keycloak -n ai-platform
  fi

  echo "Waiting for pods to be ready with Kuma sidecars..."
  kubectl wait deployment ollama -n ai-platform --for=condition=Available=true --timeout=300s
  kubectl wait deployment kong-gateway -n kong --for=condition=Available=true --timeout=120s

  # Force KIC to re-read service-upstream annotations.
  # KIC caches endpoint targets (Pod IPs) from before Kuma was enabled.
  # Re-toggling the annotation forces KIC to switch to Service DNS targets (ClusterIPs),
  # which is required for Kuma's outbound listeners to match and apply mTLS.
  echo "Re-syncing service-upstream annotations for KIC..."
  for SVC in ollama keycloak; do
    kubectl annotate svc "$SVC" -n ai-platform konghq.com/service-upstream- 2>/dev/null || true
    kubectl annotate svc "$SVC" -n ai-platform konghq.com/service-upstream="true" 2>/dev/null || true
  done

  echo "Kuma mTLS enabled. All AI platform traffic is now encrypted."
fi

# --- OpenWebUI ---
echo ""
echo "Deploying OpenWebUI..."

helm repo add open-webui https://helm.openwebui.com/
helm repo update

helm upgrade --install open-webui open-webui/open-webui \
  --namespace ai-platform \
  --values "${WEBUI_VALUES_FILE}"

echo "Waiting for OpenWebUI to be ready..."
kubectl rollout status statefulset/open-webui -n ai-platform --timeout=300s

kubectl apply -f open-webui-route.yaml

# Create initial admin user so OIDC users get DEFAULT_USER_ROLE (user).
# OpenWebUI makes the first signup user admin — by seeding a platform admin account
# via localhost (inside the pod), all subsequent OIDC logins receive the 'user' role.
WEBUI_ADMIN_EMAIL="admin@ai-platform.local"
WEBUI_ADMIN_PASSWORD="admin"
echo "Seeding platform admin account..."
kubectl exec -n ai-platform open-webui-0 -c open-webui -- python3 -c "
import urllib.request, json, time
for i in range(15):
    try:
        req = urllib.request.Request(
            'http://localhost:8080/api/v1/auths/signup',
            data=json.dumps({'name':'Platform Admin','email':'${WEBUI_ADMIN_EMAIL}','password':'${WEBUI_ADMIN_PASSWORD}'}).encode(),
            headers={'Content-Type':'application/json'}
        )
        resp = urllib.request.urlopen(req)
        data = json.loads(resp.read())
        if data.get('role') == 'admin':
            print('OK: Platform admin seeded. OIDC users will get user role.')
        else:
            print('WARNING: Seeded user got role=' + data.get('role','?') + ' (expected admin)')
        break
    except Exception as e:
        if i < 14:
            time.sleep(2)
        else:
            print('WARNING: Could not seed platform admin. First OIDC user will become admin.')
"

if [[ "${KUMA_ENABLED}" == "true" ]]; then
  echo "Annotating OpenWebUI service for Kuma mTLS (ClusterIP routing)..."
  kubectl annotate svc open-webui -n ai-platform konghq.com/service-upstream="true" --overwrite
fi

# --- Done ---
# --- Enterprise: Patch routes (must run AFTER monitoring/kuma to avoid being overwritten) ---
if [[ -f ${LICENSE_FILE} ]]; then
  echo ""
  echo "Patching AI routes for OIDC consumer mapping..."
  OIDC_PLUGINS="ai-proxy-ollama,ai-key-auth-or-oidc,ai-oidc,ai-http-log"
  kubectl annotate httproute ai-proxy-ollama -n kong konghq.com/plugins="${OIDC_PLUGINS}" --overwrite
  kubectl annotate httproute ai-proxy-ollama-internal -n kong konghq.com/plugins="${OIDC_PLUGINS}" --overwrite

  if [[ "${GEMINI_ENABLED}" == "true" ]]; then
    kubectl annotate httproute ai-proxy-gemini -n kong konghq.com/plugins="ai-proxy-gemini,ai-key-auth-or-oidc,ai-oidc,acl-gemini,ai-http-log" --overwrite
  fi
  if [[ "${ANTHROPIC_ENABLED}" == "true" ]]; then
    kubectl annotate httproute ai-proxy-anthropic -n kong konghq.com/plugins="ai-proxy-anthropic,ai-key-auth-or-oidc,ai-oidc,acl-anthropic,ai-http-log" --overwrite
  fi
  kubectl annotate httproute ai-proxy-failover -n kong konghq.com/plugins="ai-proxy-advanced-failover,ai-key-auth-or-oidc,ai-oidc,ai-http-log" --overwrite
  kubectl annotate httproute ai-proxy-ollama-internal -n kong konghq.com/plugins="ai-proxy-advanced-multimodel,ai-key-auth-or-oidc,ai-oidc,ai-http-log" --overwrite
  echo "Routes patched: API key OR OIDC token accepted."
  echo "Internal route upgraded to ai-proxy-advanced (multi-model)."
fi

echo ""
echo "============================================="
echo "  Kong AI Gateway + OpenWebUI deployed!"
echo "============================================="
echo ""
echo "--- Local Models ---"
echo "  [x] llama3.2:1b — general chat"
if [[ -f ${LICENSE_FILE} ]]; then
  echo "  [x] qwen2.5-coder:1.5b — code generation (Enterprise)"
  echo "  [x] gemma3:1b — alternative chat (Enterprise)"
fi
echo ""
echo "--- Providers ---"
echo "  [x] Ollama — local, free"
if [[ "${GEMINI_ENABLED}" == "true" ]]; then
  echo "  [x] Google Gemini (gemini-2.5-flash) — free tier"
fi
if [[ "${ANTHROPIC_ENABLED}" == "true" ]]; then
  echo "  [x] Anthropic Claude (claude-haiku-3-5-20241022) — paid"
fi
echo ""
echo "--- Consumer Groups ---"
echo "  dev-user   (key: dev-key-12345)   → Ollama only"
echo "  team-lead  (key: lead-key-12345)  → Ollama + Gemini"
echo "  admin-user (key: admin-key-12345) → All providers"
echo ""
echo "--- Test AI Proxy via curl (Ollama, as dev-user) ---"
echo "  curl -k -H 'apikey: dev-key-12345' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}],\"model\":\"llama3.2:1b\"}' \\"
echo "    https://ai.example.com:8081/ollama/v1/chat/completions"
echo ""
if [[ "${GEMINI_ENABLED}" == "true" ]]; then
  echo "--- Test AI Proxy via curl (Gemini, as team-lead) ---"
  echo "  curl -k -H 'apikey: lead-key-12345' \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}],\"model\":\"gemini-2.5-flash\"}' \\"
  echo "    https://ai.example.com:8081/gemini/v1/chat/completions"
  echo ""
  echo "--- Test ACL (dev-user blocked from Gemini) ---"
  echo "  curl -k -H 'apikey: dev-key-12345' \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}],\"model\":\"gemini-2.5-flash\"}' \\"
  echo "    https://ai.example.com:8081/gemini/v1/chat/completions"
  echo "  # Returns 403 Forbidden"
  echo ""
fi
if [[ "${MONITORING_ENABLED}" == "true" ]]; then
  echo "--- Monitoring ---"
  echo "  Grafana:    https://grafana.example.com:8081 (admin / admin)"
  echo "  Dashboard:  Kong AI Gateway (pre-installed)"
  echo ""
fi
echo "--- OpenWebUI ---"
echo "  Open in browser: https://chat.example.com:8081"
echo "  Admin login:     ${WEBUI_ADMIN_EMAIL} / ${WEBUI_ADMIN_PASSWORD}"
if [[ -f ${LICENSE_FILE} ]]; then
  echo "  OIDC login:      click 'Keycloak' (dev/dev, lead/lead, or admin/admin)"
  echo ""
  echo "--- Keycloak Admin Console ---"
  echo "  https://keycloak.example.com:8081"
  echo "  Admin login: admin / admin"
  echo ""
  echo "--- Kong Manager ---"
  echo "  https://kong-manager.example.com:8081"
  echo ""
  echo "--- Kong Admin API ---"
  echo "  https://kong-admin.example.com:8081"
  echo ""
  echo "--- Test OIDC Token Authentication ---"
  echo "  # Get token for 'dev' user:"
  echo "  TOKEN=\$(curl -sk -X POST https://keycloak.example.com:8081/realms/ai-platform/protocol/openid-connect/token \\"
  echo "    -d 'client_id=kong-ai-gateway&client_secret=kong-ai-gateway-secret&username=dev&password=dev&grant_type=password' | jq -r .access_token)"
  echo ""
  echo "  # Use token with Kong AI Gateway:"
  echo "  curl -k -H \"Authorization: Bearer \$TOKEN\" \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}],\"model\":\"llama3.2:1b\"}' \\"
  echo "    https://ai.example.com:8081/ollama/v1/chat/completions"
  echo ""
  echo "--- AI Gateway Failover (Enterprise) ---"
  echo "  Unified endpoint: https://ai.example.com:8081/ai/v1/chat/completions"
  echo "  Failover chain: Ollama$([ "${GEMINI_ENABLED}" == "true" ] && echo " → Gemini")$([ "${ANTHROPIC_ENABLED}" == "true" ] && echo " → Anthropic")"
  echo ""
  echo "  curl -k -H 'apikey: admin-key-12345' \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}' \\"
  echo "    https://ai.example.com:8081/ai/v1/chat/completions"
  echo "  # No model needed — Kong selects automatically with failover"
  echo ""
  echo "--- Enterprise Features Enabled ---"
  echo "  - AI Gateway Failover (ai-proxy-advanced): automatic provider failover"
  echo "  - OIDC consumer mapping (Keycloak user → Kong consumer)"
  echo "  - API key OR OIDC token authentication"
  echo "  - AI Rate Limiting (token-based): 10,000 tokens/minute"
  echo "  - AI Prompt Guard: blocks prompt injection attempts"
else
  echo "  (No authentication — open access for demo)"
fi
if [[ "${KUMA_ENABLED}" == "true" ]]; then
  echo ""
  echo "--- Kuma Service Mesh ---"
  echo "  mTLS: enabled (all inter-service traffic encrypted)"
  echo "  Policies: default-deny with explicit allow rules"
  echo "  Kuma GUI: https://kuma-gui.example.com:8081/gui"
  echo ""
  echo "  Verify mTLS:"
  echo "    kubectl get dataplaneinsights -A"
  echo "    kubectl get meshtrafficpermissions -n kuma-cp"
fi
echo ""
