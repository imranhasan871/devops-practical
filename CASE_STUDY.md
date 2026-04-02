# DevOps Practical — Full Case Study

**Author:** Imran Hasan  
**Date:** April 2026  
**Repository:** https://github.com/imranhasan871/devops-practical  
**Live API:** http://104.236.49.243

---

## Table of Contents

1. [Objective](#1-objective)
2. [System Architecture](#2-system-architecture)
3. [Technology Stack](#3-technology-stack)
4. [Application — Go REST API](#4-application--go-rest-api)
5. [Containerization](#5-containerization)
6. [Reverse Proxy — Nginx](#6-reverse-proxy--nginx)
7. [CI/CD Pipeline](#7-cicd-pipeline)
8. [Infrastructure as Code — Terraform](#8-infrastructure-as-code--terraform)
9. [Zero-Downtime Deployment](#9-zero-downtime-deployment)
10. [Monitoring & Observability](#10-monitoring--observability)
11. [Security & Secrets Management](#11-security--secrets-management)
12. [Kubernetes Manifests (Bonus)](#12-kubernetes-manifests-bonus)
13. [Live Testing URLs](#13-live-testing-urls)
14. [Local Development](#14-local-development)
15. [Cost Breakdown](#15-cost-breakdown)
16. [Challenges & Lessons Learned](#16-challenges--lessons-learned)

---

## 1. Objective

Design, build, and deploy a production-style system that demonstrates:

- Containerization with Docker
- Automated CI/CD with GitHub Actions
- Traffic management via Nginx reverse proxy
- Basic observability with Prometheus and Grafana
- Zero-downtime deployments
- Infrastructure as Code with Terraform on DigitalOcean
- Handling ~100 requests/sec

---

## 2. System Architecture

```
                        Internet
                           │
                           ▼
                  ┌─────────────────┐
                  │  DigitalOcean   │
                  │  Firewall       │
                  │  (ports 22/80)  │
                  └────────┬────────┘
                           │
                  ┌────────▼────────┐
                  │    Droplet      │
                  │  nyc3 / 1vCPU  │
                  │                 │
                  │  ┌───────────┐  │
                  │  │   Nginx   │  │  ← port 80
                  │  │ (proxy)   │  │
                  │  └─────┬─────┘  │
                  │        │        │
                  │  ┌─────▼─────┐  │
                  │  │  Go API   │  │  ← port 8080 (internal)
                  │  │  app      │  │
                  │  └───────────┘  │
                  │                 │
                  │  ┌───────────┐  │
                  │  │Prometheus │  │  ← scrapes /metrics
                  │  └─────┬─────┘  │
                  │        │        │
                  │  ┌─────▼─────┐  │
                  │  │  Grafana  │  │  ← dashboards
                  │  └───────────┘  │
                  └─────────────────┘

  GitHub Actions CI/CD
  ┌──────────────────────────────────────────────┐
  │  push to main                                │
  │       │                                      │
  │  ┌────▼────┐   ┌──────────────┐   ┌───────┐ │
  │  │  test   │──▶│ build+push   │──▶│deploy │ │
  │  │ go test │   │ ghcr.io      │   │ SSH   │ │
  │  └─────────┘   └──────────────┘   └───────┘ │
  └──────────────────────────────────────────────┘

  Image Registry: ghcr.io (GitHub Container Registry — free)
  IaC: Terraform (local state)
```

**Request flow:**
```
Client → Firewall → Nginx (port 80) → Go API (port 8080) → Response
```

---

## 3. Technology Stack

| Layer | Tool | Why |
|---|---|---|
| Language | Go 1.22 | Fast, single static binary, excellent HTTP concurrency |
| Router | chi v5 | Lightweight, stdlib-compatible, clean middleware API |
| Logging | zerolog | Structured JSON logs, zero-allocation |
| Metrics | Prometheus client_golang | Industry-standard, `/metrics` endpoint built-in |
| Container | Docker (multi-stage) | Small final image (~15 MB), non-root user |
| Reverse Proxy | Nginx 1.25 | `least_conn` load balancing, JSON access logs, security headers |
| Compose | Docker Compose v2 | Local dev + prod override pattern |
| CI/CD | GitHub Actions | Native GitHub integration, free for public repos |
| Registry | GitHub Container Registry (ghcr.io) | Free unlimited public packages |
| IaC | Terraform 1.6+ | Declarative, reproducible DigitalOcean infra |
| Cloud | DigitalOcean | Simple API, predictable pricing |
| Monitoring | Prometheus + Grafana | Request rate, latency, error rate dashboards |
| Orchestration | Kubernetes manifests (bonus) | Rolling updates, HPA, Ingress |

---

## 4. Application — Go REST API

### Architecture

The API follows clean architecture with strict layer separation:

```
cmd/server/          ← main(), HTTP server config, graceful shutdown
internal/
  domain/            ← Item entity, CreateItemInput, validation (no deps)
  store/             ← ItemRepository interface + MemoryStore (sync.RWMutex)
  service/           ← ItemService: business logic, metrics updates
  api/               ← HTTP handlers, routes, tests
  middleware/        ← RequestID, Logger, Metrics, Recoverer
  metrics/           ← Prometheus metric definitions
```

**Design principles applied:**
- **SRP** — each package has one responsibility
- **DIP** — `ItemService` depends on `ItemRepository` interface, not `MemoryStore`
- **Constructor injection** — no globals, all dependencies wired in `NewRouter()`

### Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | API index — lists all endpoints |
| `GET` | `/status` | Service health, version, uptime, item count |
| `POST` | `/data` | Submit `{"key":"...","value":...}`, returns created item |
| `GET` | `/data` | List all stored items |
| `GET` | `/healthz` | Liveness probe (nginx, Kubernetes, load balancer) |
| `GET` | `/readyz` | Readiness probe |
| `GET` | `/metrics` | Prometheus scrape endpoint |

### How ~100 req/s Is Handled

- **Go's goroutine-per-request model** — the runtime schedules thousands of goroutines on OS threads. A single `s-1vcpu-1gb` Droplet handles 300–500 req/s for this workload.
- **Explicit HTTP server timeouts** prevent slow clients from holding goroutines indefinitely:
  ```go
  ReadTimeout:       15 * time.Second
  ReadHeaderTimeout: 5 * time.Second
  WriteTimeout:      15 * time.Second
  IdleTimeout:       60 * time.Second
  ```
- **Nginx keepalive pool** — 32 persistent connections to the upstream, avoiding TCP handshake overhead on every request.
- **Stateless design** — each container is fully independent; horizontal scaling is a config change.
- **Kubernetes HPA** (bonus manifests) — auto-scales from 3 to 10 pods when CPU > 60%.

### Test Results

```
=== RUN   TestGetStatus_OK        --- PASS
=== RUN   TestPostData_Valid       --- PASS
=== RUN   TestPostData_MissingKey  --- PASS
=== RUN   TestPostData_BadJSON     --- PASS
=== RUN   TestGetData_ReturnsList  --- PASS
=== RUN   TestHealthz              --- PASS
=== RUN   TestReadyz               --- PASS
PASS  coverage: 78.3% of statements
```

---

## 5. Containerization

### Multi-Stage Dockerfile

```dockerfile
# Stage 1: build
FROM golang:1.22-alpine AS builder
RUN apk add --no-cache git ca-certificates tzdata
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download          # cached layer if deps unchanged
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" -o /app/bin/server ./cmd/server

# Stage 2: final (~15 MB)
FROM alpine:3.19
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/bin/server ./server
USER appuser                 # never run as root
ENTRYPOINT ["./server"]      # exec form — SIGTERM reaches Go process directly
```

**Key decisions:**

| Decision | Reason |
|---|---|
| Two-stage build | Final image has no Go toolchain — ~15 MB vs ~300 MB |
| `CGO_ENABLED=0` | Produces a fully static binary — no libc required in final image |
| `-ldflags="-w -s"` | Strips debug info — reduces binary size by ~30% |
| Non-root user | Security best practice — container cannot write to host paths |
| Exec-form `ENTRYPOINT` | Signals go to PID 1 (Go process), not a shell wrapper |
| Layer order | `go.mod/go.sum` before source code — dependency layer cached on code changes |

### Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8080` | HTTP listen port |
| `ENV` | `development` | Controls log format (JSON in production) |
| `APP_VERSION` | `dev` | Git SHA injected by CI at build time |

---

## 6. Reverse Proxy — Nginx

**Location:** [`infra/nginx/nginx.conf`](infra/nginx/nginx.conf)

### Key configuration

```nginx
upstream app_backend {
    least_conn;                         # route to least-busy container
    server app:8080 max_fails=3 fail_timeout=30s;
    keepalive 32;                       # persistent connections to app
}
```

**Features:**

| Feature | Config |
|---|---|
| Load balancing algorithm | `least_conn` |
| Keepalive connections to upstream | 32 persistent connections |
| JSON structured access logs | `log_format json_combined` |
| Security headers | `X-Content-Type-Options`, `X-Frame-Options`, `X-XSS-Protection` |
| Gzip compression | `gzip on` for `application/json` — ~70% bandwidth saving |
| `/metrics` blocked externally | `deny all` except Docker/k8s internal networks |
| Health probes excluded from logs | `access_log off` on `/healthz` and `/readyz` |
| Real IP forwarding | `X-Real-IP`, `X-Forwarded-For` passed to upstream |

### Sample nginx access log (JSON)

```json
{
  "time": "2026-04-02T07:33:10+00:00",
  "remote_addr": "103.192.157.228",
  "method": "GET",
  "uri": "/status",
  "status": 200,
  "bytes_sent": 109,
  "request_time": 0.000,
  "upstream_addr": "172.18.0.2:8080",
  "upstream_response_time": "0.000"
}
```

---

## 7. CI/CD Pipeline

**File:** [`.github/workflows/pipeline.yml`](.github/workflows/pipeline.yml)

### Pipeline stages

```
push to main
     │
     ▼
┌─────────┐     ┌───────────────────────┐     ┌──────────────────────────┐
│  test   │────▶│     build-image       │────▶│         deploy           │
│         │     │                       │     │                          │
│ go vet  │     │ docker/login-action   │     │ doctl → get Droplet IP   │
│ go test │     │ build & push api img  │     │ SSH → deploy.sh          │
│  -race  │     │ build & push nginx    │     │ verify /healthz passes   │
│coverage │     │ → ghcr.io (free)      │     │                          │
└─────────┘     └───────────────────────┘     └──────────────────────────┘
```

### Triggers

| Event | Jobs run |
|---|---|
| Push to `main` | test → build-image → deploy |
| Push to `develop` | test → build-image (no deploy) |
| Pull request to `main` | test only |

### Image tagging strategy

Every push to `main` produces two tags:
- `ghcr.io/imranhasan871/devops-practical-go-api:<7-char-sha>` — immutable, pinned to commit
- `ghcr.io/imranhasan871/devops-practical-go-api:latest` — always points to newest

### GitHub Actions secrets required

| Secret | Value |
|---|---|
| `DIGITALOCEAN_ACCESS_TOKEN` | DO API token (read/write) |
| `DEPLOY_SSH_KEY` | Private half of the deploy SSH key pair |

### Latest successful run

```
✓ Test              — 19s
✓ Build & Push Image — 55s
✓ Deploy            — 12s
Total               — 1m 17s
```

View all runs: https://github.com/imranhasan871/devops-practical/actions

---

## 8. Infrastructure as Code — Terraform

**Directory:** [`infra/terraform/`](infra/terraform/)

### Resources provisioned

```hcl
digitalocean_ssh_key   "deploy"   # deploy keypair
digitalocean_droplet   "app"      # s-1vcpu-1gb, Ubuntu 22.04, nyc3
digitalocean_firewall  "app"      # allow 22, 80, 8080 inbound
digitalocean_project   "main"     # groups resources in DO dashboard
```

### Droplet bootstrap (userdata)

On first boot the Droplet automatically:
1. Runs `apt-get upgrade`
2. Installs Docker + Docker Compose plugin
3. Authenticates to ghcr.io with the PAT
4. Writes `/opt/devops-practical/infra/docker-compose.yml`
5. Runs `docker compose pull && docker compose up -d`

### Reproduce the infrastructure

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# fill in do_token, ssh_public_key, ghcr_token

terraform init
terraform plan
terraform apply   # ~60 seconds
# outputs: droplet_ip
```

### Tear down

```bash
terraform destroy   # removes all DO resources
```

---

## 9. Zero-Downtime Deployment

### How it works

The deploy script ([`infra/scripts/deploy.sh`](infra/scripts/deploy.sh)) uses Docker Compose's **start-first** rolling update:

```
1. Record current running image tag (for rollback)
2. Authenticate to ghcr.io
3. Pull new image
4. Write docker-compose.override.yml with new image tag
5. docker compose up -d --no-deps --remove-orphans app
   └── Docker starts NEW container first
   └── OLD container keeps serving traffic
6. Poll /healthz up to 20 times (60 seconds)
   └── PASS → old container removed, deploy complete
   └── FAIL → rollback: restart with previous image tag
```

### Why no requests are dropped

- Nginx holds open keep-alive connections — in-flight requests to the old container complete
- The new container must pass `/healthz` before Nginx routes new requests to it
- The health check polls every 3 seconds × 20 retries = 60 second window
- On rollback, the previous image tag was saved before the pull, so the exact previous version is restored

### Graceful shutdown (Go side)

```go
// blocks until SIGTERM/SIGINT (docker stop sends SIGTERM)
sig := <-quit

// give in-flight requests 30 seconds to complete
ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
srv.Shutdown(ctx)
```

---

## 10. Monitoring & Observability

### Application logs (zerolog, structured JSON)

```json
{
  "level": "info",
  "method": "GET",
  "path": "/status",
  "status": 200,
  "duration": 0.024216,
  "remote_addr": "[::1]:48474",
  "request_id": "9f7a043b-c964-48f8-8fc0-10d77319c38f",
  "bytes_written": 109,
  "time": "2026-04-02T07:34:29Z",
  "message": "request"
}
```

Every request has a `request_id` (UUID) injected by the `RequestID` middleware, allowing end-to-end tracing across nginx and app logs.

### Prometheus metrics exposed at `/metrics`

| Metric | Type | Description |
|---|---|---|
| `http_requests_total{method,path,status}` | Counter | Total requests by method/path/status |
| `http_request_duration_seconds{method,path}` | Histogram | Latency percentiles (p50/p95/p99) |
| `http_requests_in_flight` | Gauge | Currently active requests |
| `data_items_total` | Counter | Total POST /data submissions |
| `data_store_size` | Gauge | Items currently in memory store |

### Grafana dashboard panels

| Panel | PromQL |
|---|---|
| Request Rate (req/s) | `rate(http_requests_total[1m])` |
| Error Rate (%) | `rate(http_requests_total{status=~"5.."}[1m]) / rate(http_requests_total[1m]) * 100` |
| p99 Latency | `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))` |
| In-Flight Requests | `http_requests_in_flight` |
| Data Store Size | `data_store_size` |

### View logs live

```bash
# nginx access logs (JSON)
ssh root@104.236.49.243 "docker logs infra-nginx-1 -f"

# app structured logs
ssh root@104.236.49.243 "docker logs infra-app-1 -f"
```

### Start monitoring stack locally

```bash
make docker-up
open http://localhost:3000   # Grafana (admin/changeme)
open http://localhost:9090   # Prometheus
```

---

## 11. Security & Secrets Management

### Nothing hardcoded — ever

| Where | Approach |
|---|---|
| Local dev | `.env` file (in `.gitignore`) |
| GitHub Actions | Repository Secrets (`DIGITALOCEAN_ACCESS_TOKEN`, `DEPLOY_SSH_KEY`) |
| Droplet (pull auth) | ghcr.io PAT written to `/opt/devops-practical/.env` at bootstrap, never in image |
| Terraform | `terraform.tfvars` (in `.gitignore`, never committed) |
| Container images | Zero credentials baked in |

### Container security

- **Non-root user** — `appuser:appgroup` created in Dockerfile, `USER appuser` before `ENTRYPOINT`
- **Read-only filesystem** — Kubernetes manifest sets `readOnlyRootFilesystem: true`
- **Drop all capabilities** — `capabilities: drop: ["ALL"]` in k8s security context
- **No privilege escalation** — `allowPrivilegeEscalation: false`

### Network security

- DigitalOcean Firewall restricts inbound to ports 22 and 80 only
- Port 8080 (app) and `/metrics` are not publicly routable in production Kubernetes setup
- SSH key-based authentication only (no passwords)

---

## 12. Kubernetes Manifests (Bonus)

**Directory:** [`infra/k8s/`](infra/k8s/)

### Files

| File | Purpose |
|---|---|
| `namespace.yaml` | Isolated `devops-practical` namespace |
| `configmap.yaml` | Non-secret env vars (PORT, ENV) |
| `deployment.yaml` | 3 replicas, rolling update, liveness/readiness probes, non-root security context |
| `service.yaml` | ClusterIP service on port 80 |
| `ingress.yaml` | Nginx ingress with TLS via cert-manager |
| `hpa.yaml` | HorizontalPodAutoscaler: 3–10 pods, scale at CPU 60% / memory 70% |

### Rolling update strategy

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0   # never reduce capacity
    maxSurge: 1         # one extra pod during rollout
```

New pod must pass `readinessProbe` (`/readyz`) before traffic shifts — guarantees zero downtime.

### Deploy to Kubernetes

```bash
kubectl apply -f infra/k8s/namespace.yaml
kubectl apply -f infra/k8s/configmap.yaml
kubectl apply -f infra/k8s/deployment.yaml
kubectl apply -f infra/k8s/service.yaml
kubectl apply -f infra/k8s/hpa.yaml
kubectl apply -f infra/k8s/ingress.yaml

# watch rollout
kubectl rollout status deployment/go-api -n devops-practical
```

---

## 13. Live Testing URLs

The API is live at **http://104.236.49.243**

### curl commands

```bash
BASE=http://104.236.49.243

# API index — lists all endpoints
curl $BASE/

# Liveness probe
curl $BASE/healthz

# Readiness probe
curl $BASE/readyz

# Service status (version, uptime, item count)
curl $BASE/status

# Submit a key/value item
curl -X POST $BASE/data \
  -H "Content-Type: application/json" \
  -d '{"key":"hello","value":"world"}'

# List all stored items
curl $BASE/data

# Prometheus metrics (raw)
curl $BASE/metrics
```

### Expected responses

**`GET /`**
```json
{
  "endpoints": ["GET  /status","GET  /data","POST /data","GET  /healthz","GET  /readyz","GET  /metrics"],
  "service": "devops-practical",
  "version": "dev"
}
```

**`GET /healthz`**
```json
{"status":"alive"}
```

**`GET /readyz`**
```json
{"status":"ready"}
```

**`GET /status`**
```json
{
  "status": "ok",
  "version": "dev",
  "uptime": "10m21s",
  "timestamp": "2026-04-02T07:33:10Z",
  "item_count": 2
}
```

**`POST /data`** — request:
```json
{"key":"environment","value":"digitalocean"}
```
Response `201 Created`:
```json
{
  "id": "1775115193560374001",
  "key": "environment",
  "value": "digitalocean",
  "created_at": "2026-04-02T07:33:13Z"
}
```

**`GET /data`**
```json
{
  "count": 2,
  "items": [
    {"id":"1775114939386229278","key":"cicd","value":"pipeline-deployed","created_at":"2026-04-02T07:28:59Z"},
    {"id":"1775115193560374001","key":"environment","value":"digitalocean","created_at":"2026-04-02T07:33:13Z"}
  ]
}
```

### Error cases

**`POST /data` — missing key → 400:**
```bash
curl -X POST $BASE/data -H "Content-Type: application/json" -d '{"value":"orphan"}'
# {"error":"validation failed: field 'key' is required","code":400}
```

**`POST /data` — invalid JSON → 400:**
```bash
curl -X POST $BASE/data -H "Content-Type: application/json" -d '{bad'
# {"error":"invalid JSON body","code":400}
```

### Full smoke test

```bash
BASE_URL=http://104.236.49.243 bash infra/scripts/health-check.sh
```

Expected output:
```
=== smoke tests against http://104.236.49.243 ===
PASS  liveness probe
PASS  readiness probe
PASS  GET /status
PASS  POST /data
PASS  GET /data

results: 5 passed, 0 failed
```

### GitHub Resources

| Resource | URL |
|---|---|
| Repository | https://github.com/imranhasan871/devops-practical |
| Actions (CI/CD runs) | https://github.com/imranhasan871/devops-practical/actions |
| Latest passing run | https://github.com/imranhasan871/devops-practical/actions/runs/23889026077 |
| API image (ghcr.io) | https://github.com/imranhasan871/devops-practical/pkgs/container/devops-practical-go-api |
| Nginx image (ghcr.io) | https://github.com/imranhasan871/devops-practical/pkgs/container/devops-practical-reverse-proxy |

---

## 14. Local Development

### Prerequisites

| Tool | Version |
|---|---|
| Go | 1.22+ |
| Docker + Compose v2 | latest |
| make | any |

### Start the full stack

```bash
git clone https://github.com/imranhasan871/devops-practical.git
cd devops-practical

cp .env.example .env
make docker-up

# app via nginx
curl http://localhost/status

# Grafana  → http://localhost:3000  (admin / changeme)
# Prometheus → http://localhost:9090
```

### Run tests

```bash
make test                # go test -v -race ./...
make test-cover          # + HTML coverage report
```

### Useful make targets

```bash
make run          # go run ./cmd/server
make build        # compile binary to bin/go-api
make lint         # golangci-lint
make docker-build # build image locally
make docker-down  # stop all containers
make docker-logs  # tail app container logs
```

---

## 15. Cost Breakdown

| Resource | Spec | Cost/month |
|---|---|---|
| Droplet | s-1vcpu-1gb, nyc3 | $6.00 |
| Container Registry | ghcr.io (public packages) | Free |
| CI/CD | GitHub Actions (public repo) | Free |
| **Total** | | **$6.00/month** |

To scale up: change `droplet_size = "s-2vcpu-4gb"` in `terraform.tfvars` and run `terraform apply`.

---

## 16. Challenges & Lessons Learned

### 1. Terraform `templatefile()` — `$$` escaping

**Problem:** Shell variables like `$VERSION_CODENAME` inside a Terraform `templatefile()` heredoc are treated as Terraform template references and cause parse errors.

**Solution:** Use `$$VERSION_CODENAME` to produce a literal `$` in the rendered script. Alternatively, hardcode the Ubuntu codename (`jammy`) for a fixed base image.

**Lesson:** Never use `${VAR}` shell syntax inside Terraform templates — prefer `$VAR` or hardcode known values.

---

### 2. Nginx build-time `RUN nginx -t` fails in Docker

**Problem:** The Nginx Dockerfile had `RUN nginx -t` to validate config at build time. This fails because the upstream hostname `app:8080` only exists inside the Docker Compose network at runtime — not during image build.

**Solution:** Remove the build-time validation. Nginx validates its config at container startup anyway and will fail fast if the config is invalid.

**Lesson:** Build-time checks that require runtime networking don't work in Docker — defer them to container startup or CI integration tests.

---

### 3. `GITHUB_TOKEN` cannot push to manually-created ghcr.io packages

**Problem:** Packages pushed manually from a local machine (using a PAT) are not linked to any repository. The `GITHUB_TOKEN` in GitHub Actions cannot push to them, resulting in `403 Forbidden`.

**Solution:** Delete the manually-created packages and let GitHub Actions create them fresh. Actions-created packages are automatically linked to the repository, so `GITHUB_TOKEN` can push to them.

**Lesson:** Always let CI create container registry packages on first push. Never pre-create them manually if you plan to use `GITHUB_TOKEN`.

---

### 4. Terraform remote state chicken-and-egg

**Problem:** Using DigitalOcean Spaces as a Terraform backend requires the Spaces bucket to exist before `terraform init`. But creating the bucket with Terraform requires init first.

**Solution:** Use `backend "local" {}` for the initial bootstrap. Once everything is provisioned, the state can be migrated to remote with `terraform init -migrate-state`.

**Lesson:** Bootstrap remote state manually (CLI or separate Terraform config) before using it as a backend.

---

### 5. Graceful shutdown requires exec-form ENTRYPOINT

**Problem:** If `ENTRYPOINT` uses shell form (`ENTRYPOINT ./server`), Docker sends `SIGTERM` to the shell process (PID 1), not the Go binary. The shell may forward it or not, resulting in the container being force-killed after the timeout.

**Solution:** Always use exec form: `ENTRYPOINT ["./server"]`. This makes the Go process PID 1 and receives signals directly.

**Lesson:** Shell-form entrypoints silently break graceful shutdown. Always use exec form in production Dockerfiles.
