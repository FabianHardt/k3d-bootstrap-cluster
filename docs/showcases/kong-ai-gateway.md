# Kong AI Gateway + OpenWebUI

This showcase demonstrates how to use **Kong AI Gateway** as a centralized proxy for LLM access, combined with **OpenWebUI** as a chat frontend. Kong handles authentication, authorization, and (with Enterprise license) rate limiting and prompt guardrails — so individual users never need direct access to LLM provider API keys.

## Architecture

```
                                                 ┌─────────────────┐
                                            ┌───▶│  Ollama (local) │  Default, free
                                            │    │  - llama3.2:1b  │  Chat model
┌────────────┐    ┌──────────────────────┐  │    │  - nomic-embed  │  Embeddings (RAG)
│  Browser   │──▶ │   Kong AI Gateway    │──┤    └─────────────────┘
│ (OpenWebUI)│    │                      │  │    ┌─────────────────┐
└────────────┘    │  - ai-proxy plugin   │  ├───▶│  Google Gemini  │  Optional, free tier
                  │  - key-auth plugin   │  │    └─────────────────┘
                  │  - opentelemetry     │  │    ┌─────────────────┐
                  │  - rate-limit (Ent.) │  └───▶│  Anthropic API  │  Optional, paid
                  │  - prompt-guard (E.) │       └─────────────────┘
                  └──────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
   RAG Pipeline    Monitoring        Token Metrics
   Docs → Embed    Prometheus →      OTel access logs →
   → ChromaDB →    Grafana           OTel Collector
   Context         Dashboard         (sum connector)
```

Multiple local models and cloud providers are supported, each with its own Kong route:

| Model / Provider | Route | Type | Cost |
|-----------------|-------|------|------|
| llama3.2:1b (Ollama) | `/ollama/v1/chat/completions` | General chat | Free (local) |
| qwen2.5-coder:1.5b (Ollama) | `/coder/v1/chat/completions` | Code generation | Free (local) |
| gemma3:1b (Ollama) | `/gemma/v1/chat/completions` | Alternative chat | Free (local) |
| Google Gemini (gemini-2.5-flash) | `/gemini/v1/chat/completions` | Cloud — fast | Free tier / Optional |
| Anthropic Claude (claude-haiku-4-5) | `/anthropic/v1/chat/completions` | Cloud — quality | Paid / Optional |

## Preconditions

- k3d cluster with Kong Ingress Controller deployed (`examples/kong-gateway`)
- `helm` CLI installed
- Optional: Google Gemini API Key (free from [aistudio.google.com](https://aistudio.google.com))
- Optional: Anthropic API Key (paid, from [console.anthropic.com](https://console.anthropic.com))

## Getting API Keys

### Google Gemini (free)

1. Go to [aistudio.google.com](https://aistudio.google.com)
2. Sign in with your Google account
3. Click **"Get API key"** in the left sidebar
4. Click **"Create API key"** and select a Google Cloud project (or create one)
5. Copy the generated key — it starts with `AIza...`

The free tier includes 15 requests/minute and 1 million tokens/day — more than enough for this demo.

### Anthropic (paid, optional)

1. Go to [console.anthropic.com](https://console.anthropic.com)
2. Create an account and add a payment method
3. Navigate to **Settings → API keys**
4. Click **"Create Key"** and copy it — it starts with `sk-ant-...`

> **Note:** Anthropic does not offer a free tier. You can skip this and still use the demo with Ollama and Gemini.

### Adding keys after installation

If you skipped the API key prompts during `setup.sh`, you can add them later:

```bash
# Add Gemini key
kubectl create secret generic gemini-api-key \
  --namespace kong --from-literal=api-key="YOUR_GEMINI_KEY"
kubectl apply -f kong-ai-plugin-gemini.yaml
kubectl apply -f kong-ai-route-gemini.yaml

# Add Anthropic key
kubectl create secret generic anthropic-api-key \
  --namespace kong --from-literal=api-key="YOUR_ANTHROPIC_KEY"
kubectl apply -f kong-ai-plugin-anthropic.yaml
kubectl apply -f kong-ai-route-anthropic.yaml
```

> **Note:** Without an Enterprise license, apply `kong-ai-route-gemini-oss.yaml` instead of `kong-ai-route-gemini.yaml` (the Enterprise variant references OIDC and semantic-cache plugins that only exist with a license).

## DNS preparation

Add the following entries to `/etc/hosts`:

```
127.0.0.1 ai.example.com chat.example.com keycloak.example.com grafana.example.com kong-manager.example.com kong-admin.example.com
```

## Installation

```bash
cd examples/kong-ai-gateway
bash setup.sh
```

### Non-interactive complete setup

To deploy the whole showcase with every optional component (OpenBao,
monitoring stack, Kuma mesh) and no prompts, use the wrapper:

```bash
cd examples/kong-ai-gateway
bash complete-setup.sh
```

It runs `setup.sh` with `NON_INTERACTIVE=1` and `DEPLOY_OPENBAO`,
`DEPLOY_MONITORING`, `DEPLOY_KUMA` all set to `y`. Enterprise features
activate automatically when `license.json` is present. External providers
stay opt-in — export the keys first to wire them in, or turn a component off:

```bash
GEMINI_API_KEY=... ANTHROPIC_API_KEY=... bash complete-setup.sh
DEPLOY_KUMA=n bash complete-setup.sh
```

The script will:
1. Verify that Kong Ingress Controller is running
2. Optionally deploy **OpenBao** and **cert-manager** for TLS certificates
3. Deploy **Ollama** with `llama3.2:1b` (chat) and `nomic-embed-text` (RAG embeddings), optionally `qwen2.5-coder:1.5b` and `gemma3:1b`
4. Optionally prompt for **Gemini** and **Anthropic** API keys
5. Apply Kong AI plugins per provider (ai-proxy, key-auth, per-user model filtering)
6. Deploy three consumers with different access levels (`dev-user`, `team-lead`, `admin-user`)
7. Optionally deploy **Prometheus + Grafana** monitoring with pre-built AI dashboard, token metrics, and cost estimation
8. Optionally enable **Kuma Service Mesh** with mTLS for confidential computing
9. Deploy **OpenWebUI** via Helm (all traffic including RAG embeddings routed through Kong)
10. Seed a platform admin account so OIDC users get the `user` role (no settings access)
11. Set up HTTPRoutes for all endpoints

### Kong Enterprise (optional)

Place a `license.json` file in the `examples/kong-ai-gateway/` directory before running `setup.sh`. This enables:

- **Kong Manager UI** at `https://kong-manager.example.com:8081`
- **Keycloak** as OpenID Connect identity provider (3 users: `dev`, `lead`, `admin`)
- **OIDC Consumer Mapping** — JWT `preferred_username` claim maps to Kong consumers
- **AI Gateway Failover** — `ai-proxy-advanced` with priority-based failover (Ollama → Gemini → Anthropic)
- **Dual Authentication** — API key OR OIDC token accepted on all AI routes
- **AI Rate Limiting Advanced** — token-based rate limiting (10,000 tokens/minute per consumer)
- **AI Prompt Guard** — blocks prompt injection attempts (e.g., "ignore previous instructions")

> **Note on RBAC:** Kong's Role-Based Access Control (RBAC) for the Admin API and Manager UI requires a database-backed deployment. This showcase uses Kong in DB-less mode (via Kong Ingress Controller), which does not support RBAC. In production, consider running Kong in hybrid mode with a PostgreSQL database to enable RBAC, or restrict access to the Admin API via network policies.

## Components

| Component | Source | Namespace |
|-----------|--------|-----------|
| Ollama (llama3.2:1b + nomic-embed-text) | Deployment manifest | `ai-platform` |
| ChromaDB (RAG vector store) | Built into OpenWebUI | `ai-platform` |
| OpenWebUI | [Helm chart](https://github.com/open-webui/helm-charts) | `ai-platform` |
| Kong AI Proxy Plugins | KongPlugin CRD | `kong` |
| Key Authentication | KongPlugin CRD | `kong` |
| Demo Consumer | KongConsumer CRD | `kong` |
| OTel Collector (optional) | Deployment manifest | `monitoring` |
| Prometheus (optional) | Helm chart | `monitoring` |
| Grafana (optional) | Helm chart | `monitoring` |
| Kong Prometheus Plugin (optional) | KongClusterPlugin CRD | cluster-wide |
| Keycloak (Enterprise) | Deployment manifest | `ai-platform` |
| AI Rate Limiting (Enterprise) | KongPlugin CRD | `kong` |
| AI Prompt Guard (Enterprise) | KongPlugin CRD | `kong` |
| Kuma Service Mesh (optional) | Helm chart | `kuma-cp` |
| mTLS Traffic Policies | MeshTrafficPermission CRD | `kuma-cp` |

## Endpoints

| Service | URL | Auth |
|---------|-----|------|
| OpenWebUI | `https://chat.example.com:8081` | OSS: open / Enterprise: Keycloak OIDC / Admin: `admin@ai-platform.local` / `admin` |
| AI Proxy (Ollama) | `https://ai.example.com:8081/ollama/v1/chat/completions` | key-auth (`apikey` header) |
| AI Proxy (Gemini) | `https://ai.example.com:8081/gemini/v1/chat/completions` | key-auth (`apikey` header) |
| AI Proxy (Anthropic) | `https://ai.example.com:8081/anthropic/v1/chat/completions` | key-auth (`apikey` header) |
| AI Failover (Enterprise) | `https://ai.example.com:8081/ai/v1/chat/completions` | key-auth / OIDC |
| Grafana (optional) | `https://grafana.example.com:8081` | admin / admin |
| Kong Manager (Enterprise) | `https://kong-manager.example.com:8081` | — |
| Kong Admin API (Enterprise) | `https://kong-admin.example.com:8081` | — |
| Keycloak Admin (Enterprise) | `https://keycloak.example.com:8081` | admin / admin (Keycloak admin) |

## Testing

### Direct API call via curl (Ollama — free, always available)

```bash
curl -k -H "apikey: dev-key-12345" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello! What is Kubernetes?"}],"model":"llama3.2:1b"}' \
  https://ai.example.com:8081/ollama/v1/chat/completions
```

### Direct API call via curl (Gemini — if configured)

```bash
# Requires team-lead or admin-user API key (dev-user returns 403)
curl -k -H "apikey: lead-key-12345" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello! What is Kubernetes?"}],"model":"gemini-2.5-flash"}' \
  https://ai.example.com:8081/gemini/v1/chat/completions
```

### Model list per consumer (Enterprise)

Per-user model filtering requires the Enterprise setup (Keycloak + OIDC consumer mapping). In OSS mode, `/ollama/v1/models` returns a static list containing `llama3.2:1b` for every authenticated consumer.

```bash
# dev-user sees Ollama models only
curl -k -H "apikey: dev-key-12345" https://ai.example.com:8081/ollama/v1/models

# lead-user sees Ollama + Gemini
curl -k -H "apikey: lead-key-12345" https://ai.example.com:8081/ollama/v1/models

# admin-user sees all models
curl -k -H "apikey: admin-key-12345" https://ai.example.com:8081/ollama/v1/models
```

### OpenWebUI

1. Open `https://chat.example.com:8081` in your browser
2. **OSS mode:** No login required — open access
3. **Enterprise mode:** Click "Login with Keycloak" (`dev`/`dev`, `lead`/`lead`, or `admin`/`admin`)
4. The model dropdown shows only the models your role is authorized for
5. Select a model and start chatting

### Verify API authentication

Without a valid API key, the request is rejected:

```bash
curl -k -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"model":"llama3.2:1b"}' \
  https://ai.example.com:8081/ollama/v1/chat/completions
# Returns 401 Unauthorized
```

### Verify model access control

```bash
# dev-user trying to use Gemini → 403 Forbidden
curl -k -H "apikey: dev-key-12345" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"model":"gemini-2.5-flash"}' \
  https://ai.example.com:8081/gemini/v1/chat/completions
```

## How it works

### AI Proxy Plugin

**External routes** — each provider gets its own `ai-proxy` KongPlugin instance and HTTPRoute:

- **Ollama**: Uses `provider: openai` with `upstream_url` pointing to the local Ollama service.
- **Gemini**: Injects the Gemini API key as a query parameter and transforms requests from OpenAI format to Gemini format.
- **Anthropic**: Injects the Anthropic API key as an `x-api-key` header and transforms requests from OpenAI to Anthropic format.

**Internal route (OpenWebUI)** — a single `ai-proxy-advanced` plugin with `model_alias` handles all providers through one endpoint:

```
OpenWebUI → Kong /ollama/v1/chat/completions
              │
              ├─ model: "llama3.2:1b"    → ai-proxy-advanced → Ollama
              ├─ model: "gemma3:1b"      → ai-proxy-advanced → Ollama
              ├─ model: "gemini-2.5-flash" → ai-proxy-advanced → Gemini API
              └─ model: "claude-haiku-*"  → ai-proxy-advanced → Anthropic API
```

Each target in the `ai-proxy-advanced` plugin has a `model_alias` matching the model name that clients send. Kong routes the request to the correct provider based on the `model` field in the request body — no separate routes needed.

All providers expose an OpenAI-compatible interface via Kong, so any OpenAI client (like OpenWebUI) can use them transparently.

**OSS mode (no `license.json`)** — `ai-proxy-advanced`, `openid-connect`, `ai-semantic-cache` and `ai-rate-limiting-advanced` are Enterprise plugins. Without a license, `setup.sh` applies `kong-ai-routes-oss.yaml` instead:

| Aspect | Enterprise | OSS |
|--------|-----------|-----|
| Internal chat route (OpenWebUI) | `ai-proxy-advanced` multi-model (`model_alias`) | plain `ai-proxy` pinned to `llama3.2:1b` |
| Authentication | API key **or** OIDC token (`ai-key-auth-or-oidc` + `ai-oidc`) | API key only (`ai-key-auth`) |
| Model list (`/v1/models`) | per-user filtered (`ai-models-filtered`) | static `llama3.2:1b` (`ai-models-response`) |
| Gemini / Anthropic | via OpenWebUI and external routes | external routes only (`curl`), ACL-protected |
| Failover `/ai`, semantic cache, prompt guard, token rate limiting | ✔ | — |

### Model Recommendations

This demo uses small models (1b–1.5b parameters) optimized for k3d on laptops. For production or GPU-equipped environments, consider larger models:

| Use Case | Demo (CPU, k3d) | Production (GPU) | Parameters |
|----------|----------------|-------------------|------------|
| General Chat | llama3.2:1b | llama3.3:70b, qwen2.5:32b | 1b → 32–70b |
| Code Generation | qwen2.5-coder:1.5b | qwen2.5-coder:32b, codellama:34b | 1.5b → 32–34b |
| Alternative Chat | gemma3:1b | gemma3:27b, mistral:7b | 1b → 7–27b |
| Embeddings (RAG) | nomic-embed-text | nomic-embed-text, mxbai-embed-large | 137M → 335M |

To add a model, pull it in Ollama and create a new ai-proxy plugin + route in Kong:

```bash
# Pull a new model
kubectl exec -n ai-platform deployment/ollama -- ollama pull mistral:7b

# Create plugin + route (follow the pattern of existing models)
# Then update the models response list
```

Kong acts as a **model router** — each model gets its own route with independent authentication, rate limiting, and monitoring. This enables per-model access control (e.g., restrict expensive GPU models to specific consumer groups).

### Consumer Groups & Access Control

Three consumer groups with different provider access levels are pre-configured:

| Consumer | API Key | Keycloak User | Ollama | Gemini | Anthropic |
|----------|---------|---------------|--------|--------|-----------|
| `dev-user` | `dev-key-12345` | `dev` / `dev` | Yes | No (403) | No (403) |
| `team-lead` | `lead-key-12345` | `lead` / `lead` | Yes | Yes | No (403) |
| `admin-user` | `admin-key-12345` | `admin` / `admin` | Yes | Yes | Yes |

Access control is enforced at two levels in Kong:

**Route-level ACL** (`acl` plugin):
- **Ollama route**: No ACL — all authenticated consumers can access
- **Gemini route**: ACL group `gemini-access` required (team-lead, admin-user)
- **Anthropic route**: ACL group `anthropic-access` required (admin-user only)

**Per-user model filtering** (`post-function` + `pre-function` plugins):
- **Model list** (`ai-models-filtered`): A `post-function` plugin on the `/v1/models` routes dynamically returns only the models the user is authorized for. It identifies the user via the `X-OpenWebUI-User-Email` header (forwarded by OpenWebUI) or the Kong consumer's `custom_id` (for direct API access).
- **Chat enforcement** (`ai-model-acl`): A `pre-function` plugin on chat routes validates the requested model against the user's role and returns 403 if unauthorized. Embedding requests (`/v1/embeddings`) are excluded from this check since RAG uses `nomic-embed-text` internally.

This ensures users only **see** and can only **use** models matching their role — both in the OpenWebUI dropdown and via direct API calls.

The `key-auth` plugin accepts the key via the `apikey` header (for curl) or the `Authorization: Bearer` header (for OpenAI-compatible clients like OpenWebUI).

Consumer API keys are separate from provider API keys (Gemini, Anthropic). Provider keys are centrally managed in Kong — consumers never see them.

### OpenWebUI Integration

OpenWebUI connects to Kong's AI proxy as an OpenAI-compatible backend. All traffic — including model discovery and RAG embeddings — is routed through Kong:

- **Chat**: All chat requests go through Kong (`/ollama/v1/chat/completions`), enabling centralized authentication, logging, and metrics. With Enterprise, the internal route uses `ai-proxy-advanced` (multi-model) so a single connection handles all providers.
- **Model discovery**: Kong returns a per-user filtered model list via a `post-function` plugin on `/ollama/v1/models`. The plugin reads the `X-OpenWebUI-User-Email` header (forwarded when `ENABLE_FORWARD_USER_INFO_HEADERS=true`) and returns only the models the user is authorized for. The embedding model (`nomic-embed-text`) is excluded from the list.
- **RAG embeddings**: OpenWebUI uses the OpenAI embedding engine (`RAG_EMBEDDING_ENGINE=openai`) routed through Kong to Ollama. This prevents OpenWebUI from discovering Ollama models directly (which would bypass Kong's model filtering).
- **Access control bypass**: OpenWebUI's built-in model access control is disabled (`BYPASS_MODEL_ACCESS_CONTROL=true`) since Kong handles authorization. Users have the `user` role (`DEFAULT_USER_ROLE=user`) so they cannot modify OpenWebUI settings.

### RAG (Retrieval-Augmented Generation)

OpenWebUI includes built-in RAG support with an embedded ChromaDB vector store. This showcase configures it to use Ollama's `nomic-embed-text` model for generating embeddings — completely local, no data leaves the cluster.

**How it works:**

1. Upload documents (PDF, TXT, MD, etc.) via the OpenWebUI sidebar (`+` button next to chat)
2. OpenWebUI extracts text and splits it into chunks
3. Each chunk is embedded using `nomic-embed-text` via the local Ollama instance
4. Embeddings are stored in OpenWebUI's built-in ChromaDB
5. When chatting, relevant chunks are retrieved and injected into the prompt as context

**Usage:**

1. Open `https://chat.example.com:8081`
2. Click the `+` icon in the sidebar to create a new knowledge base
3. Upload one or more documents
4. Start a new chat, click `+` in the message bar, and select the knowledge base
5. Ask questions about your documents — the model will answer based on the retrieved context

All processing happens locally: text extraction, embedding generation (Ollama), vector storage (ChromaDB), and LLM inference. No document content is sent to external providers unless you explicitly select Gemini or Anthropic as the chat model.

### Monitoring (Prometheus + Grafana)

When monitoring is enabled, the following components are deployed:

**Kong Prometheus Plugin** — activated globally, exposes request metrics:

| Metric | Description |
|--------|-------------|
| `kong_http_requests_total` | Total requests by service (AI route), status code, consumer |
| `kong_bandwidth_bytes` | Request/response bandwidth by service and direction |
| `kong_upstream_latency_ms` | LLM provider response latency histogram |
| `kong_kong_latency_ms` | Kong processing latency histogram |

**Per-user LLM token metrics — no custom exporter.** Kong's `opentelemetry`
plugin ships access logs to an **OTel Collector**; each record carries the AI
plugin's `log_statistics` token counts plus `provider`/`model`/`consumer`
attributes (set via `custom_attributes_by_lua`). The Collector's `sum` connector
turns them into these Prometheus counters — config, not code:

| Metric | Description |
|--------|-------------|
| `ai_llm_prompt_tokens_total` | Prompt tokens by provider, model, consumer |
| `ai_llm_completion_tokens_total` | Completion tokens by provider, model, consumer |
| `ai_llm_tokens_total` | Total tokens by provider, model, consumer |
| `ai_llm_requests_total` | Total LLM requests by provider, model, consumer |
| `ai_llm_estimated_cost_usd` | Estimated cost in USD by provider, model, consumer |

The user identity comes from OpenWebUI's `X-OpenWebUI-User-Email` header
(forwarded by `ENABLE_FORWARD_USER_INFO_HEADERS`), falling back to the Kong
consumer's `custom_id` — same consumer labels (`dev`, `lead`, `admin`) as before.
Cost is computed by Kong from the per-model `input_cost`/`output_cost` rates.

Because token counts come from Kong (not from parsing the response body),
**streaming works** — no `ai-force-nostream` hack — and all providers are handled
uniformly (the AI plugin normalizes OpenAI/Ollama, Gemini and Anthropic usage).

The pre-installed **Kong AI Gateway** Grafana dashboard includes:

- **Overview**: Total AI requests, success/error counts, bandwidth
- **Request Rate by Provider**: Time series of request rates per LLM route
- **Bandwidth by Provider**: Ingress/egress data volume per provider
- **Latency Percentiles**: p50/p95/p99 upstream latency per provider
- **Consumer & Status Analytics**: Pie charts for request distribution
- **Token Usage**: Prompt, completion, and total token counts by provider and consumer
- **Enterprise License**: License TTL and error count (when Enterprise license is active)

Open `https://grafana.example.com:8081` (admin / admin) and navigate to the **Kong > Kong AI Gateway** dashboard.

### Enterprise: Keycloak OIDC & Consumer Mapping

With an Enterprise license, Keycloak is deployed as an identity provider with two authentication paths:

**OpenWebUI Login (browser-based):**
OpenWebUI uses its built-in OIDC support for user authentication:

1. User opens OpenWebUI → Login page with "Keycloak" button
2. Browser redirects to Keycloak login page
3. User authenticates (`dev`/`dev`, `lead`/`lead`, or `admin`/`admin`)
4. Keycloak redirects back to OpenWebUI with an authorization code
5. OpenWebUI exchanges the code for tokens server-side

**API Access with OIDC Token (programmatic):**
Kong's `openid-connect` plugin validates JWT tokens and maps the `preferred_username` claim to a Kong consumer via `custom_id`. This enables **API key OR OIDC token** authentication on all AI routes:

```bash
# Get a token from Keycloak (as 'dev' user)
TOKEN=$(curl -sk -X POST \
  https://keycloak.example.com:8081/realms/ai-platform/protocol/openid-connect/token \
  -d "client_id=kong-ai-gateway&client_secret=kong-ai-gateway-secret&username=dev&password=dev&grant_type=password" \
  | jq -r .access_token)

# Use OIDC token with Kong (maps to dev-user consumer → Ollama only)
curl -k -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"model":"llama3.2:1b"}' \
  https://ai.example.com:8081/ollama/v1/chat/completions
```

The mapping works via Kong's anonymous consumer pattern:
1. `key-auth` plugin tries API key → if valid, consumer is set
2. If no API key, fallback to anonymous consumer
3. `openid-connect` plugin tries JWT token → if valid, consumer is mapped via `preferred_username` → `custom_id`
4. If neither succeeds, `request-termination` plugin returns 401

> **Technical note:** OpenWebUI connects to Keycloak's discovery endpoint via the cluster-internal URL (`http://keycloak.ai-platform.svc.cluster.local/realms/ai-platform/.well-known/openid-configuration`), while browser redirects use the external URL (`https://keycloak.example.com:8081`). The Keycloak Service uses port 80 (targetPort 8080) so the internal URL has no port suffix.

### Enterprise: AI Gateway Failover

With an Enterprise license, the `ai-proxy-advanced` plugin provides automatic multi-provider failover via a single unified endpoint:

```
https://ai.example.com:8081/ai/v1/chat/completions
```

**Failover chain (priority algorithm):**

```
┌─────────────────┐     fail     ┌─────────────────┐     fail     ┌─────────────────┐
│  Ollama (local)  │────────────▶│  Google Gemini   │────────────▶│  Anthropic API   │
│  weight: 100     │             │  weight: 50      │             │  weight: 10      │
│  $0 (sovereign)  │             │  $0 (free tier)  │             │  $$ (paid)       │
└─────────────────┘             └─────────────────┘             └─────────────────┘
```

**Configuration:**
- **Algorithm**: `priority` — routes to the highest-weight target first
- **Circuit breaker**: After 2 consecutive failures (`max_fails: 2`), a target is marked unavailable for 30 seconds
- **Failover criteria**: `error`, `timeout`, `http_429`, `http_500`, `http_502`, `http_503`
- **Retries**: Up to 3 attempts across the failover chain

**Test failover:**

```bash
# No model parameter needed — Kong selects automatically
curl -k -H "apikey: admin-key-12345" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello!"}]}' \
  https://ai.example.com:8081/ai/v1/chat/completions

# Simulate Ollama failure: scale down Ollama, repeat the request
# Kong automatically fails over to Gemini (or Anthropic)
kubectl scale deployment ollama -n ai-platform --replicas=0
# ... repeat curl, observe failover ...
kubectl scale deployment ollama -n ai-platform --replicas=1
```

This demonstrates the sovereign AI gateway pattern: local-first processing with automatic cloud fallback when the local model is unavailable.

> **Note:** The unified `/ai` endpoint exists alongside the individual model routes (`/ollama`, `/coder`, `/gemma`, `/gemini`, `/anthropic`). Direct routes give explicit model control; the failover route provides resilience.

### Confidential Computing: Kuma Service Mesh with mTLS

When Kuma is enabled, all inter-service communication within the AI platform is encrypted with mutual TLS (mTLS). Kuma's sidecar proxies handle certificate management and rotation automatically.

**What gets encrypted:**

```
┌─────────────────────────────────────────────────────────────────┐
│                         Kuma Mesh (mTLS)                        │
│                                                                 │
│  Kong Gateway has a Kuma sidecar for mesh membership           │
│  Kuma GUI available at kuma-gui.example.com:8081/gui           │
└─────────────────────────────────────────────────────────────────┘
```

**Current scope:**
- Kong Gateway runs with a Kuma sidecar (mesh member)
- Kuma control plane with CNI mode installed
- MeshTrafficPermission policies configured (allow-all within mesh)
- Kuma GUI exposed via Kong HTTPRoute

**Kong + Kuma integration requires three fixes:**

1. **`KONG_DNS_ORDER=A,CNAME`** (in Helm values) — Kong prefers A records (ClusterIPs) over SRV records (Pod IPs) when resolving service DNS.
2. **`konghq.com/service-upstream: "true"`** on meshed backend Services — forces KIC to pass the Service DNS name to Kong instead of resolving to Pod IPs. After enabling Kuma, the setup re-toggles these annotations to force KIC to re-read them (KIC caches endpoint targets from before Kuma was enabled).
3. **`MeshProxyPatch`** resources — override Kuma's default HTTP/2 protocol on outbound clusters to HTTP/1.1 (required for Ollama, Keycloak, and OpenWebUI backends).

> **Note:** Do NOT set `konghq.com/service-upstream` on Kong's own internal services (`kong-gateway-manager`, `kong-gateway-admin`). With multi-port services, KIC incorrectly selects the TLS port when this annotation is set. The manager/admin routes use HTTP backend ports (8002/8001) instead of HTTPS (8445/8444) to avoid self-signed certificate issues.

**Verify mesh status:**

```bash
# Check sidecar injection
kubectl get pods -n kong -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{", "}{end}{"\n"}{end}'

# Check mesh policies
kubectl get meshtrafficpermissions -n kuma-cp

# View Kuma GUI
# https://kuma-gui.example.com:8081/gui
```

**Data sovereignty by provider:**

| Provider | Prompt leaves cluster? | Transport |
|----------|----------------------|-----------|
| Ollama (local) | No — full sovereignty | Internal cluster network |
| Gemini (cloud) | Yes — sent to Google | TLS (external) |
| Anthropic (cloud) | Yes — sent to Anthropic | TLS (external) |

For maximum data sovereignty, use **Ollama only** and leave cloud providers unconfigured. The AI Gateway Failover (Enterprise) can be configured to only fall back to cloud providers when the local model is unavailable — ensuring that prompts only leave the cluster in degraded scenarios, not during normal operation.

### Enterprise: Prompt Guard

The `ai-prompt-guard` plugin inspects prompts before forwarding and blocks known injection patterns like "ignore previous instructions" or "reveal system prompt".
