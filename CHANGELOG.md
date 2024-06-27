# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added


### Changed


### Removed

### Fixed

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

[unreleased]: https://github.com/olivierlacan/keep-a-changelog/compare/v0.4.4...HEAD
[0.4.4]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/FabianHardt/k3d-sample-cluster/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/FabianHardt/k3d-sample-cluster/commits/v0.1.0