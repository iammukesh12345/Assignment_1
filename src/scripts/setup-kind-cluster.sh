
#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Employee Management DevOps Assignment
# Automated Kind Kubernetes Cluster Setup
#
# Cluster: employee-cluster
# Node: Single control-plane
# Host Port: 8081 (localhost only)
# Kubernetes NodePort: 30080
# ============================================================

CLUSTER_NAME="employee-cluster"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_SRC="$(cd "${SCRIPT_DIR}/.." && pwd)"

KIND_CONFIG="${PROJECT_SRC}/kubernetes/kind-config.yaml"

log() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

error() {
    echo "ERROR: $1" >&2
    exit 1
}

# ------------------------------------------------------------
# STEP 1: Verify required tools
# ------------------------------------------------------------

log "STEP 1: Checking required tools"

for tool in docker kind kubectl; do
    command -v "$tool" >/dev/null 2>&1 || \
        error "$tool is not installed."
done

docker info >/dev/null 2>&1 || \
    error "Docker daemon is not accessible."

echo "Docker, Kind and kubectl are available."

# ------------------------------------------------------------
# STEP 2: Verify Kind configuration
# ------------------------------------------------------------

log "STEP 2: Checking Kind configuration"

[[ -f "$KIND_CONFIG" ]] || \
    error "Configuration not found: $KIND_CONFIG"

echo "Using configuration: $KIND_CONFIG"

cat "$KIND_CONFIG"

# ------------------------------------------------------------
# STEP 3: Check existing cluster
# ------------------------------------------------------------

log "STEP 3: Checking existing Kind clusters"

if kind get clusters | grep -Fxq "$CLUSTER_NAME"; then

    echo "Cluster '$CLUSTER_NAME' already exists."
    echo "Skipping cluster creation."

else

    log "STEP 4: Creating Kubernetes cluster"

    kind create cluster \
        --name "$CLUSTER_NAME" \
        --config "$KIND_CONFIG" \
        --wait 120s

    echo "Cluster created successfully."

fi

# ------------------------------------------------------------
# STEP 4: Configure kubectl context
# ------------------------------------------------------------

log "STEP 5: Configuring kubectl"

kind export kubeconfig --name "$CLUSTER_NAME"

kubectl config use-context "kind-${CLUSTER_NAME}"

# ------------------------------------------------------------
# STEP 5: Verify cluster readiness
# ------------------------------------------------------------

log "STEP 6: Verifying Kubernetes cluster"

kubectl wait \
    --for=condition=Ready \
    node \
    --all \
    --timeout=120s

kubectl get nodes -o wide

echo
kubectl cluster-info

# ------------------------------------------------------------
# STEP 6: Verify Kubernetes system pods
# ------------------------------------------------------------

log "STEP 7: Checking Kubernetes system pods"

kubectl get pods -n kube-system

echo
echo "Storage classes:"
kubectl get storageclass

# ------------------------------------------------------------
# STEP 7: Check EC2 resources
# ------------------------------------------------------------

log "STEP 8: Checking EC2 resources"

free -h

echo
df -h /

echo
docker system df

# ------------------------------------------------------------
# Final summary
# ------------------------------------------------------------

log "Kubernetes cluster setup completed"

echo "Cluster Name: $CLUSTER_NAME"
echo "kubectl Context: kind-${CLUSTER_NAME}"
echo "Application Host Port: 8081"
echo "Kubernetes NodePort: 30080"

echo
echo "Next:"
echo "1. Create Kubernetes manifests."
echo "2. Configure Jenkins kubeconfig access."
echo "3. Automate deployment through Jenkins."

