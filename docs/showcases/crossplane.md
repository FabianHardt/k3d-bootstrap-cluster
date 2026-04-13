# Crossplane — Platform Engineering Demo

## Konzept

Dieses Beispiel demonstriert **Platform Engineering** mit [Crossplane](https://www.crossplane.io): einem Open-Source-Projekt der CNCF, das Kubernetes zur Plattform für Self-Service-Infrastruktur macht.

Die Kernidee: Nicht jeder Entwickler soll Kubernetes im Detail kennen müssen.

```
┌─────────────────────────────────────────────────────────────────┐
│  Platform-Team                       Entwickler-Team            │
│  ─────────────                       ──────────────             │
│  XRD (Schema)        →               AppEnvironment Claim       │
│  Composition (Impl.) →  Crossplane   "Ich möchte eine App"      │
│                                              ↓                  │
│                          erstellt automatisch:                  │
│                            • Namespace (app-meine-app)          │
│                            • Deployment                         │
│                            • Service                            │
│                            • Ingress / HTTPRoute                │
└─────────────────────────────────────────────────────────────────┘
```

**Platform-Team** (Plattform-Experten):
- Definiert das Schema: Was darf ein Entwickler konfigurieren? (`XRD`)
- Definiert die Implementierung: Was wird dahinter erstellt? (`Composition`)

**Entwickler-Team** (App-Entwickler):
- Legt einen `AppEnvironment`-Claim mit wenigen Zeilen YAML an
- Bekommt eine vollständige, laufende Umgebung — ohne Kubernetes-Detailwissen

### Precondition

Cluster muss mit httpbin-Sample und HAProxy oder Kong Ingress-Controller deployed sein.

### Installation

```bash
cd examples/crossplane

# Mit HAProxy Ingress Controller (Standard)
HAPROXY_FLAG=Yes bash setup.sh

# Mit Kong Gateway (Gateway API / HTTPRoute)
KONG_FLAG=Yes bash setup.sh
```

Ohne Flag wird der Ingress-Controller automatisch erkannt.

### Installierte Komponenten

| Komponente | Namespace | Beschreibung |
|---|---|---|
| Crossplane | `crossplane-system` | Core-Controller + RBAC-Manager |
| provider-kubernetes | `crossplane-system` | Kubernetes-Provider für In-Cluster-Ressourcen |
| XRD `xappenvironments` | cluster-scoped | Das API-Schema des Platform-Teams |
| Composition `appenvironment-haproxy` oder `-kong` | cluster-scoped | Die Implementierung |
| AppEnvironment Claim `meine-app` | `default` | Demo-Bestellung des Entwickler-Teams |
| App-Namespace `app-meine-app` | — | Erstellt durch Crossplane |

### Dateistruktur

```
examples/crossplane/
├── setup.sh
├── platform/                          ← Platform-Team schreibt diese Dateien
│   ├── 01-provider.yaml               # Kubernetes-Provider + RBAC
│   ├── 02-providerconfig.yaml         # In-Cluster Auth (InjectedIdentity)
│   ├── 03-xrd.yaml                    # API-Schema: AppEnvironment
│   ├── 04-composition-haproxy.yaml    # Implementierung für HAProxy
│   └── 04-composition-kong.yaml       # Implementierung für Kong Gateway API
└── developer/                         ← Entwickler schreiben nur diese Datei
    └── claim.yaml                     # "Ich möchte eine App-Umgebung"
```

### Schritt-für-Schritt-Erklärung

#### Schritt 1: Crossplane installiert das Fundament

Crossplane wird als Helm-Chart im Namespace `crossplane-system` installiert.
Es registriert neue Kubernetes-Ressourcentypen: `Provider`, `Composition`, `CompositeResourceDefinition` u.a.

#### Schritt 2: Das Platform-Team richtet die Plattform ein

**Provider** (`01-provider.yaml`): Installiert `provider-kubernetes` — dieser Provider kann im Namen von Crossplane Kubernetes-Ressourcen anlegen, ändern und löschen.

**ProviderConfig** (`02-providerconfig.yaml`): Konfiguriert den Provider für In-Cluster-Zugriff (`InjectedIdentity`). Kein externer Kubeconfig, keine Cloud-Credentials.

**XRD** (`03-xrd.yaml`): Das Bestellformular. Definiert, welche Parameter ein Entwickler angeben kann:

```yaml
spec:
  parameters:
    appName: meine-app    # Pflicht
    image: httpbin        # Optional
    replicas: 1           # Optional
```

**Composition** (`04-composition-*.yaml`): Die Implementierung. Beschreibt, welche Kubernetes-Ressourcen für jeden Claim erstellt werden und wie die Parameter darauf abgebildet werden (Patches).

#### Schritt 3: Der Entwickler bestellt eine Umgebung

Der Entwickler legt genau eine Datei an:

```yaml
apiVersion: platform.example.com/v1alpha1
kind: AppEnvironment
metadata:
  name: meine-app
  namespace: default
spec:
  parameters:
    appName: meine-app
```

Crossplane übernimmt den Rest automatisch.

### Test

```bash
# Platform-Sicht
kubectl get xrd
kubectl get composition
kubectl get xappenvironment

# Objekte die Crossplane erstellt hat
kubectl get objects.kubernetes.crossplane.io

# Entwickler-Sicht
kubectl get appenvironment -n default
kubectl get all -n app-meine-app
```

App-Zugriff (HAProxy oder Kong):
```
http://meine-app.127-0-0-1.nip.io:8080
```

### Weitere Apps anlegen

Einfach `developer/claim.yaml` kopieren und `appName` ändern — jede Instanz bekommt einen eigenen isolierten Namespace:

```bash
cp developer/claim.yaml developer/zweite-app.yaml
# appName: zweite-app setzen
kubectl apply -f developer/zweite-app.yaml
# → erreichbar unter http://zweite-app.127-0-0-1.nip.io:8080
```

### Aufräumen

```bash
# Claim löschen → entfernt alle erstellen Ressourcen automatisch
kubectl delete appenvironment meine-app -n default

# Crossplane komplett entfernen
helm uninstall crossplane -n crossplane-system
kubectl delete -f platform/03-xrd.yaml
kubectl delete -f platform/01-provider.yaml
```
