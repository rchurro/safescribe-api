# safescribe-api

FastAPI paywall backend for SafeScribe. Handles user auth, Stripe subscriptions, and gating access to WebLLM model IDs based on subscription status.

## What it does

Users register and log in. Free users get access to one model (`Llama-3.2-1B`). Paid users unlock the full model list. Payment is handled by Stripe Checkout — when a subscription completes, a Stripe webhook flips `is_paid = true` on the user record.

## Architecture

```mermaid
graph TD
    Client["Browser / Frontend\nsafescribe.mai.style"]
    API["SafeScribe API\nFastAPI on port 8000"]
    PG["PostgreSQL\nuser data"]
    Redis["Redis\nrefresh tokens"]
    Stripe["Stripe\npayments"]
    Vault["Vault Agent\nsecrets injector"]

    Client -->|REST| API
    API -->|read/write users| PG
    API -->|store/verify refresh tokens| Redis
    API -->|create checkout session| Stripe
    Stripe -->|webhook: checkout.session.completed| API
    Vault -->|inject secrets at pod start| API
```

## Request flows

### Auth

```mermaid
sequenceDiagram
    participant C as Client
    participant API
    participant DB as PostgreSQL
    participant R as Redis

    C->>API: POST /auth/register {email, password}
    API->>DB: INSERT user (bcrypt hashed password)
    DB-->>API: user row
    API-->>C: 201 {id, email, is_paid}

    C->>API: POST /auth/login {email, password}
    API->>DB: SELECT user WHERE email=?
    API->>API: verify bcrypt hash
    API->>R: SETEX refresh:{token} = user_id (30d TTL)
    API-->>C: {access_token (JWT 15m), refresh_token}

    C->>API: POST /auth/refresh {refresh_token}
    API->>R: GET refresh:{token}
    API->>R: DEL old token, SETEX new token
    API-->>C: {new access_token, new refresh_token}

    C->>API: POST /auth/logout {refresh_token}
    API->>R: DEL refresh:{token}
    API-->>C: 204
```

### Paywall

```mermaid
sequenceDiagram
    participant C as Client
    participant API
    participant Stripe
    participant DB as PostgreSQL

    C->>API: GET /models (no auth)
    API-->>C: {models: [Llama-3.2-1B], is_paid: false}

    C->>API: POST /stripe/checkout (Bearer token)
    API->>Stripe: create Checkout Session (user_id in metadata)
    Stripe-->>API: checkout URL
    API-->>C: {checkout_url}

    C->>Stripe: user completes payment
    Stripe->>API: POST /stripe/webhook (checkout.session.completed)
    API->>API: verify Stripe signature
    API->>DB: UPDATE users SET is_paid=true, stripe_customer_id=?
    API-->>Stripe: 200

    C->>API: GET /models (Bearer token, is_paid=true)
    API-->>C: {models: [...all 100+ models], is_paid: true}
```

## CI/CD pipeline

```mermaid
flowchart LR
    subgraph GitHub
        PR["Pull Request\nto main/staging"]
        CI["CI workflow\ntests + coverage"]
        Push["Push to\nmain or staging"]
        CD["CD workflow\nbuild + push image"]
        GHCR["GHCR\nghcr.io/rchurro/safescribe-api"]
    end

    subgraph "Kubernetes Cluster"
        IU["ArgoCD\nImage Updater"]
        Argo["ArgoCD\napp controller"]
        NS_S["safescribe-staging\nnamespace"]
        NS_P["safescribe-production\nnamespace"]
    end

    PR --> CI
    Push --> CD
    CD --> GHCR
    GHCR --> IU
    IU -->|"commits new tag to\nvalues.staging.yaml / values.production.yaml"| Push
    Argo -->|watches git| NS_S
    Argo -->|watches git| NS_P
```

**Tag format:**
- `staging` branch → `ghcr.io/rchurro/safescribe-api:staging-<sha>`
- `main` branch → `ghcr.io/rchurro/safescribe-api:main-<sha>`

## Secret management (Vault)

Secrets are never stored in git or Kubernetes secrets. At pod startup, the Vault Agent sidecar authenticates using the pod's Kubernetes service account, fetches secrets, and writes them to `/vault/secrets/env`. The app sources that file before starting.

```mermaid
flowchart TD
    Pod["Pod starts"]
    Injector["Vault Agent Injector\n(mutating webhook)"]
    VA["Vault Agent sidecar\ninjected into pod"]
    VaultServer["Vault Server"]
    Secrets["/vault/secrets/env\nDATABASE_URL\nREDIS_URL\nJWT_SECRET_KEY\nSTRIPE_SECRET_KEY\netc."]
    App["FastAPI app\nsources env file"]

    Pod --> Injector
    Injector --> VA
    VA -->|k8s service account auth| VaultServer
    VaultServer -->|secret/data/safescribe/api| Secrets
    Secrets --> App
```

Vault paths:
- Production: `secret/data/safescribe/api` (role: `safescribe-api`)
- Staging: `secret/data/safescribe/api-staging` (role: `safescribe-api-staging`)

## Infrastructure layout

Both environments run on the same Kubernetes cluster. Some infrastructure is shared, some is isolated:

| Component | Shared or isolated |
|---|---|
| PostgreSQL pod | **Shared** — separate databases (`safescribe` vs `safescribe_staging`) |
| Redis pod | **Shared** — separate DB indexes (`/0` vs `/1`) |
| Vault pod | **Shared** — separate secret paths and auth roles per env |
| ArgoCD | **Shared** — manages both apps |
| App pods | **Isolated** — separate namespaces, deployments, service accounts |
| Cloudflare Tunnel | **Isolated** — separate tunnel and `cloudflared` deployment per environment |
| Stripe keys | **Isolated** — live keys for production, test keys for staging |
| JWT secrets | **Isolated** — separate keys per environment |

If Postgres or Redis goes down, both environments are affected. This is an intentional tradeoff to keep infrastructure costs low.

## Helm environments

| Values file | Namespace | Image tag pattern | Replicas | Autoscaling |
|---|---|---|---|---|
| `values.yaml` | — | base defaults | 2 | off |
| `values.staging.yaml` | `safescribe-staging` | `staging-<sha>` | 1 | off |
| `values.production.yaml` | `safescribe-production` | `main-<sha>` | 2 | 2–6 pods |

## Development workflow

Changes go through a PR process — direct pushes to `main` or `staging` are discouraged.

```
feature branch → pull request → CI → merge → CD → deploy
```

**CI** runs automatically on every PR to `main` or `staging`:
- Spins up real Postgres 16 and Redis 7 containers (no mocks)
- Runs the full test suite with coverage
- Must pass before merging

**CD** runs automatically on every push to `main` or `staging`:
- Builds a multi-arch Docker image (`linux/amd64`, `linux/arm64`)
- Pushes to GHCR with a `<branch>-<sha>` tag
- ArgoCD Image Updater detects the new tag and triggers a rolling deploy

| Branch | Environment | Image tag |
|---|---|---|
| `staging` | `safescribe-staging` | `staging-<sha>` |
| `main` | `safescribe-production` | `main-<sha>` |

## Local development

```bash
cp .env.example .env
# fill in .env

docker compose up          # starts api + postgres + redis
docker compose run migrate # run on first setup or after new migration
```

API available at `http://localhost:8000`.  
Swagger UI at `http://localhost:8000/docs` (only when `DEBUG=true`).

## Database migrations

```bash
# create a new migration
alembic revision --autogenerate -m "description"

# apply
alembic upgrade head

# rollback one
alembic downgrade -1
```

Migrations run automatically at app startup (before uvicorn starts) on every deploy.

## API endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/auth/register` | none | Create account |
| `POST` | `/auth/login` | none | Get access + refresh tokens |
| `POST` | `/auth/refresh` | none | Rotate tokens |
| `POST` | `/auth/logout` | Bearer | Invalidate refresh token |
| `GET` | `/models` | optional | List available WebLLM model IDs |
| `POST` | `/stripe/checkout` | Bearer | Create Stripe Checkout session |
| `POST` | `/stripe/webhook` | Stripe sig | Handle payment events |
| `GET` | `/health` | none | Liveness check |
| `GET` | `/metrics` | none | Prometheus metrics |

## Notifications

Discord notifications are sent to a private channel on:

| Event | Source |
|---|---|
| Image build success/fail | GitHub Actions (CD workflow) |
| Test pass/fail | GitHub Actions (CI workflow) |
| Deploy succeeded | ArgoCD Notifications |
| Health degraded | ArgoCD Notifications |
| Sync failed | ArgoCD Notifications |

Requires a `DISCORD_WEBHOOK` secret set in GitHub repository secrets (Settings → Secrets and variables → Actions).
