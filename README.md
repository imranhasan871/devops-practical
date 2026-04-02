# devops-practical

A production-style Go API service demonstrating containerisation, CI/CD automation, traffic management, and observability — deployed on **DigitalOcean**.

---

## System Architecture

```
                     ┌─────────────────────────────────────────────────────┐
                     │                DigitalOcean (nyc3)                   │
                     │                                                       │
  Internet ──► LB ──►│  ┌──────────────────────────────────────────────┐   │
  (port 80)          │  │                  VPC 10.10.0.0/16             │   │
                     │  │                                               │   │
                     │  │   ┌──────────┐      ┌──────────┐             │   │
                     │  │   │ Droplet 1 │      │ Droplet 2 │            │   │
                     │  │   │  :8080   │      │  :8080   │             │   │
                     │  │   └────┬─────┘      └────┬─────┘             │   │
                     │  │        │                  │                   │   │
                     │  │        └──────┬───────────┘                  │   │
                     │  │               │                               │   │
                     │  │        Prometheus + Grafana                   │   │
                     │  └──────────────────────────────────────────────┘   │
                     │                                                       │
                     │  Container Registry (DOCR)                           │
                     └─────────────────────────────────────────────────────┘
```

**Request flow:** client → DigitalOcean Load Balancer → app Droplet (port 8080) → response

**Stack:**
- **Go API** — clean architecture, SOLID, constructor DI, graceful shutdown
- **DigitalOcean Load Balancer** — health-checks `/healthz`, distributes traffic across Droplets
- **Firewall** — Droplets only accept traffic from the Load Balancer; port 22 restricted to VPC
- **DOCR** — DigitalOcean Container Registry stores all built images
- **Prometheus + Grafana** — request rate, latency percentiles, error rate (run in docker compose alongside the app)
- **Terraform** — full infrastructure provisioned via IaC; state in DigitalOcean Spaces
- **GitHub Actions** — test → build → push to DOCR → rolling deploy one Droplet at a time

---

## API Endpoints

| Method | Path      | Description                                         |
|--------|-----------|-----------------------------------------------------|
| GET    | /status   | Service health, version, uptime, stored item count  |
| POST   | /data     | Submit a key/value item `{"key":"...","value":...}` |
| GET    | /data     | List all stored items                               |
| GET    | /healthz  | Liveness probe (load balancer + Kubernetes)         |
| GET    | /readyz   | Readiness probe                                     |
| GET    | /metrics  | Prometheus metrics (blocked externally by firewall) |

**GET /status**
```bash
curl http://<LB_IP>/status
# → {"status":"ok","version":"abc1234","uptime":"5m30s","timestamp":"...","item_count":2}
```

**POST /data**
```bash
curl -X POST http://<LB_IP>/data \
  -H "Content-Type: application/json" \
  -d '{"key":"region","value":"nyc3"}'
# → {"id":"1736936014123456789","key":"region","value":"nyc3","created_at":"..."}
```

---

## Project Structure

```
.
├── cmd/server/          # main() — server config, graceful shutdown
├── internal/
│   ├── domain/          # Item, CreateItemInput (no external deps)
│   ├── store/           # ItemRepository interface + MemoryStore
│   ├── service/         # ItemService (business logic layer)
│   ├── api/             # HTTP Handler, routes, tests
│   ├── middleware/       # RequestID, Logger, Metrics, Recoverer
│   └── metrics/         # Prometheus metric definitions
├── infra/
│   ├── nginx/           # Reverse proxy config + Dockerfile
│   ├── k8s/             # Kubernetes manifests (bonus)
│   ├── terraform/       # DigitalOcean IaC
│   ├── monitoring/      # Prometheus + Grafana config
│   ├── scripts/         # deploy.sh, health-check.sh
│   ├── docker-compose.yml
│   └── docker-compose.prod.yml
└── .github/workflows/   # CI/CD pipeline
```

---

## How ~100 req/s Is Handled

- **Go's HTTP server** uses one goroutine per request, scheduled by the Go runtime. A single `s-1vcpu-2gb` Droplet comfortably handles 300–500 req/s for this workload.
- **2 Droplets behind the Load Balancer** gives ~600–1 000 req/s headroom.
- **Explicit server timeouts** (`ReadTimeout`, `WriteTimeout`, `IdleTimeout`) prevent slow clients from holding goroutines open indefinitely.
- **Stateless design** — each Droplet is fully independent; adding more scales linearly.
- **Kubernetes HPA** (if using the k8s path) auto-scales from 3 to 10 pods on CPU/memory thresholds.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Go | 1.22+ | https://go.dev/dl |
| Docker + Compose v2 | latest | https://docs.docker.com/engine/install |
| doctl | latest | `brew install doctl` or https://github.com/digitalocean/doctl/releases |
| Terraform | 1.6+ | `brew install terraform` or https://developer.hashicorp.com/terraform/install |

---

## Step-by-Step DigitalOcean Deployment

### 1 — Create a DigitalOcean Account & API Token

1. Sign up at https://cloud.digitalocean.com
2. Go to **API → Tokens → Generate New Token**
3. Name it `devops-practical`, enable **Read + Write**, click **Generate**
4. Copy the token — you'll use it in several places below

### 2 — Push the Repo to GitHub

```bash
# inside the devops-practical folder
git remote add origin https://github.com/<your-username>/devops-practical.git
git push -u origin main
```

### 3 — Set GitHub Actions Secrets

Go to your repo → **Settings → Secrets and variables → Actions → New repository secret**

Add every secret in this table:

| Secret name | Value | Where to get it |
|---|---|---|
| `DIGITALOCEAN_ACCESS_TOKEN` | your DO API token | Step 1 |
| `DO_REGISTRY_NAME` | `devops-practical` | you chose this in tfvars |
| `DEPLOY_SSH_KEY` | **private** SSH key (PEM format) | generated below |

**Generate an SSH key pair for deployments:**
```bash
ssh-keygen -t ed25519 -C "deploy@devops-practical" -f ~/.ssh/do_deploy -N ""
# ~/.ssh/do_deploy      ← paste this into the DEPLOY_SSH_KEY secret
# ~/.ssh/do_deploy.pub  ← paste this into terraform.tfvars as ssh_public_key
```

### 4 — Create the Terraform State Bucket

```bash
doctl auth init   # paste your API token

# create a Spaces bucket for remote state (do this once, manually)
doctl spaces create devops-practical-tfstate --region nyc3
```

### 5 — Provision Infrastructure with Terraform

```bash
cd infra/terraform

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — fill in do_token, ssh_public_key, etc.

terraform init
terraform plan     # review what will be created
terraform apply    # type "yes" to confirm

# after apply finishes, note the outputs:
# load_balancer_ip  → point your domain's A record here
# registry_endpoint → used as your IMAGE prefix
```

Expected resources created:
- 1 VPC (`10.10.0.0/16`)
- 1 DigitalOcean Container Registry (`devops-practical`)
- 2 Droplets (`s-1vcpu-2gb`, Ubuntu 22.04)
- 1 Load Balancer (health-checks `/healthz` on port 8080)
- 1 Firewall (restricts Droplet access to LB + VPC only)
- 1 Project (groups everything in the DO dashboard)

### 6 — First Deploy (Trigger CI/CD)

The pipeline runs automatically on every push to `main`. Either push a commit or trigger it manually:

```bash
git commit --allow-empty -m "trigger: first deploy to DO"
git push origin main
```

Watch it in **Actions** tab on GitHub. The pipeline will:
1. Run `go test -race ./...`
2. Build and push the Docker image to your DOCR
3. SSH into each Droplet and run `scripts/deploy.sh` one at a time
4. Verify the Load Balancer health check passes

### 7 — Verify Everything Is Working

```bash
LB_IP=$(doctl compute load-balancer list --format IP --no-header)

curl http://$LB_IP/status
curl http://$LB_IP/healthz
curl -X POST http://$LB_IP/data -H "Content-Type: application/json" -d '{"key":"test","value":1}'
curl http://$LB_IP/data

# full smoke test
BASE_URL=http://$LB_IP bash infra/scripts/health-check.sh
```

### 8 — (Optional) Point a Domain

1. In your DNS provider, create an **A record** pointing `api.yourdomain.com` → `<load_balancer_ip>`
2. Wait for propagation (~5 minutes for DigitalOcean Managed DNS)

---

## Zero-Downtime Deployment

### How It Works

The GitHub Actions deploy job rolls through each Droplet **one at a time**:

1. Pulls the new image onto Droplet N
2. Runs `docker compose up -d --no-deps app` — starts the new container alongside the old one
3. Polls `/healthz` up to 20 times (60 seconds)
4. If health checks pass → old container is removed, moves to Droplet N+1
5. If health checks fail → rolls back to the previous image on that Droplet immediately

The DigitalOcean Load Balancer continuously health-checks all Droplets. If a Droplet fails its health check, the LB stops sending traffic to it within ~10 seconds, so no requests are dropped during the update window.

**At no point are all Droplets updating simultaneously.**

---

## Local Development

```bash
cp .env.example .env
make docker-up   # runs: docker compose -f infra/docker-compose.yml up -d --build

# app via nginx on port 80
curl http://localhost/status

# Grafana dashboard
open http://localhost:3000    # admin / changeme

# Prometheus
open http://localhost:9090
```

Run tests:
```bash
make test
```

---

## CI/CD Pipeline Summary

```
push to main
     │
     ▼
┌─────────┐    ┌───────────────────┐    ┌──────────────────────────────┐
│  test   │───►│   build-image     │───►│           deploy             │
│         │    │                   │    │                              │
│ go vet  │    │ docker build      │    │ doctl → get Droplet IPs      │
│ go test │    │ push to DOCR      │    │ SSH → deploy.sh (one by one) │
│  -race  │    │ DOCR GC cleanup   │    │ verify LB health check       │
└─────────┘    └───────────────────┘    └──────────────────────────────┘
```

---

## Monitoring

Prometheus scrapes `/metrics` every 5 seconds. Grafana is auto-provisioned with a dashboard showing:

| Panel | Metric |
|---|---|
| Request Rate | `rate(http_requests_total[1m])` |
| Error Rate % | `rate(http_requests_total{status=~"5.."}[1m])` |
| Latency p50/p95/p99 | `histogram_quantile(0.99, ...)` |
| In-Flight Requests | `http_requests_in_flight` |
| Data Store Size | `data_store_size` |

Access Grafana at port `3000` on the Droplet (or expose via SSH tunnel):
```bash
ssh -L 3000:localhost:3000 root@<droplet-ip>
open http://localhost:3000
```

---

## Secrets Summary (Nothing Hardcoded)

| Where | How secrets are handled |
|---|---|
| Local dev | `.env` file (git-ignored) |
| GitHub Actions | Repository Secrets (`DIGITALOCEAN_ACCESS_TOKEN`, `DEPLOY_SSH_KEY`, `DO_REGISTRY_NAME`) |
| Droplets | Environment variables via docker compose; DO API token only used at bootstrap time |
| Terraform | `terraform.tfvars` (git-ignored); sensitive vars redacted from plan output |
| Container images | No credentials baked in; images pulled from DOCR using doctl auth |

---

## Tear Down

```bash
cd infra/terraform
terraform destroy   # removes all DO resources (LB, Droplets, registry, VPC, firewall)
```

> **Note:** The Spaces bucket used for Terraform state is not managed by Terraform itself (to avoid accidental deletion). Delete it manually via the DO dashboard or `doctl spaces delete devops-practical-tfstate`.

---

## Running Tests

```bash
# unit tests with race detector
go test -v -race ./...

# with HTML coverage report
make test-cover

# smoke test against a running stack
BASE_URL=http://localhost bash infra/scripts/health-check.sh
```
