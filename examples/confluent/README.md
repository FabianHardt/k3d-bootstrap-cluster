# Confluent for Kubernters (CFK)

### Precondition
**DNS preparation**

You can test Confluent Controlenter by adding the following entry to your */etc/hosts* file:

```bash
# Append to /etc/hosts
[...]

127.0.0.1		confluent.example.com
```

### Installation

You can start the installation of the Confluent Operator and the Confluent Platform with the included shell script:

```bash
cd examples/confluent
bash setup.sh
```

The following components are installed with the *setup.sh*:

- Confluent HELM Chart is used to deploy Confluent for Kubernets - https://docs.confluent.io/operator/current/overview.html
  - Installs Confluent Operator and Platform instance to namespace *confluent*

### Show Confluent Controlcenter Dashboard

If your local DNS settings (/etc/hosts) are set correctly, you can open the Controlcenter in your browser: https://confluent.example.com:8081/
