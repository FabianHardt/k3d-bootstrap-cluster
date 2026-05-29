# CloudNativePG

[CloudNativePG](https://cloudnative-pg.io) is a Kubernetes operator that manages the full lifecycle of highly available PostgreSQL clusters. It provides native Kubernetes integration for PostgreSQL via a `Cluster` custom resource, including automated failover, backup/restore, and rolling updates.

This showcase deploys a CloudNativePG operator, a sample PostgreSQL cluster, and [pgAdmin 4](https://www.pgadmin.org) as a web-based database management UI — pre-configured to connect to the sample cluster.

### Precondition

A running k3d cluster. The httpbin sample is not required for this showcase.

### Installation

```bash
cd examples/cloudnative-pg

# With HAProxy Ingress Controller
HAPROXY_FLAG=Yes bash setup.sh

# With Kong Gateway (Gateway API)
KONG_FLAG=Yes bash setup.sh
```

If neither flag is set, the ingress controller is auto-detected from the cluster. If none is found, pgAdmin is accessible via port-forward only.

The following components are installed by `setup.sh`:

- **CloudNativePG operator** — Helm Chart (namespace: `cnpg-system`)
- **PostgreSQL cluster** — `Cluster` CR `sample-pg` (namespace: `cloudnative-pg`)
  - 1 instance (suitable for local demo)
  - Database `sampledb`, owner `appuser`
  - Exposes `sample-pg-rw` (read-write) and `sample-pg-ro` (read-only) services
- **pgAdmin 4** — Helm Chart (namespace: `pgadmin`)
  - Pre-configured server connection to `sample-pg`
  - Ingress configured via Helm values, matching the detected ingress controller

### Access pgAdmin UI

Open pgAdmin in your browser via http://pgadmin.127-0-0-1.nip.io:8080.

Login credentials:

| Field    | Value               |
|----------|---------------------|
| Email    | admin@example.com   |
| Password | admin               |

The server `sample-pg (primary)` is pre-registered under the group `CloudNativePG`. Use the password `apppassword` when prompted for the database connection.

### Access pgAdmin without Ingress

If no ingress controller was detected, use port-forward:

```bash
kubectl port-forward svc/pgadmin4 -n pgadmin 8888:80
```

Then open: http://localhost:8888

### Connect to PostgreSQL directly

Retrieve the superuser credentials created by CloudNativePG:

```bash
kubectl get secret sample-pg-superuser -n cloudnative-pg \
  -o jsonpath='{.data.username}' | base64 -d

kubectl get secret sample-pg-superuser -n cloudnative-pg \
  -o jsonpath='{.data.password}' | base64 -d
```

Connect via psql from inside the cluster:

```bash
kubectl run psql --rm -it --image=postgres:16 --restart=Never -- \
  psql -h sample-pg-rw.cloudnative-pg.svc -U appuser -d sampledb
```

### Cleanup

```bash
kubectl delete cluster sample-pg -n cloudnative-pg
helm uninstall pgadmin4 -n pgadmin
helm uninstall cnpg -n cnpg-system
kubectl delete namespace cloudnative-pg pgadmin cnpg-system
```
