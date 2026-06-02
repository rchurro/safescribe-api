# safescribe-api

FastAPI backend for SafeScribe — a school psychologist report writing tool. Handles auth, subscription management via Stripe, and AI model access control.

## Stack

- **Framework**: FastAPI + SQLAlchemy (async)
- **Database**: PostgreSQL (asyncpg)
- **Cache / sessions**: Redis
- **Auth**: JWT (access + refresh tokens)
- **Payments**: Stripe subscriptions
- **Secrets**: HashiCorp Vault (Kubernetes agent injector)
- **Deploy**: k3s + ArgoCD + Helm + Cloudflare Tunnel

## Environments

| Environment | API URL | Branch |
|---|---|---|
| Staging | `https://staging-ssapi.mai.style` | `staging` |
| Production | `https://safescribe.mai.style` | `main` |

## CI/CD Pipeline

```
git push → GitHub Actions (build image → GHCR)
         → ArgoCD Image Updater (detects new tag)
         → ArgoCD (syncs Helm chart → k3s)
         → Discord notification
```

### Notifications
Discord notifications are sent to a private channel on:
- GitHub Actions: image build success/fail, test pass/fail
- ArgoCD: deploy succeeded, health degraded, sync failed

Requires a `DISCORD_WEBHOOK` secret set in GitHub repository secrets.

## Local development

```bash
cp .env.example .env
# fill in .env values
docker compose up
```

## Running tests

```bash
pip install -e ".[dev]"
pytest -v
```

## Deployment

Push to `staging` branch to deploy to staging. Merge to `main` for production.

ArgoCD Image Updater automatically detects new images tagged `staging-<sha>` or `main-<sha>` and updates the Helm values file.

## Secrets

Secrets are injected at runtime via Vault agent. The following keys are expected in Vault:

- `database_url`
- `redis_url`
- `jwt_secret_key`
- `stripe_secret_key`
- `stripe_webhook_secret`
- `stripe_price_id`
