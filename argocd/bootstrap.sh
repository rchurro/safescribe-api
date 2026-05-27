#!/usr/bin/env bash
# Bootstrap ArgoCD + Image Updater on a k3s cluster for safescribe-api.
# Run this once from a machine with kubectl access to your cluster.
set -euo pipefail

ARGOCD_VERSION="v2.13.0"
IMAGE_UPDATER_VERSION="v0.15.0"

echo "==> Installing ArgoCD ${ARGOCD_VERSION}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for ArgoCD server to be ready"
kubectl rollout status deploy/argocd-server -n argocd --timeout=120s

echo "==> Installing ArgoCD Image Updater ${IMAGE_UPDATER_VERSION}"
kubectl apply -n argocd -f \
  "https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/${IMAGE_UPDATER_VERSION}/manifests/install.yaml"

echo "==> Retrieving initial ArgoCD admin password"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "    admin password: ${ARGOCD_PASSWORD}"
echo "    (change this after first login)"

echo ""
echo "==> Configuring GitHub repository access"
echo "    Set GITHUB_TOKEN before running this section, then uncomment:"
echo ""
echo "    argocd login <ARGOCD_SERVER> --username admin --password '${ARGOCD_PASSWORD}'"
echo "    argocd repo add https://github.com/rchurro/safescribe-api \\"
echo "      --username rchurro --password \$GITHUB_TOKEN"
echo ""

echo "==> Applying Application manifests"
kubectl apply -f "$(dirname "$0")/application-staging.yaml"
kubectl apply -f "$(dirname "$0")/application-production.yaml"

echo ""
echo "==> Done. Next steps:"
echo "    1. Port-forward ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "    2. Login at https://localhost:8080 with admin / ${ARGOCD_PASSWORD}"
echo "    3. Add your GitHub repo (see above)"
echo "    4. Configure Vault Agent Injector: helm install vault hashicorp/vault --set='injector.enabled=true'"
echo "    5. Create Vault k8s auth role 'safescribe-api' with policy allowing read on secret/data/safescribe/api"
echo "    6. Expose ArgoCD via Cloudflare Tunnel or kubectl port-forward"
