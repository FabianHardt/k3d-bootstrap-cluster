# Keycloak

This demo installs the official Keycloak Operator and configures a test installation via CRD.

## Precondition

Cluster has to be deployed with the *NGINX Ingress Controller* and the *Vault example*.

### DNS preparation

You can test Kong Ingress by adding the following entry to your */etc/hosts* file:

```bash
# Append to /etc/hosts
[...]

127.0.0.1		keycloak.example.com
127.0.0.1		apps.example.com
```
### Installation

You can start the installation of Keycloak with the included shell script:

```bash
cd examples/keycloak
bash setup.sh
```
### Show Kong Manager

If your local DNS settings (/etc/hosts) are set correctly, you can open the Keycloak Admin interface in your browser: https://keycloak.example.com:<_PORT_>

The matching *Port* you can find with the following command:
```bash
docker ps --format '{{json .}}' | jq -r '.Ports | split(",") | map(select(contains("30001"))) | .[]'
# Answer
# 0.0.0.0:43809->30001/tcp
```
The right port is **43809** in this example. You can define this port once while cluster creation.

The **default login credentials** are printed at the end of the script execution.


## Configuration

Please add a new client to keycloak with following parameter:

`Client ID`: test-client
`Valid redirect URIs`: https://apps.example.com:8081 , http://localhost:4200
`Web origins`: '+'