# External Secrets Operator (ESO)

### Precondition

Cluster has to be deployed with the *httpbin* sample. Otherwise this demo wouldn't work.

Vault example is automatically deployed with this example. If you already have a deployed Vault instance, this script will skip the Vault installation.

### Installation

You can install External Secrets Operator with the following startup command:

```bash
cd examples/external-secrets
bash setup.sh
```

The following components are installed with the *setup.sh*:

- All components described in this [README](examples/vault/README.md)
- Key/Value Store is configured on Vault server
  - An example secret is added to new KV secret store (hello/world)
- ESO is deployed via HELM Chart to new namespace *external-secrets*
- Connection to Vault is configured as ClusterSecretStore (clusterwide)
- Two ExternalSecret samples are deployed to namespace *demo*
  - example-secret - automatically creates a new K8s secret, named *k8s-secret*, from Vault to namespace *demo*
  - example-secret2 - automatically creates a new K8s secret, named *k8s-secret2*,  from Vault to namespace *demo*

### Test

You can test and watch the newly created K8s secrets with the following command:

```bash
BASE64_STRING=$(kubectl -n demo get secrets k8s-secret -o json | jq -r .data.helloKey)
echo $BASE64_STRING | base64 -d
# should return "world"
```

### Troubleshooting

There could be some problems with existing filehandles, for example on the rootCA, installed into Hashicorp Vault. In this case please drop the namespaces and try again:

```bash
kubectl delete ns vault
kubectl delete ns cert-manager
kubectl delete ns external-secrets
```

