#!/bin/bash
# @See https://argo-cd.readthedocs.io/en/stable/getting_started/

# Variables
export ARGOCD_NS="argocd"
export ARGOCD_VERSION="v2.7.4" # must be tagged version, e.g. v2.7.4
KUBE_CONTEXT="kind-kind"
CREATE_CLUSTER=true
REMOVE_EXISTING_CLUSTER=false
export ARGOCD_OPTS='--insecure'

# Do not touch
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
KIND_CONFIG="$SCRIPT_DIR/kind-config.yaml"

function must_be_installed() {
    echo "Checking if $1 is installed"
    if [[ $(command -v $1) ]]; then
        echo "$1 is installed. Continuing...";
    else
        echo "$1 must be installed first. Aborting..."; 
        exit 2;
    fi;
}

# Prepare
if [[ $(command -v argocd) ]]; then
    echo "argocd CLI is already installed."
else
    if [[ $(uname -s) = "Linux" ]]; then
        ## Install argo cd cli
        curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_VERSION/argocd-linux-amd64
        sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
        rm argocd-linux-amd64
    else
        echo "Cannot install argocd cli. Aborting..."
        exit 1;
    fi;
fi;

echo "Preparing cluster..."
must_be_installed docker
must_be_installed kubectl

if [[ $(kubectl config use-context $KUBE_CONTEXT) ]]; then
    echo "Cluster already exists";

    if [ "$REMOVE_EXISTING_CLUSTER" = true ]; then
        must_be_installed kind;

        echo "Should the existing cluster be removed? [yes/no]"
        read -p 'Continue: ' confirm
        [[ $confirm == [yY][eE][sS] ]] && kind delete cluster || exit 1;
    fi;
fi;

if [ "$CREATE_CLUSTER" = true ]; then
    echo "Creating local cluster using kind"
    must_be_installed kind;

    kind create cluster --config $KIND_CONFIG;
else
    echo "No cluster found. Aborting...";
    exit 2;
fi;

## Install argo cd into cluster
kubectl config set-context --current --namespace=$ARGOCD_NS
kubectl create namespace $ARGOCD_NS
kubectl apply -n $ARGOCD_NS -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml

echo "Waiting for argocd to complete setup..."
sleep 10
kubectl wait --for=condition=ready --timeout=120s pod -n $ARGOCD_NS -l app.kubernetes.io/name=argocd-server


if pid=$(lsof -wn -i:8443 -t); then
    echo "Port 8443 is already used ($pid). Cannot start port-forwarding."
else
    echo "Starting port-forwarding..."
    kubectl port-forward svc/argocd-server -n $ARGOCD_NS 8443:443 1>/dev/null & 
fi;

adminPassword=$(kubectl -n $ARGOCD_NS get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Initial admin password: $adminPassword"
echo $adminPassword > "$SCRIPT_DIR/.password"

argocd login --core
argocd cluster add $KUBE_CONTEXT