# Kyverno / Policy Reporter

### Description

In this example Kyverno and Policy Reporter incl. UI will be deployed. As an example the default Pod Security Policies are deployed by this script. More details here:

- https://kubernetes.io/docs/concepts/security/pod-security-standards/
- https://kyverno.io/policies/pod-security/

### Installation

You can install Kyverno and the Kyverno Policy Reporter with the following startup command:

```bash
cd examples/kyverno
bash setup.sh
```

The following components are installed with the *setup.sh*:

- Kyverno is installed via HELM Chart
- Policy Reporter (API, Kyverno Plugin and UI) is installed via HELM Chart
- Example policies deployed - https://kyverno.io/policies/pod-security/
  - You can check this: `kubectl get clusterpolicies.kyverno.io`
  - These examples are deployed in *Audit* mode - you can see failing policies in the Policy Reporter UI, but they are not permitted by Kyverno.


### Show Policy Reporter UI

The Policy Reporter UI is exposed via Ingress, you can open Policy-Reporter-UI in a browser of your choice: https://policy-reporter-127-0-0-1.nip.io:8081/#/