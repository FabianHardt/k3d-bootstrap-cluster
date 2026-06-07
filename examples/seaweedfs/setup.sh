#!/bin/bash
set -o errexit

# Deploy SeaweedFS as a self-contained, S3-compatible object store for demos
# (backup targets, ML artifact stores, etc.). Apache-2.0 licensed; intended as a
# Lab-friendly alternative to MinIO.
#
# Endpoint (cluster-internal):  http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333
# Demo credentials:             seaweedadmin / seaweedadminsecret
#
# Usage:
#   bash setup.sh              # deploys SeaweedFS, creates bucket "demo"
#   bash setup.sh mybucket     # also creates an additional bucket

EXTRA_BUCKET="${1:-}"

kubectl apply -f seaweedfs.yaml

echo "Waiting for SeaweedFS to become ready…"
kubectl -n seaweedfs rollout status statefulset/seaweedfs --timeout=300s

create_bucket() {
  local name="$1"
  echo "Creating bucket: ${name}"
  kubectl -n seaweedfs exec seaweedfs-0 -- \
    sh -c "echo 's3.bucket.create -name ${name}' | weed shell -master localhost:9333 -filer localhost:8888" \
    || true
}

create_bucket "demo"
if [ -n "${EXTRA_BUCKET}" ]; then
  create_bucket "${EXTRA_BUCKET}"
fi

echo ""
echo "SeaweedFS is ready."
echo "  S3 endpoint (in-cluster): http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333"
echo "  Access key:               seaweedadmin"
echo "  Secret key:               seaweedadminsecret"
