# Confluent for Kubernters (CFK)

### Precondition

**Resources**

*We recommend at least 8 CPUs and 20GB RAM reserved for k3d*

Please note that the entire stack, including Zookeeper, Kafka, Schema Registry, REST Proxy, KSQLDB, Control Center, and so on, requires significant resources.
With 6 CPUs and 12GB of RAM, installation will take approximately 15 minutes (based on a clean install without Kuma, Kong, or Vault).

**DNS preparation**

You can test Confluent ControlCenter by adding the following entry to your */etc/hosts* file:

```bash
# Append to /etc/hosts
[...]

127.0.0.1		confluent.example.com
```

### Installation

Use the provided shell script to begin the installation of 
the Confluent Operator and Confluent Platform:

```bash
cd examples/confluent
bash setup.sh
```

The following components are installed with the *setup.sh*:

- Confluent HELM Chart is used to deploy Confluent for Kubernets - https://docs.confluent.io/operator/current/overview.html
  - Installs Confluent Operator and Platform instance to namespace *confluent*

### Show Confluent Controlcenter Dashboard

If your local DNS settings (/etc/hosts) are set correctly, you can open the Controlcenter in your browser: https://confluent.example.com:8081/
