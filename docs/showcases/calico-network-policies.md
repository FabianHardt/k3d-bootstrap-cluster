# Calico NetworkPolicy example

This is an example of Calicos NetworkPolicies. It shows the typical use case of wanting to separate namespaces from each other.

This means that pods from namespace A cannot call pods from namespace B. However, communication within a namespace is not restricted.

To use the full example, you should also apply the Calico API server:

```bash
# https://docs.tigera.io/calico/latest/operations/install-apiserver
# Deploy API server
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/apiserver.yaml

# Create certificates
openssl req -x509 -nodes -newkey rsa:4096 -keyout apiserver.key -out apiserver.crt -days 365 -subj "/" -addext "subjectAltName = DNS:calico-api.calico-apiserver.svc"

# Create secret for API server and deploy to Kubernetes
kubectl create secret -n calico-apiserver generic calico-apiserver-certs --from-file=apiserver.key --from-file=apiserver.crt
kubectl patch apiservice v3.projectcalico.org -p \
    "{\"spec\": {\"caBundle\": \"$(kubectl get secret -n calico-apiserver calico-apiserver-certs -o go-template='{{ index .data "apiserver.crt" }}')\"}}"
```

**Example:**

```bash
# Change directory to Calico folder
cd examples/calico/

# Create two new test namespaces
kubectl create namespace namespace1
kubectl create namespace namespace2

# Start a new test Pod in namespace1 (Terminal 1)
kubectl -n namespace1 run tmp-shell --rm -i --tty --image nicolaka/netshoot

# Start a new test Pod in namespace2 (Terminal 2)
kubectl -n namespace2 run tmp-shell --rm -i --tty --image nicolaka/netshoot

# Test reaching the httpbin demo service from both test Pods (Terminal 1 or 2)
curl -v httpbin.demo
# this should give an HTML answer

# Apply a GlobalNetworkPolicy - this will lockdown all other communication (Terminal 3)
kubectl apply -f allow-dns-global.yml # just allow DNS port in the cluster

# Test reaching the httpbin demo service from both test Pods again (Terminal 1 or 2)
curl -v httpbin.demo
# this should NOT give an answer - you should see an answer like this
#* Host httpbin.demo:80 was resolved.
#* IPv6: (none)
#* IPv4: 10.43.121.122 --> the DNS lookup is allowed by policy
#*   Trying 10.43.121.122:80...
```

These are the very first steps with Calico NetworkPolices, congratulations :-)

But now we have a problem, the traffic in our own namespaces is also disallowed. For demo purposes we use the "normal" Kubernetes NetworkPolicies here, to demonstrate that you can mix them with the Calico ones.

Here's an example:

```bash
# Start another small webserver
kubectl -n namespace1 run nginx --image nginx

# Get a list of our running Pods in namespace1
kubectl -n namespace1 get po -o wide
# Output should look similar to this:
NAME        READY   STATUS    RESTARTS   AGE     IP               NODE              NOMINATED NODE   READINESS GATES
nginx       1/1     Running   0          6m15s   192.168.171.78   k3d-XXX-agent-0   <none>           <none>
tmp-shell   1/1     Running   0          11m     192.168.171.76   k3d-XXX-agent-0   <none>           <none>

# Now switch to Terminal 1 and try to reach our new NGINX Pod
curl -v 192.168.171.78 # use IP from NGINX Pod
# It's not allowed anymore!
# OUTPUT: curl: (28) Failed to connect to 192.168.171.78 port 80 after 133190 ms: Couldn't connect to server

# Add a wildcard policy for namespace1
kubectl apply -f allow-all-own-ns-1.yml
# Try the curl from above again - should work now!

# Optional - also apply policy for namespace2
kubectl apply -f allow-all-own-ns-2.yml
```

We have now reached the point where namespaces exist cleanly isolated from one another.
If traffic between them is to be enabled, explicit policies must be created:

```bash
# Apply ingress rule to allow traffic on port 80 to demo namespace
kubectl apply -f allow-ingress-port-80-demo-ns.yml

# Allow full egress traffic from namespace1
kubectl apply -f allow-all-egress-namespace1.yml

# Check the result (Terminal 1)
curl -v httpbin.demo
# Result - should show a HTML page
```

Have fun trying out the Calico Policies!

**Optional - allow traffic to httpbin app from outside:**

```bash
# Allow ingress and egress on port 80 in ingress-nginx namespace
kubectl apply -f allow-ingress-egress-nginx.yml

# now it should be possible again to visit localhost:8080 :-)
```

