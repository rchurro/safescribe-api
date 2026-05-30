#!/usr/bin/env bash
# Deploy PostgreSQL and Redis on the cluster.
# Run once from a machine with kubectl + helm access.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Adding Bitnami Helm repo"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# ── PostgreSQL ────────────────────────────────────────────────────────────────

PG_NAMESPACE="postgres"
PG_RELEASE="postgresql"
PG_PASSWORD="${PG_PASSWORD:-$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')}"

echo ""
echo "==> Installing PostgreSQL"
kubectl create namespace "$PG_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "$PG_RELEASE" bitnami/postgresql \
  --namespace "$PG_NAMESPACE" \
  --values "$ROOT_DIR/postgres/values.yaml" \
  --set auth.password="$PG_PASSWORD" \
  --wait

echo ""
echo "    PostgreSQL ready."
echo "    !! Save this password in your password manager now !!"
echo "    PG_PASSWORD=${PG_PASSWORD}"
echo ""
echo "    Production URL:"
echo "    postgresql+asyncpg://safescribe:${PG_PASSWORD}@${PG_RELEASE}.${PG_NAMESPACE}.svc.cluster.local:5432/safescribe"
echo ""
echo "    Staging URL:"
echo "    postgresql+asyncpg://safescribe:${PG_PASSWORD}@${PG_RELEASE}.${PG_NAMESPACE}.svc.cluster.local:5432/safescribe_staging"

# ── Redis ─────────────────────────────────────────────────────────────────────

REDIS_NAMESPACE="redis"
REDIS_RELEASE="redis"

echo ""
echo "==> Installing Redis"
kubectl create namespace "$REDIS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "$REDIS_RELEASE" bitnami/redis \
  --namespace "$REDIS_NAMESPACE" \
  --values "$ROOT_DIR/redis/values.yaml" \
  --wait

echo ""
echo "    Redis ready."
echo ""
echo "    Production URL: redis://${REDIS_RELEASE}-master.${REDIS_NAMESPACE}.svc.cluster.local:6379/0"
echo "    Staging URL:    redis://${REDIS_RELEASE}-master.${REDIS_NAMESPACE}.svc.cluster.local:6379/1"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "==> Done. Next: populate Vault secrets — see TODO.md 'Vault — Populate Secrets'."
