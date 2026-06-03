# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

* CloudNativePG showcase (`examples/cloudnative-pg/`) demonstrating the CloudNativePG operator for managing PostgreSQL clusters on Kubernetes. Deploys a sample `Cluster` CR with a pre-configured database, and pgAdmin 4 as a web UI client — pre-registered with the sample cluster. Supports both HAProxy and Kong Gateway API ingress modes. Includes documentation (`docs/showcases/cloudnative-pg.md`).
* Strimzi Kafka cluster showcase (`examples/kafka-cluster/`) deploying a production-sized, KRaft-based Kafka cluster (no ZooKeeper) using the Strimzi operator 1.0.0. Includes 3 brokers in combined controller/broker mode via `KafkaNodePool`, Apicurio Registry (operator-managed, Kafka SQL storage), Kafka HTTP Bridge, and kafbat-ui as a web management console. Comes with k6 load tests for plain, JSON, and Avro message patterns (`examples/kafka-cluster/loadtest/`). Supports both HAProxy and Kong Gateway API ingress modes. Includes documentation (`docs/showcases/kafka-cluster.md`).
* SeaweedFS showcase (`examples/seaweedfs/`) providing a self-contained, S3-compatible object store as a license-friendly (Apache-2.0) alternative to MinIO. Deploys a single-pod `weed server -filer -s3` `StatefulSet` with a 10 GiB PVC, a default `demo` bucket, and static Lab credentials. Intended as a reusable backup target / artifact store for other showcases. Includes documentation (`docs/showcases/seaweedfs.md`).
* Velero Backup & Restore showcase (`examples/velero/`) demonstrating a full backup/restore lifecycle on the local cluster: nginx + PVC sample workload, Velero installed via the official Helm chart with the AWS plugin against the in-cluster SeaweedFS S3 endpoint, `node-agent` DaemonSet with Kopia-based file-system backup (no CSI snapshots required for k3d's local-path storage). Includes an end-to-end `demo.sh` (write data → backup → delete namespace → restore → verify) and an optional daily `Schedule`. Reuses the SeaweedFS showcase as a dependency (same pattern as External Secrets → OpenBao). Includes documentation (`docs/showcases/velero.md`).

### Changed

### Removed

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