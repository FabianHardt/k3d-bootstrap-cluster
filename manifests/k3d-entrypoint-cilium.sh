#!/bin/sh
# Mounted into every k3d node as /bin/k3d-entrypoint-cilium.sh; the k3d
# entrypoint runs all /bin/k3d-entrypoint-*.sh scripts before starting k3s.
# Cilium needs bpffs and a dedicated cgroup2 mount inside the node container,
# which the k3s image cannot set up itself (see k3d-io/k3d#479).
set -e

if ! grep -qs ' /sys/fs/bpf ' /proc/mounts; then
  mount bpffs -t bpf /sys/fs/bpf
fi
mount --make-shared /sys/fs/bpf

mkdir -p /run/cilium/cgroupv2
if ! grep -qs ' /run/cilium/cgroupv2 ' /proc/mounts; then
  mount -t cgroup2 none /run/cilium/cgroupv2
fi
mount --make-shared /run/cilium/cgroupv2
