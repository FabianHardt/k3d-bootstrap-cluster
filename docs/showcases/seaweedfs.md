# SeaweedFS (S3 + SFTP with certificate auth)

### Description

[SeaweedFS](https://seaweedfs.com/) is a fast, distributed object store with an Apache-2.0 license. This showcase deploys SeaweedFS via its official Helm chart in **all-in-one mode** — master, volume, filer, S3 gateway and SFTP server in a single pod — and configures the SFTP server for **certificate-based authentication**: clients log in with short-lived SSH user certificates signed by a local certificate authority (CA), instead of statically listed passwords or public keys.

Certificate auth for the SeaweedFS SFTP server comes from upstream [PR #9815](https://github.com/seaweedfs/seaweedfs/pull/9815) and mirrors OpenSSH's `TrustedUserCAKeys` and MinIO's `--sftp=trusted-user-ca-key`.

The S3 gateway is kept enabled so SeaweedFS remains the backup target for the [Velero](./velero.html) showcase.

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

- Generates the SSH key material (see below) under `examples/seaweedfs/.keys/` (git-ignored)
- Creates the `seaweedfs` namespace and the supporting Secrets (static S3 identity, SFTP host key)
- Installs the `seaweedfs/seaweedfs` Helm chart (all-in-one: S3 + SFTP), injecting the CA public key
- Adds a `seaweedfs-s3` compatibility Service so the documented S3 endpoint keeps resolving
- Creates a default bucket called `demo`

### Endpoints and credentials

| Property | Value |
|---|---|
| In-cluster S3 endpoint | `http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333` |
| In-cluster SFTP | `seaweedfs-all-in-one.seaweedfs.svc.cluster.local:2022` |
| S3 access key | `seaweedadmin` |
| S3 secret key | `seaweedadminsecret` |
| SFTP login | certificate only (principal `admin`) |
| Admin-UI | ` https://seaweedfs-ui.example.com:8081/` |

> The S3 credentials and all generated keys are intended for **local Lab use only** — never reuse them anywhere reachable beyond your machine. The CA private key (`.keys/ca_user`) can mint logins for the SFTP server; it stays on your machine and is git-ignored.

### SSH keys and CA signing

Certificate authentication replaces "which public keys may log in?" with "which CA do I trust to vouch for users?". The server is told one thing — the **public key of a trusted user CA** — and then accepts any user certificate that CA has signed, without the server ever seeing the individual keys in advance. `setup.sh` sets up three independent key pairs:

| Key pair | File(s) in `.keys/` | Role |
|---|---|---|
| **User CA** | `ca_user`, `ca_user.pub` | Signs user certificates. Only its **public** key is given to the server (`-sftp.trustedUserCAKeysFile`). The private key is the trust anchor — guard it. |
| **Server host key** | `ssh_host_ed25519_key` | Identifies the *server* to clients (the usual SSH host key). Mounted into the pod under the chart's `hostKeysFolder`. |
| **Client key** | `id_admin`, `id_admin.pub` | The *user's* own key pair. The public half gets signed by the CA into a certificate. |

#### How a certificate is issued

The CA signs the client's **public** key into a certificate with `ssh-keygen -s`:

```bash
ssh-keygen -s ca_user \        # sign with the CA private key
  -I admin@k3d \               # key identity (free-form label, shows up in logs)
  -n admin \                   # principal(s): the SSH login name(s) this cert is valid for
  -V +12w \                    # validity window (here: now .. +12 weeks)
  id_admin.pub                 # the public key to sign
```

This produces `id_admin-cert.pub` next to `id_admin.pub`. The certificate bundles the client's public key, the list of valid **principals**, a validity window, and the CA's signature. Nothing about it is secret — it is presented to the server during login, alongside proof that the client holds the matching private key `id_admin`.

#### What the server checks on login

When a client connects, the SeaweedFS SFTP server (via `ssh.CertChecker`) accepts the login only if **all** of these hold:

1. The certificate is a **user** certificate (not a host certificate).
2. Its signature verifies against one of the trusted CA public keys.
3. The current time is within the certificate's `ValidAfter` … `ValidBefore` window.
4. The certificate lists at least one principal, and the **SSH login name is among them** (here: logging in as `admin` requires `admin` in `-n`).
5. The login name resolves to an existing user in SeaweedFS's user store (the chart ships an `admin` user, which is why we sign for that principal).

Because `authMethods` is set to `certificate` only, plain public keys and passwords are **rejected** — a key that the CA has not signed cannot log in, even if it would otherwise be a valid SSH key.

#### Why certificates instead of static keys

- **No central key list to maintain.** Onboarding or rotating a user is a `ssh-keygen -s` away; the server config never changes.
- **Built-in expiry.** `-V` gives every credential a lifetime, so a leaked cert stops working on its own. Re-issue with the same command (re-run `bash setup.sh`, or override `CERT_VALIDITY`).
- **Scoped by principal.** A certificate is only valid for the login names in `-n`, so one CA can issue narrowly-scoped credentials for many users.

### Connecting via SFTP

```bash
bash connect.sh          # scripted upload / list / download demo
bash connect.sh shell    # interactive sftp prompt
```

`connect.sh` port-forwards the in-cluster SFTP port to `localhost:2022` and runs `sftp` with the issued certificate. The equivalent manual invocation:

```bash
kubectl -n seaweedfs port-forward deployment/seaweedfs-all-in-one 2022:2022 &

sftp -P 2022 \
  -i .keys/id_admin \
  -o CertificateFile=.keys/id_admin-cert.pub \
  -o StrictHostKeyChecking=no \
  admin@127.0.0.1
```

### Issuing another certificate

To add a credential for a different user, sign a cert whose principal matches a user in the SFTP user store. To add new users you would override the chart's SFTP user store (`allInOne.sftp.existingConfigSecret`); the chart ships `admin`, `readonly_user` and `public_user` out of the box. Example for `readonly_user`:

```bash
cd examples/seaweedfs/.keys
ssh-keygen -t ed25519 -N "" -f id_readonly
ssh-keygen -s ca_user -I readonly@k3d -n readonly_user -V +1w id_readonly.pub
sftp -P 2022 -i id_readonly -o CertificateFile=id_readonly-cert.pub readonly_user@127.0.0.1
```

### Smoke test the S3 side with the AWS CLI

```bash
kubectl run aws-cli --rm -it --restart=Never \
  --image=amazon/aws-cli:latest \
  --env=AWS_ACCESS_KEY_ID=seaweedadmin \
  --env=AWS_SECRET_ACCESS_KEY=seaweedadminsecret \
  -- s3 --endpoint-url http://seaweedfs-s3.seaweedfs:8333 ls
```

### Managing buckets via `weed shell`

```bash
POD=$(kubectl -n seaweedfs get pod -l app.kubernetes.io/component=seaweedfs-all-in-one -o jsonpath='{.items[0].metadata.name}')
kubectl -n seaweedfs exec -it "$POD" -- \
  sh -c "echo 's3.bucket.list' | weed shell -master localhost:9333 -filer localhost:8888"
```

### Used by

- [Velero Backup & Restore](./velero.html) — uses SeaweedFS as the backup storage location (via the `seaweedfs-s3` S3 endpoint).

### Cleanup

```bash
helm -n seaweedfs uninstall seaweedfs
kubectl delete namespace seaweedfs
```
