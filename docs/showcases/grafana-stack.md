# Grafana Observability Stack

This showcase deploys a lightweight observability stack — **Prometheus**, **Grafana Tempo**, and **Grafana** — to the `monitoring` namespace. It serves as the shared monitoring foundation for other showcases like [Kong AI Gateway](./kong-ai-gateway.md) and [Kuma Service Mesh](./kuma.md).

## Components

| Component | Source | Namespace |
|-----------|--------|-----------|
| Prometheus | Helm chart `prometheus-community/prometheus` | `monitoring` |
| Grafana Tempo | Helm chart `grafana/tempo` | `monitoring` |
| Grafana | Helm chart `grafana/grafana` | `monitoring` |

## Preconditions

- k3d cluster deployed
- `helm` CLI installed

## DNS preparation

Add the following entry to `/etc/hosts`:

```
127.0.0.1 grafana.example.com
```

## Installation

```bash
cd examples/grafana-stack
bash setup.sh
```

The script:
1. Creates the `monitoring` namespace with Kuma sidecar injection enabled
2. Adds the `prometheus-community` and `grafana` Helm repositories
3. Deploys Prometheus, Tempo, and Grafana via Helm
4. Waits for all deployments to be ready
5. Applies an HTTPRoute to expose Grafana at `https://grafana.example.com:8081`

## Endpoints

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | `https://grafana.example.com:8081` | admin / admin |

## Architecture

```
Any scrape target ──▶ Prometheus ──┐
                          ▲         ├──▶ Grafana
Any OTLP source ────▶ Tempo ───────┘
  (service graph metrics remote write)
```

### Prometheus

Prometheus is deployed as a minimal scrape engine with no alertmanager, node-exporter, or kube-state-metrics. It also acts as a remote write receiver, so Tempo can push generated service graph and span metrics back into it.

Other showcases register their own scrape targets by extending `prometheus-values.yaml` or deploying ServiceMonitor resources.

### Grafana Tempo

Tempo runs in single-binary mode and receives traces via OTLP:

| Protocol | Endpoint |
|----------|----------|
| OTLP HTTP | `:4318` |
| OTLP gRPC | `:4317` |

The metrics generator is enabled and writes service graph and span metrics to Prometheus, powering Grafana's **Service Map** and **Node Graph** panels.

> **Kuma mTLS note:** The gRPC OTLP port (4317) is excluded from Kuma sidecar inbound interception (`traffic.kuma.io/exclude-inbound-ports: "4317"`). Kuma's MeshTrace plugin sends plain gRPC to Tempo — not mTLS — so the sidecar must not intercept it.

### Grafana

Grafana is pre-configured with two datasources:

| Datasource | URL |
|------------|-----|
| Prometheus (default) | `http://prometheus-server.monitoring.svc.cluster.local:80` |
| Tempo | `http://tempo.monitoring.svc.cluster.local:3200` |

The Tempo datasource has **Service Map** and **Node Graph** enabled, backed by Prometheus for service graph metrics.

## Adding dashboards via ConfigMap sidecar

Grafana's sidecar container watches for ConfigMaps with the label `grafana_dashboard=true` across all namespaces and automatically loads them as dashboards — no Grafana restart required.

This allows other showcases to ship their own dashboards independently, without modifying the Grafana Helm values.

**How to add a dashboard:**

1. Export the dashboard JSON from Grafana (Dashboard → Share → Export → Save to file)
2. Create a ConfigMap from the JSON file and label it `grafana_dashboard=true`:

```bash
kubectl create configmap my-dashboard \
    --namespace my-namespace \
    --from-file=my-dashboard.json=my-dashboard.json \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap my-dashboard \
    -n my-namespace grafana_dashboard=true
```

The sidecar picks up the new ConfigMap within seconds and the dashboard appears in Grafana under **Dashboards**.

### Example: Kuma Service Mesh dashboard

The [Kuma showcase](./kuma.md) uses this mechanism to register its dashboard. The relevant part of `examples/kuma-mesh/setup.sh`:

```bash
kubectl create configmap grafana-dashboard-kuma \
    --namespace kuma-cp \
    --from-file=kuma-mesh.json=grafana-dashboard-kuma.json \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap grafana-dashboard-kuma \
    -n kuma-cp grafana_dashboard=true --overwrite
```

The ConfigMap is created in the `kuma-cp` namespace — the namespace does not have to be `monitoring`. Because the Grafana sidecar watches cluster-wide, any labeled ConfigMap is discovered regardless of namespace.

## Explore traces

1. Open `https://grafana.example.com:8081`
2. Navigate to **Explore** (compass icon in the left sidebar)
3. Select **Tempo** as the datasource
4. Use **Search** to browse traces by service name, duration, or status
5. Click a trace to see the full span waterfall

For the **Service Map**, select **Tempo → Service Graph** in Explore to see a live topology of services and their request rates.
