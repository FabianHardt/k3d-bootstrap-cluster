# SeaweedFS (S3-compatible Object Store)

### Description

[SeaweedFS](https://seaweedfs.com/) is a fast, distributed object store with an Apache-2.0 license. This showcase deploys a single-pod, all-in-one SeaweedFS instance that exposes an S3-compatible endpoint inside the cluster. It serves as a lightweight, license-friendly alternative to MinIO for demos that need an object store — for example as the backup target for the [Velero](./velero.html) showcase.

### Installation

```bash
cd examples/seaweedfs
bash setup.sh
```

Optionally pass an additional bucket name to create:

```bash
bash setup.sh my-extra-bucket
```

The setup script:

- Creates the `seaweedfs` namespace
- Deploys SeaweedFS as a `StatefulSet` running `weed server -filer -s3` (master, volume, filer and S3 gateway in one pod)
- Provisions a 10 GiB PVC for object data
- Creates a default bucket called `demo`

### Endpoint and credentials

| Property | Value |
|---|---|
| In-cluster S3 endpoint | `http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333` |
| Filer HTTP API | `http://seaweedfs.seaweedfs.svc.cluster.local:8888` |
| Master HTTP API | `http://seaweedfs.seaweedfs.svc.cluster.local:9333` |
| Access key | `seaweedadmin` |
| Secret key | `seaweedadminsecret` |

> The credentials are static and committed to this repo. They are intended for **local Lab use only** — never reuse them in any environment that is reachable beyond your machine.

### Smoke test with the AWS CLI

From inside the cluster (or via `kubectl run` with the `amazon/aws-cli` image):

```bash
kubectl run aws-cli --rm -it --restart=Never \
  --image=amazon/aws-cli:latest \
  --env=AWS_ACCESS_KEY_ID=seaweedadmin \
  --env=AWS_SECRET_ACCESS_KEY=seaweedadminsecret \
  -- s3 --endpoint-url http://seaweedfs-s3.seaweedfs:8333 ls
```

### Managing buckets via `weed shell`

```bash
kubectl -n seaweedfs exec -it seaweedfs-0 -- \
  sh -c "echo 's3.bucket.list' | weed shell -master localhost:9333 -filer localhost:8888"
```

### Used by

- [Velero Backup & Restore](./velero.html) — uses SeaweedFS as the backup storage location.

### Cleanup

```bash
kubectl delete namespace seaweedfs
```
