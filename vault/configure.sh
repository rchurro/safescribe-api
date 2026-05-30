#!/usr/bin/env bash
# Configure Vault for safescribe-api after init + unseal.
# Prerequisites: vault-0 is unsealed, VAULT_ROOT_TOKEN is set.
#
# Usage: VAULT_ROOT_TOKEN=hvs.xxx ./vault/configure.sh
set -euo pipefail

VAULT_NAMESPACE="vault"
VAULT_POD="vault-0"

PROD_NAMESPACE="safescribe-production"
PROD_SA="safescribe-api-production"
PROD_ROLE="safescribe-api"
PROD_SECRET_PATH="secret/data/safescribe/api"
PROD_POLICY="safescribe-api"

STAGING_NAMESPACE="safescribe-staging"
STAGING_SA="safescribe-api-staging"
STAGING_ROLE="safescribe-api-staging"
STAGING_SECRET_PATH="secret/data/safescribe/api-staging"
STAGING_POLICY="safescribe-api-staging"

vexec() {
  kubectl exec -i -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_TOKEN="$VAULT_ROOT_TOKEN" vault "$@"
}

echo "==> Logging in to Vault"
vexec status | grep -E "^Sealed"

echo "==> Enabling KV v2 secrets engine at secret/"
vexec secrets enable -path=secret kv-v2 2>/dev/null || echo "    already enabled"

echo "==> Enabling Kubernetes auth method"
vexec auth enable kubernetes 2>/dev/null || echo "    already enabled"

echo "==> Configuring Kubernetes auth"
vexec write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

echo "==> Creating production policy: ${PROD_POLICY}"
vexec policy write "$PROD_POLICY" - <<EOF
path "${PROD_SECRET_PATH}" {
  capabilities = ["read"]
}
EOF

echo "==> Creating production k8s auth role: ${PROD_ROLE}"
vexec write "auth/kubernetes/role/${PROD_ROLE}" \
  bound_service_account_names="$PROD_SA" \
  bound_service_account_namespaces="$PROD_NAMESPACE" \
  policies="$PROD_POLICY" \
  ttl=1h

echo "==> Creating staging policy: ${STAGING_POLICY}"
vexec policy write "$STAGING_POLICY" - <<EOF
path "${STAGING_SECRET_PATH}" {
  capabilities = ["read"]
}
EOF

echo "==> Creating staging k8s auth role: ${STAGING_ROLE}"
vexec write "auth/kubernetes/role/${STAGING_ROLE}" \
  bound_service_account_names="$STAGING_SA" \
  bound_service_account_namespaces="$STAGING_NAMESPACE" \
  policies="$STAGING_POLICY" \
  ttl=1h

echo ""
echo "==> Done. Now populate secrets:"
echo ""
echo "    Production:"
echo "    kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- \\"
echo "      env VAULT_TOKEN=\$VAULT_ROOT_TOKEN vault kv put secret/safescribe/api \\"
echo "      database_url='postgres://...' \\"
echo "      redis_url='redis://...' \\"
echo "      jwt_secret_key='...' \\"
echo "      stripe_secret_key='sk_live_...' \\"
echo "      stripe_webhook_secret='whsec_...' \\"
echo "      stripe_price_id='price_...'"
echo ""
echo "    Staging:"
echo "    kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- \\"
echo "      env VAULT_TOKEN=\$VAULT_ROOT_TOKEN vault kv put secret/safescribe/api-staging \\"
echo "      database_url='postgres://...' \\"
echo "      redis_url='redis://...' \\"
echo "      jwt_secret_key='...' \\"
echo "      stripe_secret_key='sk_test_...' \\"
echo "      stripe_webhook_secret='whsec_...' \\"
echo "      stripe_price_id='price_...'"
