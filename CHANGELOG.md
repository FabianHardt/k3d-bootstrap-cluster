# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

* Prerequisite preflight check in `create-sample.sh` (`checkPrerequisites`): fails fast with a clear message when a required CLI tool (`docker`, `k3d`, `kubectl`, `helm`, `jq`) is missing or when no Docker engine is reachable, instead of cryptic mid-run errors. The engine check also catches Rancher Desktop configured with the `containerd` engine (no Docker socket). The README and getting-started docs now note that Rancher Desktop must use the `dockerd (moby)` engine.
* CI smoke test for the Kong AI Gateway showcase (`examples/kong-ai-gateway/`). Runs as an experimental `showcase (kong-ai-gateway)` matrix job that boots the minimal stack (Ollama + `llama3.2:1b`, OpenWebUI, SearXNG MCP tool server) non-interactively and asserts the core workloads roll out and Ollama serves the local model. To support it, `setup.sh` now honours `NON_INTERACTIVE=1` (skips all prompts, safe defaults) and the smoke workflow runs every showcase setup non-interactively. The Enterprise-gated external AI routes remain covered by the Playwright browser-tests.
* HAProxy Ingress Controller as a standalone, opt-in showcase (`examples/haproxy/setup.sh`, `docs/showcases/haproxy.md`). Installs HAProxy as a secondary, non-default `IngressClass` (`haproxy`) alongside the cluster's default Kong Gateway for users who want to experiment with classic `Ingress` resources.
* Cilium CNI (1.19.4) as the new default CNI in the interactive cluster setup (`CILIUM_FLAG`, default Yes), replacing Flannel. Installed from the host via Helm right after cluster creation, since a k3s `HelmChart` manifest cannot bootstrap a CNI (its install job is never scheduled on the CNI-less nodes). The Cilium images are pulled on the host and loaded into the nodes with `k3d image import` so the bootstrap also works on slow or NATed networks. A k3d node entrypoint script (`manifests/k3d-entrypoint-cilium.sh`) prepares the bpffs and cgroup2 mounts that the Cilium agent requires inside the k3s node containers. The CI smoke tests cover the new default with a dedicated `cilium` bootstrap variant. (#62, #65)
* Non-interactive mode for `create-sample.sh`: `NON_INTERACTIVE=1` skips all prompts, and every default can be overridden via environment variable (`CLUSTER_NAME`, `SERVERS`, `AGENTS`, ports, component flags). Documented in the README. (#61)
* CI: static linting workflow (`.github/workflows/lint.yml`) running shellcheck, yamllint and kubeconform over all shell scripts and Kubernetes manifests. (#60)
* CI: k3d cluster smoke tests (`.github/workflows/smoke.yml`) — bootstrap matrix plus one job per showcase boots a real cluster on every PR and verifies it end-to-end (`kubectl wait`, curl through the ingress). The runner pins the nip.io hostnames to loopback to avoid flaky external DNS resolution. (#61, #64)
* CI: documentation previews for pull requests, deployed via the `gh-pages` branch. (#59)

### Changed

* **Kong Gateway (Gateway API) is now the sole ingress controller** for the cluster bootstrap and every showcase (#55). Traefik is unconditionally disabled, Kong is installed unconditionally by `create-sample.sh`, and all showcase scripts/docs (`openbao`, `cloudnative-pg`, `kafka-cluster`, `velero`, `external-dns`, `crossplane`, `kuma-mesh`, `kyverno`, `kong-gateway`, `kong-gateway-operator`, `cluster-api`) have been simplified to a single Kong + `HTTPRoute` path. No more `HAPROXY_FLAG` / `KONG_FLAG` branching or ingress auto-detection.
* Calico CNI is no longer the default: the prompt default flips to No (`CALICO_FLAG=No`). It remains available as an opt-in alternative to Cilium (the two are mutually exclusive). The Calico NetworkPolicies showcase requires a cluster created with `CALICO_FLAG=Yes`.

### Removed

* `HAPROXY_FLAG` and the HAProxy bootstrap prompt from `create-sample.sh` / `helpers.sh`.
* `manifests/haproxy-helm.yaml`, `httpbin/sample-ingress-haproxy.yaml`, `httpbin/sample-ingress.yaml` (Traefik fallback) — superseded by the Kong-only `httpbin/sample-httproute-kong.yaml`.
* HAProxy-specific variants from showcases: `examples/openbao/{cert-ingress.yaml,openbao-values.yaml}`, `examples/cloudnative-pg/pgadmin-values.yaml`, `examples/kafka-cluster/kafka-ui/kafka-ui-values.yaml`, `examples/external-dns/update-httpbin-ingress.yaml`, `examples/velero/nginx-ingress-haproxy.yaml`, `examples/crossplane/platform/04-composition-haproxy.yaml`, `examples/kyverno/policy-reporter-ingress.yml`.
* Leftover Confluent showcase (`examples/confluent/`) and its stale README/docs references — the Kafka showcase had already been migrated to Strimzi in 1.4.0. (#63)

### Fixed

* Kuma CNI now chains onto the active CNI instead of a hard-coded Calico conflist. `installKumaStandalone` detects the primary CNI (Cilium / Calico / Flannel) and sets `cni.confName` accordingly. Previously `standalone-cp-values.yaml` pinned `10-calico.conflist`, so on the now-default Cilium cluster the `kuma-cni-node` DaemonSet crash-looped, leaving Kuma's `NodeReadiness:NoSchedule` taint on every node — any newly created pod (e.g. `tempo` after the monitoring/Kuma restart) stayed `Pending` and `setup.sh` timed out. Affects the kuma-mesh showcase and the Kong AI Gateway Kuma path.
* `helpers.sh`: the Cilium images are now imported as a single-platform tarball (`docker save --platform linux/<arch>` → `k3d image import <tar>`, arch derived from `uname`). On Docker Desktop / Rancher Desktop with the containerd image store the local store keeps the full multi-arch index even after a `--platform` pull, so a plain `k3d image import <image>` exported the index and failed on every node with `ctr: content digest sha256:...: not found` (cosmetic — the node still got its arch's layers, but noisy). Exporting only the node's platform imports cleanly. Daemons without `docker save --platform` fall back to a plain import.
* `examples/kong-ai-gateway/mcp-searxng.yaml`: the SearXNG MCP server now binds on `0.0.0.0` (`MCP_HTTP_HOST`). Newer `isokoliuk/mcp-searxng:latest` images default the HTTP transport to `127.0.0.1`, so the readiness probe (and Kong/OpenWebUI) hit "connection refused" on the pod IP and the deployment never became Available — `setup.sh` failed at the `mcp-searxng` wait. Surfaced by the new Kong AI Gateway smoke test.
* `examples/kong-gateway/setup.sh`: applying the experimental Gateway API CRDs no longer races the just-deleted `safe-upgrades` ValidatingAdmissionPolicy — the script now waits for the deletion to propagate through the API server's admission cache. Found by the CI smoke tests. (#61)

## [1.4.0] - 2026-06-03

### Added

* CloudNativePG showcase (`examples/cloudnative-pg/`) demonstrating the CloudNativePG operator for managing PostgreSQL clusters on Kubernetes. Deploys a sample `Cluster` CR with a pre-configured database, and pgAdmin 4 as a web UI client — pre-registered with the sample cluster. Supports both HAProxy and Kong Gateway API ingress modes. Includes documentation (`docs/showcases/cloudnative-pg.md`).
* Grafana Observability Stack showcase (`examples/grafana-stack/`) with Grafana, Prometheus, and Tempo deployed via Helm charts. Demonstrates OpenTelemetry instrumentation of the Kong AI Gateway plugins with span export to Tempo, and metrics collection by Prometheus. Includes a pre-configured Grafana dashboard for visualising AI plugin performance and costs, and documentation (`docs/showcases/grafana-stack.md`).
* Strimzi Kafka cluster showcase (`examples/kafka-cluster/`) deploying a production-sized, KRaft-based Kafka cluster (no ZooKeeper) using the Strimzi operator 1.0.0. Includes 3 brokers in combined controller/broker mode via `KafkaNodePool`, Apicurio Registry (operator-managed, Kafka SQL storage), Kafka HTTP Bridge, and kafbat-ui as a web management console. Comes with k6 load tests for plain, JSON, and Avro message patterns (`examples/kafka-cluster/loadtest/`). Supports both HAProxy and Kong Gateway API ingress modes. Includes documentation (`docs/showcases/kafka-cluster.md`).
* SeaweedFS showcase (`examples/seaweedfs/`) providing a self-contained, S3-compatible object store as a license-friendly (Apache-2.0) alternative to MinIO. Deploys a single-pod `weed server -filer -s3` `StatefulSet` with a 10 GiB PVC, a default `demo` bucket, and static Lab credentials. Intended as a reusable backup target / artifact store for other showcases. Includes documentation (`docs/showcases/seaweedfs.md`).
* Velero Backup & Restore showcase (`examples/velero/`) demonstrating a full backup/restore lifecycle on the local cluster: nginx + PVC sample workload, Velero installed via the official Helm chart with the AWS plugin against the in-cluster SeaweedFS S3 endpoint, `node-agent` DaemonSet with Kopia-based file-system backup (no CSI snapshots required for k3d's local-path storage). Includes an end-to-end `demo.sh` (write data → backup → delete namespace → restore → verify) and an optional daily `Schedule`. Reuses the SeaweedFS showcase as a dependency (same pattern as External Secrets → OpenBao). Includes documentation (`docs/showcases/velero.md`).

### Changed

* **Kong AI Gateway plugin consolidation**: reduced from 24 to 14 plugins and from 15 to 9 routes. Removed per-model routes and plugins (`ai-proxy-coder`, `ai-proxy-gemma`, `ai-proxy-ollama`, `ai-models-response-coder`, `ai-models-response-gemma`, `ai-models-response-enterprise`). All models are now routed through `ai-proxy-advanced-multimodel` on the unified `/ollama/*` route. Authentication unified to `ai-key-auth-or-oidc` everywhere (removed separate `ai-key-auth`). Removed unused plugins: `ai-block-anonymous`, `ai-model-acl`, `acl-anthropic`.
* All AI route YAML files now contain the final plugin annotations directly (OIDC, semantic cache, nostream, tracing) instead of being patched at the end of `setup.sh`. The Enterprise route-patching block in `setup.sh` was removed.
* `kong-ai-plugins.yaml` now contains only the `ai-force-nostream` pre-function plugin (was: `ai-proxy-ollama` + `ai-key-auth`).
* `kong-ai-oidc-plugin.yaml` simplified: removed `ai-block-anonymous` request-termination plugin. The anonymous consumer remains for the OIDC fallback chain.
* Kong Gateway Helm values (`examples/kong-gateway/values.yaml`): added `tracing_instrumentations: all` to enable OpenTelemetry span export.
* Grafana values (`grafana-values.yaml`): added Tempo datasource (port 3200) with Service Map and Node Graph enabled. Added Kuma dashboard provider and ConfigMap.
* Prometheus values (`prometheus-values.yaml`): added `kuma-dataplanes` scrape job using `kubernetes_sd_configs` with `kuma.io/sidecar-injected` annotation filter on port 5670. Added `web.enable-remote-write-receiver` flag for Tempo metrics generator.
* Grafana AI dashboard (`grafana-dashboard-ai.json`): cost panels now use the pre-calculated `ai_llm_estimated_cost_usd` metric from the AI Metrics Exporter instead of inline token-price multiplication. Pricing reference table updated to show the inflated demo pricing.
* `ai-proxy-advanced-multimodel` plugin: added `read_timeout: 300000` in balancer config to handle Ollama model swap delays. Removed `model_alias` field (requires Enterprise license to be loaded first).
* `setup.sh`: Enterprise license wait loop now actively polls the Kong Admin API for plugin count (>50 = Enterprise) instead of a fixed `sleep 5`. Monitoring namespace is added to the Kuma mesh with sidecar injection when both monitoring and Kuma are enabled.
* Kuma standalone values (`examples/kuma-mesh/standalone-cp-values.yaml`): changed `extraSecrets` from `[]` (array) to `{}` (map) to fix Helm template error with newer Kuma chart versions.

### Removed

* Separate per-model routes and plugins: `kong-ai-route-coder.yaml`, `kong-ai-route-coder-internal.yaml`, `kong-ai-route-gemma.yaml`, `kong-ai-route-gemma-internal.yaml`, `kong-ai-route-models-extra.yaml` are no longer applied by `setup.sh`. Files remain on disk for reference.
* `ai-proxy-ollama`, `ai-proxy-coder`, `ai-proxy-gemma` plugins (replaced by `ai-proxy-advanced-multimodel`).
* `ai-key-auth` plugin (replaced by `ai-key-auth-or-oidc` on all routes).
* `ai-block-anonymous`, `ai-model-acl`, `acl-anthropic` plugins (unused after consolidation).
* `ai-models-response`, `ai-models-response-coder`, `ai-models-response-gemma`, `ai-models-response-enterprise` plugins (replaced by `ai-models-filtered` post-function).
* Enterprise route-patching block at the end of `setup.sh` (routes now have correct annotations in their YAML files).
* Confluent for Kubernetes showcase (`examples/confluent/`) — replaced by the Strimzi Kafka cluster showcase. Strimzi is CNCF-hosted, fully open-source, and supports the current KRaft-based Kafka deployment model without ZooKeeper.

### Fixed

## [1.3.0] - 2026-05-27

### Added

* Headlamp Kubernetes Dashboard added as an optional component in the interactive cluster setup (`create-sample.sh`). Detects existing ingress controller and deploys the corresponding Helm values file for HAProxy, Kong Gateway, or Traefik. If no ingress controller is detected, Headlamp is installed without ingress resources and can be accessed via `kubectl port-forward` instead. Dedicated documentation page for the Headlamp showcase (`docs/showcases/headlamp.md`).

### Fixed

* Helm repo for cert-manager could not be resolved on fresh installations. The Kong Gateway setup script (`examples/kong-gateway/setup.sh`) now adds the `jetstack` Helm repository explicitly before attempting to install cert-manager ([#52](https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/52)).

## [1.2.0] - 2026-04-20

### Added

* Crossplane Platform Engineering showcase (`examples/crossplane/`) demonstrating the Platform Team / Developer Team split with Crossplane and the Kubernetes provider. The Platform Team defines an `AppEnvironment` XRD and Composition; developers create a single Claim and receive a fully provisioned Namespace, Deployment, Service, and Ingress/HTTPRoute automatically. Supports both HAProxy and Kong Gateway API ingress modes. Includes German-language documentation for classroom use (`docs/showcases/crossplane.md`).

## [1.1.1] - 2026-04-09

### Fixed

* Replaced deprecated Bitnami Helm chart for ExternalDNS (`bitnami/external-dns`) with the official chart (`external-dns/external-dns` from `https://kubernetes-sigs.github.io/external-dns/`). The official chart uses images from `registry.k8s.io/external-dns/external-dns` which are always accessible. Provider configuration changed from `--set provider=coredns` to `--set provider.name=coredns`; etcd endpoint is now passed via the `ETCD_URLS` environment variable.
* Replaced Bitnami etcd Helm chart with a plain Kubernetes manifest (`etcd.yaml`) using the `registry.k8s.io/etcd:3.5.16-0` image. Bitnami images (`docker.io/bitnami/etcd`) were not pullable, causing the ExternalDNS showcase to fail entirely.
* ExternalDNS sources are now set explicitly depending on the ingress mode: `ingress` for HAProxy, `gateway-httproute` for Kong Gateway (closes [#45](https://github.com/FabianHardt/k3d-bootstrap-cluster/issues/45)).

## [1.1.0] - 2026-04-09

### Added

* OpenBao showcase (`examples/openbao/`) — OpenBao is an open-source fork of HashiCorp Vault maintained by the Linux Foundation after Vault's license change to BSL. The API and `bao` CLI are fully compatible with Vault. Includes automated setup script, Helm values for HAProxy and Kong Gateway, HTTPRoute/Ingress resources, and a dedicated documentation page (`docs/showcases/openbao.md`).
* Multi-ingress support across showcases: `external-dns`, `external-secrets`, `kyverno`, and `kuma-mesh` now support both HAProxy Ingress and Kong Gateway API (HTTPRoute). The ingress mode is auto-detected from the cluster or can be forced via `HAPROXY_FLAG=Yes` / `KONG_FLAG=Yes`.
* HTTPRoute resources for Kong Gateway added to `examples/external-dns/`, `examples/kyverno/`, and `examples/openbao/`.

### Changed

* Kong Gateway TLS passthrough (`TLSRoute`) now requires `parameters: [ssl]` on the `proxy.stream` entry in `values.yaml`. Kong KIC only recognises a stream listener as `TLSProtocolType` when the Admin API reports `SSL=true` for that listener. Without the flag KIC sets the Gateway listener to `UnsupportedProtocol` and the TLSRoute stays in `NoMatchingParent`. Documented in `docs/showcases/kong.md`.
* Added PostgreSQL 17 TLS passthrough demo to the Kong Gateway showcase (`examples/kong-gateway/`). Demonstrates SNI-based routing of non-HTTP traffic using PostgreSQL 17 direct SSL (`sslnegotiation=direct`). Includes a cert-manager Certificate issued by OpenBao PKI, an init container to fix TLS key permissions, and a `TLSRoute` for `postgres.example.com`. The Gateway `kong-tls-passthrough` listener hostname widened to `*.example.com` to support multiple backends on the same listener.
* Extended `examples/kong-gateway/setup.sh` to deploy the PostgreSQL TLS passthrough demo automatically.
* Kong Gateway Operator: updated `GatewayConfiguration` to align with current CRD schema (`examples/kong-gateway-operator/`).
* Kuma Mesh helpers extended with additional wait logic and improved cluster setup (`examples/kuma-mesh/helpers.sh`).

### Removed

* HashiCorp Vault showcase (`examples/vault/`) — replaced by the OpenBao showcase. OpenBao is a fully API-compatible drop-in replacement.

## [1.0.0] - 2026-04-05

### Added

* Kong Gateway (Gateway API) as a selectable alternative to HAProxy Ingress in the interactive cluster setup (`create-sample.sh`). Installs Gateway API CRDs v1.5.1, a `GatewayClass`/`Gateway`, and Kong Ingress Controller via Helm chart `kong/ingress` v0.24.0. httpbin is exposed via an `HTTPRoute` instead of an `Ingress` resource. Kong and HAProxy are mutually exclusive — selecting Kong disables Traefik and auto-deselects HAProxy.
* Cluster API (CAPI) showcase using the Docker infrastructure provider (CAPD) and k3s control-plane provider. Includes interactive setup, worker scaling, teardown, and httpbin deployment on the workload cluster exposed via the management cluster's HAProxy ingress (`examples/cluster-api/`)
* VitePress documentation page for the Cluster API showcase
* `CONTRIBUTING.md` and GitHub PR template (`.github/pull_request_template.md`)

### Changed

* Updated Gateway API installation to version 1.5.1 in Kong showcase setup scripts (`examples/kong-gateway/`, `examples/kong-gateway-operator/`)
* Updated Kong Gateway image to 3.13.0.2 and Kong Ingress Controller to 3.5.6 in `examples/kong-gateway/values.yaml`

## [0.9.0] - 2026-04-03

### Changed

* Replaced NGINX Ingress Controller with HAProxy Ingress Controller (chart `haproxy-ingress` v0.14.7). Updated all samples, examples and documentation accordingly.
* Updated Gateway API installation to version 1.4.0 in setup scripts by [@svenbernhardt](https://github.com/svenbernhardt) in [#37](https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/37)
* Updated k3d installation guide to version 5.8.3

### Removed

* `manifests/nginx-helm.yaml` replaced by `manifests/haproxy-helm.yaml`
* `httpbin/sample-ingress-nginx.yaml` replaced by `httpbin/sample-ingress-haproxy.yaml`
* `examples/calico/allow-ingress-egress-nginx.yml` replaced by `examples/calico/allow-ingress-egress-haproxy.yml`

## [0.8.0] - 2025-05-12

### Changed

* Changed example for installing and using Kong Gateway resp. Kong Ingress Controller to use [Gateway Discovery Topology](https://docs.konghq.com/kubernetes-ingress-controller/latest/production/deployment-topologies/gateway-discovery/) by [@svenbernhardt](https://github.com/svenbernhardt) in [#35](https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/35)
* Updated cert-manager installation to enable CRDs via `crds.enabled` flag in [#36](https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/36)

## [0.7.0] - 2024-09-19

### Added

* Update k3d cluster template by [@FabianHardt](https://github.com/FabianHardt) in [#30](https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/30)
* Calico NetworkPolicy examples by [@FabianHardt](https://github.com/FabianHardt/) in [#30](https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/30)

### Changed

- The main [README.md](https://github.com/FabianHardt/k3d-bootstrap-cluster/blob/main/README.md) file was updated

## [0.6.0] - 2024-09-16

### Added

* Add example for installing and using Kong Gateway Operator by [@svenbernhardt](https://github.com/svenbernhardt) in [#29](https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/29)

### Fixed

- Vitapress docs now allow invalid HTML links to localhost

## [0.5.0] - 2024-06-27

### Added
* Add documentation by @PhilKuer in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/27
* add node taints and lables by @FabianHardt in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/28

### Fixed


## [0.4.4] - 2024-03-15

### Added

- Confluent for Kubernetes by @d4kine in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/17
- Init version of Kyverno example by @FabianHardt in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/24

### Fixed

- Waiting for Nginx ingress to be completely bootstrapped by @svenbernhardt in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/26

## [0.4.3] - 2024-02-15

### Fixed

- Fix issue #22 by @svenbernhardt in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/23

## [0.4.2] - 2024-02-15

### Fixed

- Fix templating issue by @FabianHardt in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/20
- Fix issue #20 by @FabianHardt in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/21

## [0.4.1] - 2023-08-11

### Fixed

- Helm install problems with newest chart by @FabianHardt in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/16
- Added LB-Host to /etc/hosts File by @PhilKuer in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/18

## [0.4.0] - 2022-12-21

### Added

- Kuma Service Mesh added to examples by @d4kine in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/13

### Fixed

- Fix issue 14, some port improvements by @FabianHardt in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/15

## [0.3.0] - 2022-11-11

### Added

- Kong API Gateway sample was added by @FabianHardt in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/9
  - Installs Kong API Gateway in Hybrid mode - separate Control- and Dataplane instances
  - Installs Kong Ingress controller instead of NGINX Ingress
  - More information to this setup mode: https://thecattlecrew.net/2022/09/02/kong-api-gateway-basics-deployment-modes-und-data-plane-installation-per-ansible/


## [0.2.0] - 2022-11-04

### Added

- External Secrets Operator (ESO) sample added by @FabianHardt in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/8

### Fixed

- Fixed cluster_name based on current kubectl context by @PhilKuer in https://github.com/FabianHardt/k3d-bootstrap-cluster/pull/7

## [0.1.0] - 2022-11-02

### Changed

- K3d cluster creation with interactive mode  - by @FabianHardt in https://github.com/FabianHardt/k3d-sample-cluster/pull/1
- Added external-dns sample. Demonstrates ExternalDNS, which configures an external CoreDNS server - by @FabianHardt in https://github.com/FabianHardt/k3d-sample-cluster/pull/2
- Added Hashicorp Vault as CA server in combination with cert-manager do demonstrate auto generated certificates - by @FabianHardt in https://github.com/FabianHardt/k3d-sample-cluster/pull/6

[unreleased]: https://github.com/FabianHardt/k3d-bootstrap-cluster/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/FabianHardt/k3d-bootstrap-cluster/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/FabianHardt/k3d-bootstrap-cluster/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/FabianHardt/k3d-bootstrap-cluster/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/FabianHardt/k3d-bootstrap-cluster/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/FabianHardt/k3d-bootstrap-cluster/compare/v0.9.0...v1.0.0
[0.9.0]: https://github.com/FabianHardt/k3d-bootstrap-cluster/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/FabianHardt/k3d-bootstrap-cluster/compare/v0.7.0...v0.8.0
[0.4.4]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/FabianHardt/k3d-sample-cluster/commits/v0.1.0