# Velero — Backup & Restore

### Description

[Velero](https://velero.io/) is a CNCF tool for backing up, restoring and migrating Kubernetes resources and persistent volumes. This showcase demonstrates a complete backup/restore lifecycle on the local k3d cluster:

1. Deploy a small sample workload (`nginx` Deployment with a PVC) into namespace `demo-velero`.
2. Write data into the PVC.
3. Create a Velero **Backup** of the namespace.
4. Delete the namespace to simulate a disaster.
5. **Restore** from the backup and verify the data is intact.

PVC contents are backed up via Velero's file-system backup (`kopia` uploader, `node-agent` DaemonSet). This avoids the need for CSI volume snapshots, which the k3d default `local-path` storage class does not support.

### Backup target

Velero needs an S3-compatible object store for its backups. This example uses [SeaweedFS](./seaweedfs.html) as a license-friendly, fully in-cluster backend. The Velero `setup.sh` automatically deploys the [SeaweedFS showcase](./seaweedfs.html) as a dependency if it is not already running — the same pattern used by the [External Secrets](./external-secrets.html) showcase with OpenBao.

### Installation

```bash
cd examples/velero
bash setup.sh
```

The setup script:

- Ensures SeaweedFS is deployed and the `velero` bucket exists
- Installs Velero via the official Helm chart `vmware-tanzu/velero` with:
  - The AWS plugin (used for any S3-compatible target)
  - `BackupStorageLocation` pointing to SeaweedFS
  - `defaultVolumesToFsBackup: true` and the `node-agent` DaemonSet
- Deploys the sample workload in namespace `demo-velero`
- Exposes the demo nginx via a Kong Gateway `HTTPRoute` — so the restored page becomes visible in the browser at:

  <http://nginx-velero.127-0-0-1.nip.io:8080/>
- Deletes the default `httpbin` `HTTPRoute` in namespace `demo`. That route has no host filter and would otherwise act as a wildcard, serving httpbin's content under the nginx-velero hostname during the "disaster" step and hiding the failure. If you want httpbin back later, re-apply it from `httpbin/sample-httproute-kong.yaml`.

### Run the demo

```bash
cd examples/velero
bash demo.sh
```

The `demo.sh` script drives a full disaster-recovery cycle end to end. Each step is described below so you know what to watch for in the output and which resources to inspect in parallel (e.g. with `kubectl get backups -n velero -w`).

#### Step 1 — Write demo data into the PVC

```bash
kubectl -n demo-velero exec deploy/nginx -- \
  sh -c 'echo "<h1>backed up at $(date)</h1>" > /usr/share/nginx/html/index.html'
curl http://nginx-velero.127-0-0-1.nip.io:8080/
```

The nginx pod mounts a `PersistentVolumeClaim` (`nginx-data`) at `/usr/share/nginx/html`. The script writes a timestamped HTML file into that volume and then verifies it through the **HTTPRoute** (`HTTP 200`, page body contains the timestamp). The current timestamp is what we will later check for after the restore — if the restored page matches, the **volume contents** (not just the manifest) survived the round-trip.

Open <http://nginx-velero.127-0-0-1.nip.io:8080/> in a browser to follow along visually.

#### Step 2 — Create a Velero Backup

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: demo-backup-<timestamp>
  namespace: velero
spec:
  includedNamespaces:
    - demo-velero
  defaultVolumesToFsBackup: true   # back up PVC contents via Kopia, not just manifests
  ttl: 24h0m0s
```

What happens under the hood:

1. The Velero server controller picks up the new `Backup` CR.
2. It enumerates all Kubernetes objects in `demo-velero` (Namespace, Deployment, PVC, Service, ConfigMaps, etc.) and writes them as a tarball into the **SeaweedFS** S3 bucket `velero/backups/<backup-name>/`.
3. Because `defaultVolumesToFsBackup: true` is set, the **`node-agent`** DaemonSet pod running on the same node as the nginx pod uses **Kopia** to stream the contents of the mounted PVC into the same backup location. This produces one `PodVolumeBackup` CR per backed-up volume.
4. The script polls `.status.phase` of the `Backup` CR every 5 seconds. The phase transitions roughly: `New` → `InProgress` → `Completed`. A `Failed` or `PartiallyFailed` phase aborts the script.

While the backup runs you can watch it live in another terminal:

```bash
kubectl -n velero get backups -w
kubectl -n velero get podvolumebackups
kubectl -n velero logs deploy/velero -f
```

#### Step 3 — Simulate a disaster

```bash
kubectl delete namespace demo-velero --wait=true
```

Deleting the namespace removes **all** objects in it: the Deployment, the ReplicaSet, the Pod, the Service, the `HTTPRoute`, **and** the `PersistentVolumeClaim`. With k3d's default `local-path` storage class, deleting the PVC also reclaims the underlying volume — so the data on disk is genuinely gone. This is the equivalent of an accidental `kubectl delete ns` in production or a wiped node.

If you reload <http://nginx-velero.127-0-0-1.nip.io:8080/> in the browser now, you will get a connection error or a 404 from the ingress controller — the route no longer exists. The script reflects this with `(request failed — expected during the disaster step)` in its output.

#### Step 4 — Restore from the backup

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: demo-backup-<timestamp>-restore
  namespace: velero
spec:
  backupName: demo-backup-<timestamp>
```

The Velero server:

1. Fetches the backup tarball from SeaweedFS and re-creates the Kubernetes objects (Namespace, PVC, Deployment, Service, …).
2. When the new Pod for the nginx Deployment is scheduled, an **init container** injected by the `node-agent` blocks startup until Kopia has restored the PVC contents from SeaweedFS into the freshly provisioned volume.
3. Only after the file-system restore is done does the actual nginx container start, with the original `index.html` already present on disk.

The script polls the `Restore`'s `.status.phase` until it reaches `Completed`. `PartiallyFailed` is treated as a failure here because we expect a clean round-trip in this demo.

#### Step 5 — Verify the restored data

```bash
kubectl -n demo-velero rollout status deployment/nginx
kubectl -n demo-velero exec deploy/nginx -- cat /usr/share/nginx/html/index.html
curl http://nginx-velero.127-0-0-1.nip.io:8080/
```

The script waits for the nginx Deployment to roll out, then polls the URL until it returns HTTP 200 (the ingress controller needs a few seconds to pick up the restored `HTTPRoute`). The final `cat` and `curl` must both print the same `<h1>backed up at …</h1>` line written in step 1 — same timestamp, same wording. Reloading the browser tab at <http://nginx-velero.127-0-0-1.nip.io:8080/> now shows the page again.

If it does, you have verified:

- Kubernetes manifests were correctly captured and restored (including `HTTPRoute`)
- PVC contents were captured and restored byte-for-byte via Kopia
- The pod re-attached to the restored volume
- The ingress controller picked the restored route back up and is serving traffic again

#### What if it does *not* match?

A few things are worth checking if the verification fails:

- `kubectl -n velero describe backup <name>` — look at warnings/errors and the `Volume Backups` block.
- `kubectl -n velero get podvolumebackups` — was the PVC actually picked up? If a row shows `Completed` for the `data` volume, the backup side worked.
- `kubectl -n velero describe restore <name>` and `kubectl -n velero get podvolumerestores` — same on the restore side.
- `kubectl -n velero logs ds/node-agent` — Kopia errors (e.g. network issues reaching SeaweedFS) show up here.
- `kubectl -n seaweedfs exec seaweedfs-0 -- sh -c "echo 's3.bucket.list' | weed shell -master localhost:9333 -filer localhost:8888"` — confirm the `velero` bucket exists and has objects.

### Inspect backups and restores

```bash
kubectl -n velero get backups
kubectl -n velero get restores
kubectl -n velero get podvolumebackups   # file-system backup details
```

### Scheduled backups

A daily schedule example is included:

```bash
kubectl apply -f schedule.yaml
kubectl -n velero get schedules
```

### Optional: install the Velero CLI

Most operations in this showcase are driven via plain `kubectl`, but the Velero CLI gives a much nicer UX (`velero backup create …`, `velero backup describe …`). Install instructions:

- <https://velero.io/docs/main/basic-install/#install-the-cli>

### Cleanup

```bash
helm uninstall -n velero velero
kubectl delete namespace velero demo-velero
# Optionally also remove the backup store:
kubectl delete namespace seaweedfs
```

### Notes and caveats

- The S3 credentials for SeaweedFS are static and committed to this repo — Lab use only.
- File-system backup with `kopia` works for any storage class but is slower than CSI snapshots. For production-grade clusters with CSI snapshot support, use `VolumeSnapshotLocation` instead.
- Velero's AWS plugin is used because SeaweedFS speaks the S3 protocol — no MinIO is involved.
