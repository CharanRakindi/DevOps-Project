# Istio Service Mesh — Microservices on Kubernetes

A complete, production-ready implementation of an **Istio service mesh** on a self-managed Kubernetes cluster, featuring two Go microservices with automated CI/CD, canary deployments, mutual TLS, circuit breaking, fault injection, and a real-time web dashboard for mesh visualization.

> **POC #35 — Advanced DevOps Implementation**

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [Option 1: Jenkins CI/CD (Recommended)](#option-1-jenkins-cicd-recommended)
  - [Option 2: Manual Deployment](#option-2-manual-deployment)
- [Microservices](#microservices)
  - [Service A — Frontend Gateway](#service-a--frontend-gateway)
  - [Service B — Backend API](#service-b--backend-api)
- [Istio Configuration](#istio-configuration)
  - [Traffic Management](#traffic-management)
  - [Security (mTLS)](#security-mtls)
  - [Resilience](#resilience)
  - [Observability](#observability)
- [Dashboard UI](#dashboard-ui)
- [Testing](#testing)
- [CI/CD Pipeline](#cicd-pipeline)
- [Kubernetes Manifests Reference](#kubernetes-manifests-reference)
- [Troubleshooting](#troubleshooting)

---

## Overview

This project deploys two Go microservices (`service-a` and `service-b`) onto a self-managed Kubernetes cluster (kubeadm on AWS EC2) with Istio as the service mesh layer. The application itself is intentionally minimal — the real deliverable is the **infrastructure around it**: traffic splitting, encrypted service-to-service communication, automated resilience, and a fully automated Jenkins pipeline.

A custom-built, dark-themed web dashboard provides real-time visualization of the mesh topology, service health, and live API responses.

### What This Project Demonstrates

| Capability | Implementation |
|---|---|
| Canary Deployments | 80% traffic → v1, 20% → v2, configurable via YAML |
| Zero-Trust Security | Strict mutual TLS on all pod-to-pod traffic |
| Circuit Breaking | Automatic ejection of unhealthy pods |
| Chaos Engineering | Inject 5s delays and HTTP 503s without code changes |
| Automated CI/CD | Jenkins pipeline: build → push → deploy → test |
| Observability | Kiali service graph + custom real-time dashboard |

---

## Architecture

```
                         ┌─────────────────────────────────┐
                         │        Istio Ingress Gateway     │
                         │         (Port 80 → NodePort)     │
                         └────────────┬────────────────────┘
                                      │
                    ┌─────────────────┴──────────────────┐
                    │         VirtualService Routing       │
                    │    ┌──────────┐    ┌──────────┐     │
                    │    │  80% v1  │    │  20% v2  │     │
                    │    └────┬─────┘    └────┬─────┘     │
                    └─────────┼───────────────┼───────────┘
                              │               │
                   ┌──────────▼──┐   ┌────────▼────┐
                   │ Service A   │   │ Service A    │
                   │ v1 (2 pods) │   │ v2 (1 pod)   │
                   │ + Envoy     │   │ + Envoy      │
                   └──────┬──────┘   └──────┬───────┘
                          │                 │
                          └────────┬────────┘
                                   │ mTLS encrypted
                          ┌────────▼────────┐
                          │   Service B      │
                          │  v1 (2 pods)     │
                          │  + Envoy sidecar │
                          └─────────────────┘
```

Every pod runs **2/2 containers**: the application container and an automatically injected **Envoy sidecar proxy**. All inter-service communication passes through the sidecar, enabling traffic control, encryption, and observability without any application code changes.

---

## Features

### Traffic Management
- **Weighted Canary Routing** — 80/20 traffic split between v1 and v2
- **Path-Based Routing** — `/v2/*` routes deterministically to v2
- **Automatic Retries** — 3 retries on gateway errors and transient failures
- **Request Timeouts** — 10-second timeout per route

### Security
- **Strict mTLS** — All pod-to-pod traffic encrypted with Istio-managed X.509 certificates
- **PeerAuthentication** — Plain-text connections are rejected namespace-wide
- **Non-root containers** — All services run as unprivileged users

### Resilience
- **Circuit Breaker** — Ejects pods after 5 consecutive 5xx errors for 30 seconds
- **Connection Pooling** — Limits concurrent TCP/HTTP connections to prevent overload
- **Fault Injection** — Inject 5s delays (50%) and HTTP 503 aborts (10%) on demand

### Observability
- **Kiali** — Live service graph with traffic flow, error rates, and mTLS status
- **Custom Dashboard** — Dark-themed web UI with real-time health polling and architecture visualization

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Go 1.21 (standard library only, zero dependencies) |
| Container Runtime | containerd (via kubeadm) |
| Container Build | Docker (multi-stage, Alpine 3.18 runtime) |
| Orchestration | Kubernetes (self-managed, kubeadm on AWS EC2) |
| Service Mesh | Istio (demo profile) |
| CI/CD | Jenkins (Declarative Pipeline) |
| Registry | Docker Hub |
| Observability | Kiali + Prometheus + Jaeger |
| Frontend | Vanilla HTML/CSS/JS (embedded in Go binary) |

---

## Project Structure

```
DevOps-Project/
│
├── Jenkinsfile                      # Declarative CI/CD pipeline
├── README.md                        # This file
├── .gitignore                       # Excludes kubeconfig and sensitive files
│
├── k8s/                             # Kubernetes & Istio Manifests
│   ├── 01-namespace.yaml            #   Namespace with Istio sidecar injection
│   ├── 02-deployments.yaml          #   Deployments (A v1, A v2, B v1) + Services
│   ├── 03-gateway.yaml              #   Istio Ingress Gateway (port 80)
│   ├── 04-virtualservice.yaml       #   Traffic rules (canary + path-based)
│   ├── 05-destinationrule.yaml      #   Subsets, mTLS, circuit breaker
│   ├── 06-fault-injection.yaml      #   Chaos engineering (delay + abort)
│   ├── 07-peer-authentication.yaml  #   Strict mTLS enforcement
│   └── 08-kiali.yaml                #   Kiali observability dashboard
│
├── scripts/                         # Automation Scripts
│   ├── build-and-push.sh            #   Manual Docker build and push
│   ├── deploy.sh                    #   K8s deployment with image substitution
│   └── test.sh                      #   Automated mesh verification tests
│
└── services/                        # Go Microservices
    ├── service-a/                   #   Frontend Gateway Service
    │   ├── main.go                  #     HTTP server (standard library)
    │   ├── Dockerfile               #     Multi-stage build
    │   ├── go.mod                   #     Module definition (zero deps)
    │   ├── static/
    │   │   └── index.html           #     Dashboard UI
    │   └── .dockerignore
    │
    └── service-b/                   #   Internal Backend Service
        ├── main.go                  #     HTTP server
        ├── Dockerfile               #     Multi-stage build
        ├── go.mod / go.sum
        ├── templates/
        │   └── dashboard.html       #     Service-B status page
        └── .dockerignore
```

---

## Prerequisites

| Requirement | Version | Purpose |
|---|---|---|
| Kubernetes cluster | 1.25+ | kubeadm on AWS EC2 (1 master + 2 workers) |
| Istio | 1.20+ | `istioctl install --set profile=demo -y` |
| Docker | 24+ | Building container images |
| kubectl | 1.25+ | Cluster management |
| Jenkins | 2.400+ | CI/CD pipeline execution |
| Docker Hub account | — | Container image registry |

### Jenkins Credentials Required

| Credential ID | Type | Description |
|---|---|---|
| `dockerhub-creds` | Username/Password | Docker Hub login credentials |
| `kubeconfig-mesh-demo` | Secret File | Kubernetes kubeconfig for the cluster |

---

## Quick Start

### Option 1: Jenkins CI/CD (Recommended)

1. **Create a Jenkins Pipeline job** pointing to this repository:
   ```
   Repository URL: https://github.com/CharanRakindi/DevOps-Project.git
   Branch: main
   Script Path: Jenkinsfile
   ```

2. **Configure credentials** in Jenkins (Manage Jenkins → Credentials):
   - `dockerhub-creds` — Your Docker Hub username and password/token
   - `kubeconfig-mesh-demo` — Your cluster's kubeconfig file

3. **Run the pipeline** — it will automatically:
   - Build 3 Docker images (service-a:v1, service-a:v2, service-b:v1)
   - Push them to Docker Hub
   - Deploy all Kubernetes manifests
   - Restart pods to pull the latest images
   - Run automated mesh verification tests

4. **Access the dashboard**:
   ```bash
   # Get the NodePort
   kubectl get svc istio-ingressgateway -n istio-system
   # Open in browser
   http://<NODE_EXTERNAL_IP>:<HTTP_NODEPORT>/
   ```

### Option 2: Manual Deployment

```bash
# 1. Build and push Docker images
chmod +x scripts/build-and-push.sh
./scripts/build-and-push.sh <YOUR_DOCKERHUB_USERNAME>

# 2. Deploy to Kubernetes
chmod +x scripts/deploy.sh
./scripts/deploy.sh <YOUR_DOCKERHUB_USERNAME>

# 3. Run tests
chmod +x scripts/test.sh
./scripts/test.sh
```

---

## Microservices

### Service A — Frontend Gateway

The primary user-facing service. Serves the dashboard UI and acts as an API gateway.

| Endpoint | Method | Response |
|---|---|---|
| `/` | GET | Dashboard HTML UI |
| `/api` | GET | `{"service":"service-a", "version":"v1", "message":"Hello from Service A", "timestamp":"..."}` |
| `/health` | GET | `{"status":"healthy", "service":"service-a", "version":"v1"}` |
| `/version` | GET | `{"service":"service-a", "version":"v1"}` |
| `/call-b` | GET | Proxied JSON response from Service B (via K8s DNS) |

**Implementation details:**
- Written in Go using only the standard library (`net/http`, `encoding/json`)
- Zero external dependencies — no frameworks
- Uses `http.FileServer` to serve `static/index.html` at the root path
- `http.ServeMux` matches API routes (`/api`, `/health`, etc.) before the static fallback (`/`)
- Reuses a single `http.Client` for `/call-b` to enable connection pooling
- Runs on port 8080 inside the container

**Versions deployed:**
- `v1` — Primary (2 replicas, receives 80% of traffic)
- `v2` — Canary (1 replica, receives 20% of traffic)

### Service B — Backend API

Internal backend service consumed by Service A via Kubernetes cluster DNS.

| Endpoint | Method | Response |
|---|---|---|
| `/` | GET | Service B status page (HTML) |
| `/api` | GET | `{"service":"service-b", "version":"v1", "message":"Hello from Service B"}` |
| `/health` | GET | `{"status":"healthy", "service":"service-b", "version":"v1"}` |

**Implementation details:**
- Built with Go and the Gin framework
- Accessible only inside the mesh (not exposed via Ingress Gateway)
- Called by Service A at `http://service-b.mesh-demo.svc.cluster.local/api`

---

## Istio Configuration

### Traffic Management

**VirtualService** (`04-virtualservice.yaml`):

```yaml
# Rule 1: Path-based routing — /v2/* always goes to v2
- match:
  - uri:
      prefix: "/v2"
  rewrite:
    uri: "/"
  route:
  - destination:
      host: service-a
      subset: v2

# Rule 2: Default canary split
- route:
  - destination:
      host: service-a
      subset: v1
    weight: 80
  - destination:
      host: service-a
      subset: v2
    weight: 20
```

**DestinationRule** (`05-destinationrule.yaml`):

```yaml
subsets:
- name: v1
  labels:
    version: v1
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
- name: v2
  labels:
    version: v2
  trafficPolicy:
    loadBalancer:
      simple: LEAST_CONN
```

### Security (mTLS)

**PeerAuthentication** (`07-peer-authentication.yaml`):

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: mesh-demo
spec:
  mtls:
    mode: STRICT    # Rejects all plain-text connections
```

All traffic between services is encrypted using Istio-managed X.509 certificates. The `ISTIO_MUTUAL` TLS mode in the DestinationRule ensures both sides present valid certificates.

### Resilience

**Circuit Breaker** (in `05-destinationrule.yaml`):

```yaml
outlierDetection:
  consecutive5xxErrors: 5     # Eject after 5 consecutive 5xx
  interval: 10s               # Scan every 10 seconds
  baseEjectionTime: 30s       # Ejected for at least 30 seconds
  maxEjectionPercent: 50      # Never eject more than 50% of pods

connectionPool:
  tcp:
    maxConnections: 100
  http:
    http1MaxPendingRequests: 100
    http2MaxRequests: 1000
```

**Fault Injection** (`06-fault-injection.yaml`):

```bash
# Apply fault injection (50% delays, 10% HTTP 503s)
kubectl apply -f k8s/06-fault-injection.yaml

# Remove fault injection
kubectl delete -f k8s/06-fault-injection.yaml
```

This overrides the Service B VirtualService to inject:
- **5-second delays** on 50% of requests (simulates slow downstream)
- **HTTP 503 aborts** on 10% of requests (simulates service crash)

### Observability

**Kiali** (`08-kiali.yaml`):

```bash
# Access Kiali dashboard
kubectl port-forward svc/kiali 20001:20001 -n istio-system
# Open: http://localhost:20001
```

Kiali provides a live service graph showing:
- Real-time traffic flow between services
- Request success/error rates
- mTLS lock icons on encrypted edges
- Response time metrics

---

## Dashboard UI

The custom-built dashboard is served at the root path (`/`) of Service A and provides:

| Section | Description |
|---|---|
| **Navigation Bar** | Live status indicators for Kubernetes, Istio, and mTLS connectivity |
| **Service Cards** | Health status, replica count, traffic weight, and port for each service |
| **Architecture Flow** | Animated visualization of traffic flow from Ingress → Service A → Service B |
| **Mesh Configuration** | mTLS mode, traffic split ratio, circuit breaker status, total pod count |
| **Istio Capabilities** | Cards explaining Traffic Management, mTLS, Fault Injection, Circuit Breaking |
| **Live Responses** | Tabbed panel polling `/api`, `/health`, `/version`, and `/call-b` in real time |

**Design:** Dark theme, glassmorphism, Inter + JetBrains Mono fonts, purple/cyan gradient accents, smooth CSS animations.

---

## Testing

The automated test suite (`scripts/test.sh`) validates 5 mesh capabilities:

| Test | What It Verifies | Pass Criteria |
|---|---|---|
| 1. Weighted Routing | 100 requests → check v1/v2 distribution | ~80 v1, ~20 v2 |
| 2. Path-Based Routing | 10 requests to `/v2/` | All 10 return v2 |
| 3. Internal Call | 5 requests to `/call-b` | ≥4 return HTTP 200 |
| 4. mTLS Status | `istioctl authn tls-check` | All connections show mTLS |
| 5. Fault Injection | Apply faults, send 20 requests, verify delays/aborts, cleanup | ~10 delayed, ~2 aborted |

**Circuit breaker test** (manual, using Fortio):

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/httpbin/sample-client/fortio-deploy.yaml -n mesh-demo

FORTIO_POD=$(kubectl get pod -l app=fortio -n mesh-demo -o name | head -1)

kubectl exec $FORTIO_POD -n mesh-demo -c fortio -- \
  fortio load -c 5 -qps 0 -n 200 http://service-a/api
```

---

## CI/CD Pipeline

The Jenkins pipeline (`Jenkinsfile`) runs 4 stages:

```
┌───────────┐    ┌───────────────────┐    ┌─────────────────┐    ┌──────────────┐
│ Preflight │ →  │ Build & Push      │ →  │ Deploy to K8s   │ →  │ Mesh Tests   │
│           │    │ Images            │    │                 │    │              │
│ • docker  │    │ • service-a:v1    │    │ • Apply YAMLs   │    │ • Canary     │
│ • kubectl │    │ • service-a:v2    │    │ • Rollout       │    │ • Path-based │
│ • scripts │    │ • service-b:v1    │    │   restart       │    │ • mTLS       │
│           │    │ • Push to Hub     │    │ • Wait for      │    │ • Faults     │
│           │    │                   │    │   readiness     │    │              │
└───────────┘    └───────────────────┘    └─────────────────┘    └──────────────┘
```

**Pipeline parameters:**
- `DEPLOY_TO_K8S` (default: true) — Skip deployment if you only want to build images
- `RUN_TESTS` (default: true) — Skip tests for faster iteration

---

## Kubernetes Manifests Reference

| File | Resource | Purpose |
|---|---|---|
| `01-namespace.yaml` | Namespace | `mesh-demo` with `istio-injection: enabled` |
| `02-deployments.yaml` | Deployment × 3, Service × 2 | Pods for A-v1, A-v2, B-v1 + ClusterIP services |
| `03-gateway.yaml` | Gateway | Istio Ingress Gateway accepting HTTP on port 80 |
| `04-virtualservice.yaml` | VirtualService × 2 | Canary routing (A) + default routing (B) |
| `05-destinationrule.yaml` | DestinationRule × 2 | Subsets, mTLS, circuit breaker, connection pools |
| `06-fault-injection.yaml` | VirtualService | Overrides B routing with delay + abort faults |
| `07-peer-authentication.yaml` | PeerAuthentication | Enforces STRICT mTLS namespace-wide |
| `08-kiali.yaml` | Kiali CR | Configures Kiali with Prometheus, Jaeger, Grafana |

---

## Troubleshooting

### Pods stuck at 1/2 READY
Istio sidecar injection may not be working. Verify the namespace label:
```bash
kubectl get namespace mesh-demo --show-labels
# Should include: istio-injection=enabled
```

### Dashboard shows "Unreachable"
You are accessing the HTML file directly (`file:///...`). The dashboard only works when served through the Go backend inside the cluster. Access via `http://<NODE_IP>:<NODEPORT>/`.

### `/api` returns 404
The pods may be running a stale image. Force a restart:
```bash
kubectl rollout restart deployment/service-a-v1 deployment/service-a-v2 -n mesh-demo
```

### Test script shows HTTP 000
The `test.sh` script cannot determine the node IP. Run manually:
```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODEPORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
curl http://$NODE_IP:$NODEPORT/api
```

### Jenkins: "Waiting for next available executor"
Set executor count on the built-in node:
**Manage Jenkins → Nodes → Built-In Node → Configure → Number of executors → 2**

### Jenkins: "permission denied" on Docker
Add the Jenkins user to the Docker group:
```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

---

## License

This project is part of an academic/professional DevOps portfolio demonstration.

---

**Built by [Charan Rakindi](https://github.com/CharanRakindi)**
