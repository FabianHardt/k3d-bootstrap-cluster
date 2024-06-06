<script setup>
import { useData } from 'vitepress'

const { theme } = useData()
</script>

# DNS resolution issues

This k3d cluster deployment uses **nip.io** DNS resolution for demo purposes. DNS names for registry and demo Ingresses are resolved to local IP. Example: registry.127-0-0-1.nip.io is resolved to static IP 127.0.0.1.

**Caution:** In some cases your network-router doesn't allow to resolve IPs of your own, or private IP address range. As a workaround you can change the ENV variable `DEMO_DOMAIN` in *helpers.sh*. This will automatically add the registry entry in your local /etc/hosts file. But it doesn't add any sample Ingress hostnames to your local /etc/hosts, you have to do this manually.

