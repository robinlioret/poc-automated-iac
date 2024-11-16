#!/bin/bash

# Go to root directory
DIR_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
cd "$DIR_ROOT" || exit 1

# Create the cluster
mkdir -p ~/mnt/kind/ 2> /dev/null
mkdir ./sensitive 2> /dev/null
kind delete cluster
kind create cluster --config ./config/kind-cluster.yaml

# Install ingress controller
echo "Installing Nginx controller..."
sleep 5
kubectl apply -f ./manifests/nginx-controller.yaml
echo "Nginx ingress controller installed. Waiting for the deployment to be up"
sleep 10
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
echo "Nginx ingress controller deployed."

# Verify the ingress controller
#ingress_is_ok=0
#kubectl apply -f ./tests/test-ingress-controller.yaml
#for index in {1..90}; do
#  echo "Ingress validation (attempt $index/60)"
#  sleep 1
#  result=$(curl http://localhost/foo 2> /dev/null)
#  if [[ $result = "foo-app" ]]; then
#    ingress_is_ok=1
#    echo "Ingress is ok"
#    break
#  fi
#done
#if [[ $ingress_is_ok = 0 ]]; then
#  echo "Ingress is not working"
#  exit 1
#fi
#kubectl delete -f ./tests/test-ingress-controller.yaml

# Install ArgoCD
echo "Deploying ArgoCD..."
kubectl create namespace argocd
kubectl apply --namespace argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/refs/heads/master/manifests/install.yaml
echo "Waiting for the server to be up and running..."
sleep 10
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=90s
echo "ArgoCD is up"
echo "Updating host file"
grep -v "argocd.rli-gitops-pulumi.local" /etc/hosts | sudo tee /etc/hosts > /dev/null
echo -e "127.0.0.1\targocd.rli-gitops-pulumi.local" | sudo tee -a /etc/hosts > /dev/null
echo "Deploying the ArgoCD ingress"
kubectl apply -f ./manifests/argocd-ingress.yaml
sleep 5
echo "Check argocd response"
if curl -k https://argocd.rli-gitops-pulumi.local > /dev/null; then
  echo "ArgoCD is accessible from https://argocd.rli-gitops-pulumi.local"
else
  echo "Something went wrong with argoCD deployment"
  exit 1
fi
echo "Storing ArgoCD admin password in a temp file"
kubectl get secret --namespace argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d > ./sensitive/argocd-password
echo "Deploy ArgoCD application set and initialize gitops"
kubectl apply --namespace argocd -f ./manifests/argocd-applicationset-helm-git.yaml
kubectl apply --namespace argocd -f ./manifests/argocd-applicationset-helm-external.yaml
kubectl apply --namespace argocd -f ./manifests/argocd-applicationset-manifest.yaml