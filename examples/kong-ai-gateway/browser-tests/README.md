# Browser Tests — Kong AI Gateway Showcase

End-to-end browser tests using [Playwright](https://playwright.dev/) that verify the full AI platform stack: OpenWebUI, Keycloak OIDC, Kong AI Gateway, MCP tool servers, and Ollama.

## Prerequisites

- Node.js 22+
- Running k3d cluster with the AI Gateway showcase deployed (`bash setup.sh`)
- Hostnames `chat.example.com`, `keycloak.example.com`, `ai.example.com` resolving to `127.0.0.1` (via `/etc/hosts` or nip.io)

## Setup

```bash
cd examples/kong-ai-gateway/browser-tests
npm install
npx playwright install chromium
```

## Run Tests

```bash
# All tests (headless)
npx playwright test

# With browser visible
npx playwright test --headed

# Single test
npx playwright test --grep "admin user can chat"

# With Playwright UI (interactive)
npx playwright test --ui
```

## Test Suite

| Test | What it verifies |
|------|-----------------|
| **Admin Chat** | Local admin can login and chat with LLM via Kong |
| **OIDC Chat** | Keycloak dev user can login via OIDC and chat |
| **Keycloak Login Page** | Keycloak realm is accessible |
| **OIDC All Users** | dev/lead/admin can all authenticate via Keycloak |
| **Kong AI API** | External AI chat route works with API key auth |
| **Kong ACL** | dev-user is blocked from Gemini (403 Forbidden) |
| **MCP Endpoint** | SearXNG MCP server responds via Kong with correct protocol |
| **Rate Limiting** | Kong rate-limit headers present on MCP endpoint |

## Architecture

The tests verify the following traffic paths:

```
Browser Chat:     Browser → Kong:443 → OpenWebUI → Kong:8000 → Ollama
OIDC Login:       Browser → Kong:443 → OpenWebUI → Keycloak
External API:     curl → Kong:443 → ai-proxy-advanced → Ollama
MCP Tool Call:    curl → Kong:443 → MCP Server → SearXNG → Web
```

## Debugging Failed Tests

Failed tests produce screenshots in `test-results/`:

```bash
# View screenshot
open test-results/ai-platform-*/test-failed-1.png

# View trace (recorded on retry)
npx playwright show-trace test-results/*/trace.zip
```

## Configuration

- `playwright.config.ts` — Base URL, timeouts, retry settings
- Tests use self-signed TLS certificates (`ignoreHTTPSErrors: true`)
- 120s test timeout accommodates slow LLM inference on local hardware
- 1 retry handles transient Kuma mesh connectivity during model inference
