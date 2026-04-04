# Cluster API (CAPI)

This showcase demonstrates [Cluster API (CAPI)](https://cluster-api.sigs.k8s.io/) — a Kubernetes sub-project that brings declarative, Kubernetes-style APIs to cluster lifecycle management. The standard k3d cluster acts as the **management cluster**, from which workload clusters are created and scaled via Kubernetes resources.

### About this demo

CAPI itself is fully **platform agnostic**. It supports infrastructure providers for AWS, Azure, GCP, vSphere, and many more. This demo uses the **Docker infrastructure provider (CAPD)**, which creates Kubernetes nodes as local Docker containers — making it ideal for local development and demos without any cloud account.

The infrastructure-specific parts (`DockerCluster`, `DockerMachineTemplate`) are the only pieces that change when targeting a different provider. The k3s control plane (`KThreesControlPlane`) and the bootstrap configuration remain identical across all providers.

### Preconditions

- The k3d management cluster must be created with **CAPI support enabled** (answer `Yes` to *"Enable Cluster API (CAPI) support?"* in `create-sample.sh`). This mounts the Docker socket into the k3d server and agent nodes, which CAPD requires to create workload cluster nodes as Docker containers.
- [`clusterctl`](https://cluster-api.sigs.k8s.io/user/quick-start.html#install-clusterctl) must be installed on your host:

```bash
brew install clusterctl
```

### Installation

```bash
cd examples/cluster-api
bash setup.sh
```

The script will:
1. Configure `clusterctl` to use the k3s bootstrap and control-plane providers
2. Initialize CAPI on the management cluster (core, k3s bootstrap, k3s control-plane, Docker infrastructure)
3. Remove the httpbin sample from the management cluster
4. Create a workload cluster with 1 control plane node and 1 worker node (via Cluster API)
5. Connect the workload cluster containers to the management cluster's Docker network
6. Deploy httpbin on the workload cluster and expose it through the management cluster's HAProxy ingress

### Accessing httpbin

Once setup is complete, httpbin running in the workload cluster is accessible via the management cluster's load balancer:

```
http://127-0-0-1.nip.io:8080
```

To interact with the workload cluster directly:

```bash
export KUBECONFIG=examples/cluster-api/workload-kubeconfig.yaml
kubectl get nodes
kubectl get po -A
```

### Scaling workers

Add or remove worker nodes interactively:

```bash
cd examples/cluster-api
bash scale-workers.sh
```

The script shows the current number of worker replicas and prompts for the desired count:

```
Using management cluster context: k3d-demo
Tip: CAPI resources always live on the management cluster, regardless of your current kubeconfig/context.

Current worker replicas: 1
Desired number of workers [1]: 3

Scaling worker nodes to 3
-------------------------------------
machinedeployment.cluster.x-k8s.io/workload-cluster-md-0 scaled
Waiting for 3 machines to be ready...
  Connected workload-cluster-md-0-...-xxxxx to k3d-demo
  Removed cloud-provider taint from workload-cluster-md-0-...-xxxxx
  Ready: 2/3 — waiting...
  ...

NAME                              STATUS   ROLES                       AGE   VERSION
workload-cluster-kcp-*            Ready    control-plane,etcd,master   ...   v1.30.2+k3s2
workload-cluster-md-0-*           Ready    <none>                      ...   v1.30.2+k3s2
workload-cluster-md-0-*           Ready    <none>                      ...   v1.30.2+k3s2
workload-cluster-md-0-*           Ready    <none>                      ...   v1.30.2+k3s2
```

CAPI reconciles the `MachineDeployment` to the desired replica count by provisioning or deleting Docker containers. Scaling down removes worker nodes gracefully.

::: tip
Always run `scale-workers.sh` from the `examples/cluster-api/` directory, and regardless of which `KUBECONFIG` is currently active in your shell — the script always targets the management cluster context (`k3d-demo`).
:::

### Teardown

```bash
cd examples/cluster-api
bash teardown.sh
```

This will:
1. Delete the workload cluster via CAPI (all Docker containers for CP and workers are removed)
2. Wait for full deletion
3. Remove the local `workload-kubeconfig.yaml`
4. Re-deploy httpbin on the management cluster

### Architecture

```
Host machine
└── Docker
    ├── k3d management cluster (k3d-demo)   ← CAPI controllers run here
    │   └── HAProxy Ingress → Endpoints → workload cluster worker
    │
    └── Workload cluster (CAPD / Docker)
        ├── workload-cluster-lb              ← HAProxy LB for API server
        ├── workload-cluster-kcp-*           ← k3s control plane node
        └── workload-cluster-md-*            ← k3s worker node (httpbin)
```

Both cluster sets share the `k3d-demo` Docker network, enabling the management cluster's HAProxy to route HTTP traffic directly to the workload cluster worker's NodePort.

::: warning Docker requirement
CAPD requires access to the Docker socket to create and manage workload cluster nodes as containers. This is handled automatically when CAPI support is enabled in `create-sample.sh`. Switching to a cloud provider (e.g. AWS, Azure) would remove this requirement entirely — only the infrastructure manifests (`DockerCluster` → `AWSCluster`, etc.) would need to change.
:::
