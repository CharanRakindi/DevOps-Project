# Service Mesh with Istio on Self-Managed Kubernetes

**POC #35 · ADVANCED · Go + Gin · kubeadm · Istio · Kiali**

---

## What This Project Does

Two Go microservices (Service A and Service B) are deployed on a self-managed
Kubernetes cluster provisioned with kubeadm. Istio automatically injects an
Envoy sidecar proxy into every pod. All inter-service traffic flows through
these sidecars, giving you:

- **Traffic Management** — weighted canary routing (80/20) + path-based routing
- **Circuit Breaker** — automatic ejection of unhealthy pod instances
- **Fault Injection** — inject delays and HTTP errors without touching code
- **Strict mTLS** — all service-to-service traffic encrypted and authenticated
- **Observability** — live service graph and health in Kiali dashboard

---

## Repository Structure

```
project-istio-mesh/
├── services/
│   ├── service-a/
│   │   ├── main.go                  Go Gin app — handles external traffic, calls service-b
│   │   ├── go.mod
│   │   └── Dockerfile               Multi-stage build
│   └── service-b/
│       ├── main.go                  Go Gin app — backend, internal traffic only
│       ├── go.mod
│       └── Dockerfile
├── k8s/
│   ├── 01-namespace.yaml            Namespace with istio-injection=enabled
│   ├── 02-deployments.yaml          Deployments (service-a v1+v2, service-b v1) + Services
│   ├── 03-gateway.yaml              Istio Ingress Gateway
│   ├── 04-virtualservice.yaml       Traffic routing rules (canary + path-based)
│   ├── 05-destinationrule.yaml      Subsets + circuit breaker + mTLS policy
│   ├── 06-fault-injection.yaml      Fault injection (apply/remove as needed)
│   ├── 07-peer-authentication.yaml  Strict mTLS enforcement
│   └── 08-kiali.yaml                Kiali custom resource (optional if using demo profile)
├── scripts/
│   ├── build-and-push.sh            Build Docker images and push to Docker Hub
│   ├── deploy.sh                    Apply all manifests to the cluster
│   └── test.sh                      Run all verification tests
└── README.md
```

---

## Prerequisites

### Infrastructure
- 2 x Ubuntu 22.04 EC2 instances (t3.medium — 2 vCPU, 4 GB RAM minimum)
- Both in the same VPC and security group
- Ports open: `6443`, `10250`, `80`, `443`, `15020-15021`, `20001`, `30000-32767`

### Tools installed locally / on control-plane node
| Tool | Install |
|------|---------|
| Go 1.21+ | https://go.dev/dl/ |
| Docker Engine | https://docs.docker.com/engine/install/ubuntu/ |
| kubectl | https://kubernetes.io/docs/tasks/tools/ |
| kubeadm + kubelet | via apt (see Step 1) |
| istioctl | https://istio.io/downloadIstio |
| Helm v3 | https://helm.sh/docs/intro/install/ |

---

## Step-by-Step Setup

### Step 1 — Provision the Kubernetes Cluster (kubeadm)

Run on **ALL nodes**:

```bash
# Disable swap permanently
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Required sysctl settings
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# Install containerd (from Docker official repo)
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y containerd.io
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd

# Install kubeadm, kubelet, kubectl
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
```

Run on **control plane only**:

```bash
# Initialise the cluster
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=<CONTROL_PLANE_PRIVATE_IP>

# Set up kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Flannel CNI
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

Run on **worker node**:

```bash
# Paste the join command printed by kubeadm init
sudo kubeadm join <CONTROL_PLANE_IP>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

Verify on control plane:

```bash
kubectl get nodes
# Both nodes should show STATUS = Ready within ~60 seconds
```

---

### Step 2 — Install Istio

```bash
# Download istioctl
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
echo 'export PATH=$HOME/istio-*/bin:$PATH' >> ~/.bashrc

# Pre-flight check
istioctl x precheck

# Install with demo profile (includes Prometheus, Kiali, Jaeger, Grafana)
istioctl install --set profile=demo -y

# Verify all Istio pods are Running
kubectl get pods -n istio-system
```

---

### Step 3 — Build & Push Docker Images

```bash
chmod +x scripts/build-and-push.sh
./scripts/build-and-push.sh <YOUR_DOCKERHUB_USERNAME>
```

This builds:
- `<user>/service-a:v1` and `<user>/service-a:v2`
- `<user>/service-b:v1`

---

### Step 4 — Deploy to Kubernetes

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh <YOUR_DOCKERHUB_USERNAME>
```

This applies all manifests in order (01 → 07) and waits for rollouts.

**Expected pod status** — all pods should show `2/2 READY` (app + Envoy sidecar):

```
NAME                         READY   STATUS    RESTARTS
service-a-v1-xxxxx           2/2     Running   0
service-a-v1-yyyyy           2/2     Running   0
service-a-v2-xxxxx           2/2     Running   0
service-b-v1-xxxxx           2/2     Running   0
service-b-v1-yyyyy           2/2     Running   0
```

> **If pods show `1/2`** — sidecar was not injected. Check:
> ```bash
> kubectl get namespace mesh-demo --show-labels
> # Must show: istio-injection=enabled
> ```

---

### Step 5 — Open Kiali Dashboard

```bash
# Port-forward Kiali to your local machine
kubectl port-forward svc/kiali 20001:20001 -n istio-system

# Open in browser
http://localhost:20001
```

In Kiali, navigate to **Graph → Namespace: mesh-demo** to see the live service
topology with animated traffic, mTLS lock icons, and health indicators.

---

### Step 6 — Run Tests

```bash
chmod +x scripts/test.sh
./scripts/test.sh
```

Tests run automatically:
1. Weighted routing — 100 requests, counts v1 vs v2 responses
2. Path routing — `/v2/` always hits v2
3. Internal call — service-a → service-b via cluster DNS
4. mTLS check — via `istioctl authn tls-check`
5. Fault injection — applies + tests + removes automatically

---

## Fault Injection (Manual)

Apply:
```bash
kubectl apply -f k8s/06-fault-injection.yaml
```

This makes service-b return:
- 5-second delay for 50% of requests
- HTTP 503 for 10% of requests

Remove when done:
```bash
kubectl delete -f k8s/06-fault-injection.yaml
```

---

## Circuit Breaker Test (Manual)

```bash
# Deploy Fortio load tester
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/httpbin/sample-client/fortio-deploy.yaml -n mesh-demo

# Run load test (5 concurrent, 200 requests)
FORTIO_POD=$(kubectl get pod -l app=fortio -n mesh-demo -o name | head -1)
kubectl exec $FORTIO_POD -n mesh-demo -c fortio -- \
  fortio load -c 5 -qps 0 -n 200 http://service-a/

# Look for Code 503 / Code 500 in output — those are circuit breaker rejections
# In Kiali, the circuit breaker icon appears on service-a edges
```

---

## Access All Dashboards

```bash
# Kiali (service mesh graph)
kubectl port-forward svc/kiali       20001:20001 -n istio-system

# Prometheus (metrics)
kubectl port-forward svc/prometheus  9090:9090   -n istio-system

# Jaeger (distributed tracing)
kubectl port-forward svc/jaeger-query 16686:16686 -n istio-system

# Grafana (metrics dashboards)
kubectl port-forward svc/grafana     3000:3000   -n istio-system
```

---

## Useful Commands

```bash
# Check pod status (must be 2/2)
kubectl get pods -n mesh-demo

# Validate all Istio config
istioctl analyze -n mesh-demo

# Check mTLS status
istioctl authn tls-check -n mesh-demo

# View Envoy sidecar logs for a pod
kubectl logs <pod-name> -c istio-proxy -n mesh-demo

# Inspect Envoy routing config
istioctl proxy-config route <pod-name>.mesh-demo
istioctl proxy-config cluster <pod-name>.mesh-demo

# Describe VirtualService
kubectl describe virtualservice service-a-vs -n mesh-demo

# Describe DestinationRule
kubectl describe destinationrule service-a-dr -n mesh-demo
```

---

## Cleanup

```bash
# Remove all application resources
kubectl delete namespace mesh-demo

# Uninstall Istio completely
istioctl uninstall --purge -y
kubectl delete namespace istio-system

# Tear down the cluster (run on each node)
sudo kubeadm reset -f
sudo rm -rf $HOME/.kube /etc/cni /etc/kubernetes
```

---

## References

- Istio Docs: https://istio.io/latest/docs/
- kubeadm Setup: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/
- Gin Framework: https://gin-gonic.com/docs/
- Kiali Docs: https://kiali.io/docs/
- Flannel CNI: https://github.com/flannel-io/flannel
