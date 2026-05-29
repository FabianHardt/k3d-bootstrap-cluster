import { test, expect, Page } from '@playwright/test';

const KEYCLOAK_URL = 'https://keycloak.example.com:8081';
const CHAT_URL = 'https://chat.example.com:8081';

// Helper: login via Keycloak OIDC
async function loginViaKeycloak(page: Page, username: string, password: string) {
  await page.goto(CHAT_URL);
  // Click the Keycloak login button
  await page.getByRole('button', { name: /keycloak/i }).click();
  // Keycloak login form
  await page.waitForURL(/keycloak\.example\.com/);
  await page.fill('#username', username);
  await page.fill('#password', password);
  await page.click('#kc-login');
  // Wait for redirect back to OpenWebUI
  await page.waitForURL(/chat\.example\.com/);
  // Wait for the UI to load
  await page.waitForSelector('[id="chat-input"]', { timeout: 15000 }).catch(() => null);
  await page.waitForTimeout(2000);
}

// Helper: login as local admin
async function loginAsAdmin(page: Page) {
  await page.goto(`${CHAT_URL}/auth`);
  await page.fill('input[type="email"]', 'admin@ai-platform.local');
  await page.fill('input[type="password"]', 'admin');
  await page.getByRole('button', { name: /sign in/i }).click();
  await page.waitForURL(/chat\.example\.com/);
  await page.waitForTimeout(2000);
}

// Helper: send a chat message and wait for response
async function sendMessage(page: Page, message: string): Promise<string> {
  // Type into the chat input
  const textarea = page.locator('#chat-input');
  await textarea.click();
  await textarea.fill(message);

  // Click the send button (arrow icon)
  await page.locator('button[type="submit"], button[aria-label*="Send"], #send-message-button').first().click();

  // Wait for response to complete — action buttons (copy, thumbs up, etc.) appear when done
  const actionButtons = page.locator('button[aria-label="Copy"], button[aria-label="Good Response"]').first();
  await actionButtons.waitFor({ state: 'visible', timeout: 90000 });
  await page.waitForTimeout(500);

  // Get response text — the action buttons' parent contains the model response
  return await page.evaluate(() => {
    // The copy button is inside the response block; its closest message container has the text
    const copyBtn = document.querySelector('button[aria-label="Copy"]');
    if (copyBtn) {
      const container = copyBtn.closest('[id^="message-"]') || copyBtn.parentElement?.parentElement;
      if (container) {
        // Get the text content, excluding the model name header and action buttons
        const textParts: string[] = [];
        container.querySelectorAll('p, li, pre, code, h1, h2, h3').forEach(el => {
          const t = (el as HTMLElement).innerText?.trim();
          if (t) textParts.push(t);
        });
        if (textParts.length > 0) return textParts.join('\n');
      }
    }
    // Fallback: find the text between the model name and the action buttons
    const body = document.body.innerText;
    const match = body.match(/(?:llama|gemma|qwen|arena)[^\n]*\n([^\n]+)/i);
    return match?.[1]?.trim() || '';
  });
}

test.describe('OpenWebUI Chat', () => {
  test('admin user can chat with llama', async ({ page }) => {
    await loginAsAdmin(page);
    const response = await sendMessage(page, 'Say "hello world" and nothing else');
    expect(response.toLowerCase()).toContain('hello');
  });

  test('OIDC user (dev) can login via Keycloak and chat', async ({ page }) => {
    await loginViaKeycloak(page, 'dev', 'dev');
    const response = await sendMessage(page, 'Say "hello" and nothing else');
    expect(response.toLowerCase()).toContain('hello');
  });
});

test.describe('Keycloak OIDC', () => {
  test('Keycloak login page is accessible', async ({ page }) => {
    await page.goto(`${KEYCLOAK_URL}/realms/ai-platform/account`);
    await expect(page.locator('#username')).toBeVisible();
  });

  test('all three OIDC users can authenticate', async ({ page }) => {
    for (const user of ['dev', 'lead', 'admin']) {
      await page.goto(`${CHAT_URL}/auth`);
      await page.getByRole('button', { name: /keycloak/i }).click();
      await page.waitForURL(/keycloak\.example\.com/);
      await page.fill('#username', user);
      await page.fill('#password', user);
      await page.click('#kc-login');
      await page.waitForURL(/chat\.example\.com/);
      // Verify we're logged in
      await expect(page).toHaveURL(/chat\.example\.com/);
      // Logout for next user
      await page.goto(`${KEYCLOAK_URL}/realms/ai-platform/protocol/openid-connect/logout`);
      await page.context().clearCookies();
    }
  });
});

test.describe('Kong AI Gateway API', () => {
  // Known issue: Kong Gateway Envoy has 5s stream_idle_timeout that cannot be
  // overridden via Kuma policies. LLM inference can exceed 5s under load.
  test('AI chat via Kong external route', async ({ request }) => {
    const response = await request.post('https://ai.example.com:8081/ollama/v1/chat/completions', {
      headers: {
        'apikey': 'admin-key-12345',
        'Content-Type': 'application/json',
      },
      data: {
        model: 'llama3.2:1b',
        messages: [{ role: 'user', content: 'Say hello' }],
      },
      ignoreHTTPSErrors: true,
    });
    expect(response.status()).toBe(200);
    const body = await response.json();
    expect(body.choices[0].message.content.toLowerCase()).toContain('hello');
  });

  test('dev-user is blocked from Gemini (ACL)', async ({ request }) => {
    const response = await request.post('https://ai.example.com:8081/gemini/v1/chat/completions', {
      headers: {
        'apikey': 'dev-key-12345',
        'Content-Type': 'application/json',
      },
      data: {
        model: 'gemini-2.5-flash',
        messages: [{ role: 'user', content: 'Hello' }],
      },
      ignoreHTTPSErrors: true,
    });
    expect(response.status()).toBe(403);
  });

  test('MCP search endpoint responds', async ({ request }) => {
    // Initialize MCP session
    const init = await request.post('https://ai.example.com:8081/mcp', {
      headers: {
        'apikey': 'admin-key-12345',
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      },
      data: {
        jsonrpc: '2.0', id: 1, method: 'initialize',
        params: {
          protocolVersion: '2025-03-26',
          capabilities: {},
          clientInfo: { name: 'playwright-test', version: '1.0' },
        },
      },
      ignoreHTTPSErrors: true,
    });
    expect(init.status()).toBe(200);
    const body = await init.text();
    expect(body).toContain('ihor-sokoliuk/mcp-searxng');
  });

  test('Kong rate limiting headers present on MCP', async ({ request }) => {
    const response = await request.post('https://ai.example.com:8081/mcp', {
      headers: {
        'apikey': 'admin-key-12345',
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
      },
      data: {
        jsonrpc: '2.0', id: 1, method: 'initialize',
        params: {
          protocolVersion: '2025-03-26',
          capabilities: {},
          clientInfo: { name: 'test', version: '1.0' },
        },
      },
      ignoreHTTPSErrors: true,
    });
    expect(response.headers()['ratelimit-limit']).toBe('30');
    expect(response.headers()['ratelimit-remaining']).toBeDefined();
  });
});

test.describe('Grafana Observability', () => {
  const GRAFANA_URL = 'https://grafana.example.com:8081';
  const GRAFANA_AUTH = { username: 'admin', password: 'admin' };

  test('Grafana is accessible and has datasources', async ({ request }) => {
    const response = await request.get(`${GRAFANA_URL}/api/datasources`, {
      headers: {
        'Authorization': 'Basic ' + Buffer.from('admin:admin').toString('base64'),
      },
      ignoreHTTPSErrors: true,
    });
    expect(response.status()).toBe(200);
    const datasources = await response.json();
    const names = datasources.map((ds: any) => ds.name);
    expect(names).toContain('Prometheus');
    expect(names).toContain('Tempo');
  });

  test('Kong AI Gateway dashboard exists with token panels', async ({ request }) => {
    const response = await request.get(`${GRAFANA_URL}/api/dashboards/uid/kong-ai-gateway`, {
      headers: {
        'Authorization': 'Basic ' + Buffer.from('admin:admin').toString('base64'),
      },
      ignoreHTTPSErrors: true,
    });
    expect(response.status()).toBe(200);
    const data = await response.json();
    const panelTitles = data.dashboard.panels
      .flatMap((p: any) => p.panels ? p.panels.map((s: any) => s.title) : [p.title]);
    // Token usage panels
    expect(panelTitles).toContain('Total Prompt Tokens');
    expect(panelTitles).toContain('Total Completion Tokens');
    expect(panelTitles).toContain('Token Usage by Consumer');
    // Cost panels
    expect(panelTitles).toContain('Estimated Total Cost (USD)');
    expect(panelTitles).toContain('Cost by Consumer (USD)');
    expect(panelTitles).toContain('Cost by Provider (USD)');
  });

  test('Kuma Service Mesh dashboard exists', async ({ request }) => {
    const response = await request.get(`${GRAFANA_URL}/api/dashboards/uid/kuma-mesh`, {
      headers: {
        'Authorization': 'Basic ' + Buffer.from('admin:admin').toString('base64'),
      },
      ignoreHTTPSErrors: true,
    });
    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data.dashboard.title).toBe('Kuma Service Mesh');
  });

  test('Prometheus has token and cost metrics', async ({ request }) => {
    // Query Grafana's unified alerting query endpoint which is more stable than the datasource proxy
    const response = await request.get(`${GRAFANA_URL}/api/datasources/uid/prometheus`, {
      headers: { 'Authorization': 'Basic ' + Buffer.from('admin:admin').toString('base64') },
      ignoreHTTPSErrors: true,
    });
    expect(response.status()).toBe(200);
    const ds = await response.json();
    // Build direct Prometheus URL from datasource config
    const promUrl = ds.url;

    // Query Prometheus via Grafana datasource proxy with retry
    let metricsResponse;
    for (let attempt = 0; attempt < 3; attempt++) {
      metricsResponse = await request.get(
        `${GRAFANA_URL}/api/datasources/proxy/uid/prometheus/api/v1/label/__name__/values`,
        {
          headers: { 'Authorization': 'Basic ' + Buffer.from('admin:admin').toString('base64') },
          ignoreHTTPSErrors: true,
        },
      );
      if (metricsResponse.status() === 200) break;
      await new Promise(r => setTimeout(r, 2000));
    }
    expect(metricsResponse!.status()).toBe(200);
    const data = await metricsResponse!.json();
    const metrics = data.data as string[];
    expect(metrics).toContain('ai_llm_tokens_total');
    expect(metrics).toContain('ai_llm_estimated_cost_usd');
    expect(metrics).toContain('ai_llm_requests_total');
  });

  test('token usage per consumer is queryable', async ({ request }) => {
    const query = 'sum by (consumer) (ai_llm_tokens_total)';
    let response;
    for (let attempt = 0; attempt < 3; attempt++) {
      response = await request.get(
        `${GRAFANA_URL}/api/datasources/proxy/uid/prometheus/api/v1/query?query=${encodeURIComponent(query)}`,
        {
          headers: { 'Authorization': 'Basic ' + Buffer.from('admin:admin').toString('base64') },
          ignoreHTTPSErrors: true,
        },
      );
      if (response.status() === 200) break;
      await new Promise(r => setTimeout(r, 2000));
    }
    expect(response!.status()).toBe(200);
    const data = await response!.json();
    expect(data.status).toBe('success');
    const results = data.data.result;
    expect(results.length).toBeGreaterThan(0);
    const consumers = results.map((r: any) => r.metric.consumer);
    console.log(`  Token usage by consumer: ${consumers.join(', ')}`);
  });

  test('estimated cost per consumer is queryable', async ({ request }) => {
    const query = 'sum by (consumer) (ai_llm_estimated_cost_usd)';
    let response;
    for (let attempt = 0; attempt < 3; attempt++) {
      response = await request.get(
        `${GRAFANA_URL}/api/datasources/proxy/uid/prometheus/api/v1/query?query=${encodeURIComponent(query)}`,
        {
          headers: { 'Authorization': 'Basic ' + Buffer.from('admin:admin').toString('base64') },
          ignoreHTTPSErrors: true,
        },
      );
      if (response.status() === 200) break;
      await new Promise(r => setTimeout(r, 2000));
    }
    expect(response!.status()).toBe(200);
    const data = await response!.json();
    expect(data.status).toBe('success');
    const results = data.data.result;
    expect(results.length).toBeGreaterThan(0);
    for (const r of results) {
      const cost = parseFloat(r.value[1]);
      console.log(`  Consumer "${r.metric.consumer}": $${cost.toFixed(6)}`);
    }
  });

  test('Tempo has Kong traces', async ({ request }) => {
    const response = await request.get(
      `${GRAFANA_URL}/api/datasources/proxy/uid/tempo/api/search?tags=service.name%3Dkong&limit=5`,
      {
        headers: {
          'Authorization': 'Basic ' + Buffer.from('admin:admin').toString('base64'),
        },
        ignoreHTTPSErrors: true,
      },
    );
    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data.traces.length).toBeGreaterThan(0);
    // Verify trace has expected structure
    const trace = data.traces[0];
    expect(trace.traceID).toBeDefined();
    expect(trace.rootServiceName).toBeDefined();
    expect(trace.durationMs).toBeGreaterThan(0);
    console.log(`  Found ${data.traces.length} Kong traces, latest: ${trace.rootTraceName} (${trace.durationMs}ms)`);
  });

  test('Grafana dashboards render in browser', async ({ page }) => {
    // Login to Grafana
    await page.goto(`${GRAFANA_URL}/login`);
    await page.fill('input[name="user"]', 'admin');
    await page.fill('input[name="password"]', 'admin');
    await page.getByRole('button', { name: /log in/i }).first().click();
    await page.waitForTimeout(2000);

    // Open Kong AI Gateway dashboard
    await page.goto(`${GRAFANA_URL}/d/kong-ai-gateway?orgId=1&refresh=10s`);
    await page.waitForTimeout(5000);

    // Verify key panels are visible (top row, no scroll needed)
    await expect(page.locator('text=Total AI Requests').first()).toBeVisible({ timeout: 10000 });
    await expect(page.locator('text=Request Rate by Provider').first()).toBeVisible({ timeout: 10000 });
    await expect(page.locator('text=Requests by Consumer').first()).toBeVisible({ timeout: 10000 });

    // Scroll down to token/cost section and verify
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(2000);
    await expect(page.locator('text=Token Usage by Consumer').first()).toBeVisible({ timeout: 10000 });

    await page.screenshot({ path: 'test-results/grafana-ai-dashboard.png', fullPage: true });
  });
});
