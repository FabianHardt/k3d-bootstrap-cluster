#!/bin/bash
set -o errexit

# Connect to the SeaweedFS SFTP server using the CA-signed user certificate
# issued by setup.sh, port-forwarding the in-cluster SFTP port to localhost.
#
# Usage:
#   bash connect.sh            # runs a scripted upload/list/download demo
#   bash connect.sh shell      # opens an interactive sftp prompt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

PRINCIPAL="admin"
KEYS_DIR="${SCRIPT_DIR}/.keys"
LOCAL_PORT="${LOCAL_PORT:-2022}"

KEY="${KEYS_DIR}/id_${PRINCIPAL}"
CERT="${KEYS_DIR}/id_${PRINCIPAL}-cert.pub"

if [ ! -f "${CERT}" ]; then
  echo "No user certificate found at ${CERT}. Run 'bash setup.sh' first." >&2
  exit 1
fi

SSH_OPTS=(
  -P "${LOCAL_PORT}"
  -i "${KEY}"
  -o "CertificateFile=${CERT}"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

# Port-forward the SFTP port; clean it up on exit.
echo "Port-forwarding seaweedfs SFTP to localhost:${LOCAL_PORT}…"
kubectl -n seaweedfs port-forward deployment/seaweedfs-all-in-one "${LOCAL_PORT}:2022" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
  if nc -z localhost "${LOCAL_PORT}" 2>/dev/null; then break; fi
  sleep 0.5
done

if [ "${1:-}" = "shell" ]; then
  exec sftp "${SSH_OPTS[@]}" "${PRINCIPAL}@127.0.0.1"
fi

# Scripted demo: upload a file, list it, download it back.
WORK="$(mktemp -d)"
trap 'kill "${PF_PID}" 2>/dev/null || true; rm -rf "${WORK}"' EXIT
echo "hello from the k3d SeaweedFS SFTP showcase" > "${WORK}/hello.txt"

echo "Uploading and listing over SFTP (certificate auth)…"
sftp "${SSH_OPTS[@]}" "${PRINCIPAL}@127.0.0.1" <<SFTP
put ${WORK}/hello.txt /hello.txt
ls -l /
get /hello.txt ${WORK}/hello-roundtrip.txt
SFTP

echo ""
echo "Round-tripped file contents:"
cat "${WORK}/hello-roundtrip.txt"
echo ""
echo "Interactive session:  bash connect.sh shell"
