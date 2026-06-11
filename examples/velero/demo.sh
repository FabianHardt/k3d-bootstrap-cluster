#!/bin/bash
set -o errexit

# End-to-end Velero demo:
#   1) Write data into the nginx PVC and show the page via Ingress/HTTPRoute
#   2) Create a backup of the demo-velero namespace
#   3) Simulate disaster by deleting the namespace (URL goes 404)
#   4) Restore from the backup
#   5) Verify the data and the URL are back
#
# This script uses `kubectl` only — the Velero CLI is not required.

BACKUP_NAME="demo-backup-$(date +%s)"
NGINX_URL="http://nginx-velero.127-0-0-1.nip.io:8080/"

# Is the demo nginx exposed via Ingress or HTTPRoute? If so, we curl the URL
# during the demo to make the disaster/recovery visible from the host side.
EXPOSED="no"
if kubectl -n demo-velero get ingress nginx &>/dev/null \
   || kubectl -n demo-velero get httproute nginx &>/dev/null; then
  EXPOSED="yes"
fi

curl_url() {
  local label="$1"
  if [ "${EXPOSED}" != "yes" ]; then
    return
  fi
  echo "    ${label}  curl ${NGINX_URL}"
  # -s silent, -S show errors, -o stdout, -w status code; never abort the script
  curl -sS --max-time 5 -o /dev/stdout -w "    HTTP %{http_code}\n" "${NGINX_URL}" \
    || echo "    (request failed — expected during the disaster step)"
}

echo "==> 1) Writing demo data into nginx PVC"
kubectl -n demo-velero exec deploy/nginx -- \
  sh -c 'echo "<h1>backed up at $(date)</h1>" > /usr/share/nginx/html/index.html'
echo "    File on PVC:"
kubectl -n demo-velero exec deploy/nginx -- cat /usr/share/nginx/html/index.html
curl_url "Page via ingress (before backup):"

echo ""
echo "==> 2) Creating backup: ${BACKUP_NAME}"
cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: ${BACKUP_NAME}
  namespace: velero
spec:
  includedNamespaces:
    - demo-velero
  defaultVolumesToFsBackup: true
  ttl: 24h0m0s
EOF

echo "    Waiting for backup to complete…"
for _ in $(seq 1 60); do
  PHASE=$(kubectl -n velero get backup "${BACKUP_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  echo "    phase=${PHASE}"
  [ "${PHASE}" = "Completed" ] && break
  [ "${PHASE}" = "Failed" ] && { echo "Backup failed."; exit 1; }
  sleep 5
done

echo ""
echo "==> 3) Simulating disaster — deleting namespace demo-velero"
kubectl delete namespace demo-velero --wait=true
curl_url "Page via ingress (after delete — should be unavailable):"

echo ""
echo "==> 4) Restoring from backup: ${BACKUP_NAME}"
RESTORE_NAME="${BACKUP_NAME}-restore"
cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: ${RESTORE_NAME}
  namespace: velero
spec:
  backupName: ${BACKUP_NAME}
EOF

echo "    Waiting for restore to complete…"
for _ in $(seq 1 60); do
  PHASE=$(kubectl -n velero get restore "${RESTORE_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  echo "    phase=${PHASE}"
  [ "${PHASE}" = "Completed" ] && break
  [ "${PHASE}" = "Failed" ] || [ "${PHASE}" = "PartiallyFailed" ] && { echo "Restore did not complete cleanly: ${PHASE}"; exit 1; }
  sleep 5
done

echo ""
echo "==> 5) Verifying restored data"
kubectl -n demo-velero rollout status deployment/nginx --timeout=120s
echo "    File on PVC:"
kubectl -n demo-velero exec deploy/nginx -- cat /usr/share/nginx/html/index.html

# Give the ingress controller a moment to pick up the restored Ingress/HTTPRoute.
if [ "${EXPOSED}" = "yes" ]; then
  echo "    Waiting up to 30s for ingress route to be served again…"
  for _ in $(seq 1 15); do
    STATUS=$(curl -sS --max-time 3 -o /dev/null -w "%{http_code}" "${NGINX_URL}" || echo "000")
    [ "${STATUS}" = "200" ] && break
    sleep 2
  done
  curl_url "Page via ingress (after restore — should be back):"
fi

echo ""
echo "Demo complete. The contents printed in step 5 must match step 1."
if [ "${EXPOSED}" = "yes" ]; then
  echo "Open ${NGINX_URL} in a browser to see the restored page."
fi
