#!/bin/bash
set -o errexit

# Deploy SeaweedFS via the official Helm chart in all-in-one mode (S3 + SFTP in
# one pod). SFTP uses certificate-only authentication: clients present an SSH
# user certificate signed by a local CA (upstream feature, PR #9815).
#
# The S3 gateway is kept (static lab credentials) so the Velero showcase keeps
# using SeaweedFS as its backup target.
#
# Usage:
#   bash setup.sh              # deploys SeaweedFS, creates bucket "demo"
#   bash setup.sh mybucket     # also creates an additional bucket
#
# Endpoints (cluster-internal):
#   S3:   http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333
#   SFTP: seaweedfs-all-in-one.seaweedfs.svc.cluster.local:2022
# Demo S3 credentials:  seaweedadmin / seaweedadminsecret

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

EXTRA_BUCKET="${1:-}"
CHART_VERSION="${CHART_VERSION:-4.35.0}"
CERT_VALIDITY="${CERT_VALIDITY:-+12w}"   # SSH user certificate validity
CERT_PRINCIPAL="admin"                   # must match a user in the chart's SFTP user store

KEYS_DIR="${SCRIPT_DIR}/.keys"
mkdir -p "${KEYS_DIR}"

# ---------------------------------------------------------------------------
# 1. Generate the SSH user CA, the server host key, and a signed user cert.
#    All idempotent — existing keys are reused so re-runs are cheap.
# ---------------------------------------------------------------------------
if [ ! -f "${KEYS_DIR}/ca_user" ]; then
  echo "Generating SSH user CA…"
  ssh-keygen -t ed25519 -N "" -C "seaweedfs-sftp-user-ca" -f "${KEYS_DIR}/ca_user" >/dev/null
fi

if [ ! -f "${KEYS_DIR}/ssh_host_ed25519_key" ]; then
  echo "Generating SFTP server host key…"
  ssh-keygen -t ed25519 -N "" -C "seaweedfs-sftp-host" -f "${KEYS_DIR}/ssh_host_ed25519_key" >/dev/null
fi

if [ ! -f "${KEYS_DIR}/id_${CERT_PRINCIPAL}" ]; then
  echo "Generating client key for '${CERT_PRINCIPAL}'…"
  ssh-keygen -t ed25519 -N "" -C "seaweedfs-sftp-${CERT_PRINCIPAL}" -f "${KEYS_DIR}/id_${CERT_PRINCIPAL}" >/dev/null
fi

echo "Signing a ${CERT_VALIDITY} user certificate for principal '${CERT_PRINCIPAL}'…"
ssh-keygen -s "${KEYS_DIR}/ca_user" \
  -I "${CERT_PRINCIPAL}@k3d" \
  -n "${CERT_PRINCIPAL}" \
  -V "${CERT_VALIDITY}" \
  "${KEYS_DIR}/id_${CERT_PRINCIPAL}.pub" >/dev/null

# ---------------------------------------------------------------------------
# 2. Namespace and supporting Secrets (must exist before the pod starts).
# ---------------------------------------------------------------------------
kubectl create namespace seaweedfs --dry-run=client -o yaml | kubectl apply -f -

# Static S3 identity so Velero's credentials keep working unchanged.
kubectl -n seaweedfs create secret generic seaweedfs-s3-auth \
  --from-literal=seaweedfs_s3_config='{"identities":[{"name":"admin","credentials":[{"accessKey":"seaweedadmin","secretKey":"seaweedadminsecret"}],"actions":["Admin","Read","Write","List","Tagging"]}]}' \
  --dry-run=client -o yaml | kubectl apply -f -

# SFTP server host key (mounted at the chart's hostKeysFolder, /etc/sw/ssh).
kubectl -n seaweedfs create secret generic seaweedfs-sftp-host-key \
  --from-file=ssh_host_ed25519_key="${KEYS_DIR}/ssh_host_ed25519_key" \
  --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# 3. Install the chart. The CA public key is injected at install time.
# ---------------------------------------------------------------------------
helm repo add seaweedfs https://seaweedfs.github.io/seaweedfs/helm >/dev/null 2>&1 || true
helm repo update seaweedfs >/dev/null

helm upgrade --install seaweedfs seaweedfs/seaweedfs \
  --version "${CHART_VERSION}" \
  --namespace seaweedfs \
  --values values.yaml \
  --set-file sftp.trustedUserCAKeys="${KEYS_DIR}/ca_user.pub"

echo "Waiting for SeaweedFS to become ready…"
kubectl -n seaweedfs rollout status deployment/seaweedfs-all-in-one --timeout=300s

# Compatibility alias so the documented S3 endpoint (seaweedfs-s3) keeps working.
kubectl apply -f s3-alias-service.yaml

# Add HTTP-Route for web ui
kubectl apply -f httproute.yaml

# ---------------------------------------------------------------------------
# 4. Create buckets via the in-pod weed shell.
# ---------------------------------------------------------------------------
POD="$(kubectl -n seaweedfs get pod -l app.kubernetes.io/component=seaweedfs-all-in-one \
  -o jsonpath='{.items[0].metadata.name}')"

create_bucket() {
  local name="$1"
  echo "Creating bucket: ${name}"
  kubectl -n seaweedfs exec "${POD}" -- \
    sh -c "echo 's3.bucket.create -name ${name}' | weed shell -master localhost:9333 -filer localhost:8888" \
    || true
}

create_bucket "demo"
if [ -n "${EXTRA_BUCKET}" ]; then
  create_bucket "${EXTRA_BUCKET}"
fi

# ---------------------------------------------------------------------------
echo ""
echo "SeaweedFS is ready (S3 + SFTP, certificate auth)."
echo "  S3 endpoint (in-cluster): http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333"
echo "  S3 access / secret key:   seaweedadmin / seaweedadminsecret"
echo ""
echo "  SFTP user certificate:    .keys/id_${CERT_PRINCIPAL}-cert.pub (principal '${CERT_PRINCIPAL}', valid ${CERT_VALIDITY})"
echo "  Connect via SFTP:         bash connect.sh"
