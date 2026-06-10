#!/bin/bash
set -o errexit

source ../../helpers.sh

# ---------------------------------------------------------------------------
# Ingress-Modus ermitteln.
# Explizite Flags haben Vorrang; sonst wird der Cluster automatisch erkannt.
#   HAPROXY_FLAG=Yes  → HAProxy IngressClass + Ingress-Ressourcen
#   KONG_FLAG=Yes     → Kong GatewayClass + Gateway API HTTPRoute-Ressourcen
# ---------------------------------------------------------------------------
if [ "${HAPROXY_FLAG}" == "Yes" ]; then
  INGRESS_MODE="haproxy"
elif [ "${KONG_FLAG}" == "Yes" ]; then
  INGRESS_MODE="kong"
elif kubectl get ingressclass haproxy &>/dev/null 2>&1; then
  echo "Auto-detected HAProxy ingress controller"
  INGRESS_MODE="haproxy"
elif kubectl get namespace kong &>/dev/null 2>&1 || kubectl get gatewayclass kong &>/dev/null 2>&1; then
  echo "Auto-detected Kong Gateway"
  INGRESS_MODE="kong"
else
  echo "Fehler: Kein unterstützter Ingress-Modus erkannt."
  echo "Bitte HAProxy oder Kong installieren oder HAPROXY_FLAG/KONG_FLAG explizit setzen."
  exit 1
fi

echo ""
echo "=========================================================="
echo "   Platform Engineering Demo mit Crossplane"
echo "=========================================================="
echo ""
echo "Konzept:"
echo "  Platform-Team  → definiert XRD + Composition (das API-Angebot)"
echo "  Entwickler     → legt einen AppEnvironment-Claim an (Self-Service)"
echo "  Crossplane     → kümmert sich um alles andere automatisch"
echo ""

# ===========================================================================
# [Platform Team] Schritt 1: Crossplane installieren
# ===========================================================================
echo "----------------------------------------------------------"
echo "[Platform Team] Schritt 1: Crossplane installieren"
echo "----------------------------------------------------------"

helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update crossplane-stable

helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace \
  --version "1.17.4" \
  --wait

kubectl wait deployment crossplane \
  -n crossplane-system \
  --for=condition=Available=true \
  --timeout=120s

kubectl wait deployment crossplane-rbac-manager \
  -n crossplane-system \
  --for=condition=Available=true \
  --timeout=120s

echo "✓ Crossplane bereit"
echo ""

# ===========================================================================
# Vorbereitungen: httpbin im Namespace demo entfernen
# ===========================================================================
# Das bestehende httpbin-Deployment wird entfernt, damit beim Test eindeutig
# klar ist, dass nur die von Crossplane verwaltete App erreichbar ist.
echo "----------------------------------------------------------"
echo "Vorbereitung: httpbin im Namespace demo entfernen"
echo "----------------------------------------------------------"
kubectl delete deployment httpbin -n demo --ignore-not-found
kubectl delete service httpbin -n demo --ignore-not-found
kubectl delete ingress httpbin -n demo --ignore-not-found
# Ohne Gateway-API-CRDs existiert der Ressourcen-Typ "httproute" nicht und
# selbst --ignore-not-found schlägt fehl, daher zuerst auf die CRD prüfen.
if kubectl get crd httproutes.gateway.networking.k8s.io &>/dev/null; then
  kubectl delete httproute httpbin -n demo --ignore-not-found
fi
echo "✓ Namespace demo bereinigt"
echo ""

# ===========================================================================
# [Platform Team] Schritt 2: Kubernetes-Provider installieren
# ===========================================================================
echo "----------------------------------------------------------"
echo "[Platform Team] Schritt 2: Kubernetes-Provider einrichten"
echo "----------------------------------------------------------"
echo "Der Provider ermöglicht Crossplane, Kubernetes-Ressourcen zu verwalten."
echo ""

kubectl apply -f platform/01-provider.yaml

echo "Warte darauf, dass der Kubernetes-Provider gesund wird..."
# Healthy=true bedeutet: Provider-Paket heruntergeladen, alle CRDs (inkl.
# providerconfigs.kubernetes.crossplane.io) registered und Controller läuft.
kubectl wait provider/provider-kubernetes \
  --for=condition=Healthy=true \
  --timeout=300s

kubectl apply -f platform/02-providerconfig.yaml

echo "✓ Kubernetes-Provider bereit"
echo ""

# ===========================================================================
# [Platform Team] Schritt 3: XRD und Composition anlegen
# ===========================================================================
echo "----------------------------------------------------------"
echo "[Platform Team] Schritt 3: XRD + Composition anlegen"
echo "----------------------------------------------------------"
echo "Die XRD definiert das Schema (was Entwickler konfigurieren können)."
echo "Die Composition definiert die Implementierung (was Crossplane erstellt)."
echo ""

kubectl apply -f platform/03-xrd.yaml

echo "Warte bis die XRD vollständig registriert ist..."
kubectl wait xrd/xappenvironments.platform.example.com \
  --for=condition=Established=true \
  --timeout=120s

if [ "${INGRESS_MODE}" == "kong" ]; then
  echo "→ Kong-Composition wird verwendet (HTTPRoute)"
  kubectl apply -f platform/04-composition-kong.yaml
else
  echo "→ HAProxy-Composition wird verwendet (Ingress)"
  kubectl apply -f platform/04-composition-haproxy.yaml
fi

echo "✓ Plattform-API bereit — Entwickler können jetzt AppEnvironments bestellen"
echo ""

# ===========================================================================
# [Entwickler Team] Schritt 4: AppEnvironment bestellen
# ===========================================================================
echo "----------------------------------------------------------"
echo "[Entwickler Team] Schritt 4: AppEnvironment bestellen"
echo "----------------------------------------------------------"
echo "Der Entwickler legt einen Claim an — das ist alles, was er tun muss."
echo ""

kubectl apply -f developer/claim.yaml

echo "Warte auf Reconciliation..."
sleep 10

echo "Warte bis AppEnvironment 'meine-app' bereit ist (max. 3 Minuten)..."
kubectl wait appenvironment/meine-app \
  -n default \
  --for=condition=Ready=true \
  --timeout=180s || {
  echo ""
  echo "Hinweis: Der Claim ist noch nicht Ready — das kann bei langsamen Images normal sein."
  echo "Status prüfen:"
  echo "  kubectl describe appenvironment meine-app -n default"
  echo "  kubectl get objects.kubernetes.crossplane.io"
  echo ""
}

# ===========================================================================
# Zusammenfassung
# ===========================================================================
echo ""
echo "=========================================================="
echo "   Crossplane Demo bereit!"
echo "=========================================================="
echo ""
echo "--- Platform-Sicht (was das Platform-Team sieht) ---"
echo "  kubectl get xrd"
echo "  kubectl get composition"
echo "  kubectl get xappenvironment"
echo "  kubectl get objects.kubernetes.crossplane.io"
echo ""
echo "--- Entwickler-Sicht (was der Entwickler sieht) ---"
echo "  kubectl get appenvironment -n default"
echo "  kubectl get all -n app-meine-app"
echo ""

if [ "${INGRESS_MODE}" == "haproxy" ] || [ "${INGRESS_MODE}" == "kong" ]; then
  echo "--- App-Zugriff ---"
  echo "  http://meine-app.127-0-0-1.nip.io:8080"
  echo ""
else
  echo "--- App-Zugriff (kein Ingress) ---"
  echo "  kubectl port-forward -n app-meine-app svc/app-meine-app 8080:80"
  echo "  → http://localhost:8080"
  echo ""
fi

echo "--- Weitere Apps anlegen ---"
echo "  developer/claim.yaml kopieren, appName ändern, kubectl apply ausführen"
echo ""
echo "--- Aufräumen ---"
echo "  kubectl delete appenvironment meine-app -n default"
echo "  (entfernt Namespace, Deployment, Service und Ingress automatisch)"
echo "=========================================================="
