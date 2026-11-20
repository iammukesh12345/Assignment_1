
#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Employee Management DevOps Assignment
# Tool Installation Script - Ubuntu 24.04
#
# Tools:
#   1. Docker Engine
#   2. Docker Compose
#   3. Java 21
#   4. Jenkins
#   5. kubectl
#   6. Kind (Kubernetes in Docker)
#
# Designed for AWS EC2 / Jenkins CI/CD lab environment.
# ============================================================

export DEBIAN_FRONTEND=noninteractive

log() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

if [[ "$EUID" -eq 0 ]]; then
    echo "Run as the ubuntu user, not as root."
    echo "The script uses sudo where required."
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: sudo is required."
    exit 1
fi

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "ERROR: This script requires Linux."
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "ubuntu" ]]; then
    echo "ERROR: This script supports Ubuntu."
    exit 1
fi

ARCH="$(dpkg --print-architecture)"

case "$ARCH" in
    amd64)
        K8S_ARCH="amd64"
        ;;
    arm64)
        K8S_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Pin these versions for reproducible installation.
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.33.4}"
KIND_VERSION="${KIND_VERSION:-v0.27.0}"

# ------------------------------------------------------------
# STEP 1: Update system and install dependencies
# ------------------------------------------------------------

log "STEP 1: Installing system dependencies"

sudo apt-get update

sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    git \
    unzip \
    fontconfig \
    openjdk-21-jre

java -version

# ------------------------------------------------------------
# STEP 2: Install Docker Engine and Docker Compose
# ------------------------------------------------------------

log "STEP 2: Installing Docker Engine and Compose"

if ! command -v docker >/dev/null 2>&1; then

    sudo install -m 0755 -d /etc/apt/keyrings

    sudo curl -fsSL \
        https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc

    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list \
      > /dev/null

    sudo apt-get update

    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

else
    echo "Docker already installed. Skipping installation."
fi

sudo systemctl enable --now docker

# Add the current user to Docker group.
sudo usermod -aG docker "$(id -un)"

docker --version
docker compose version

# ------------------------------------------------------------
# STEP 3: Install Jenkins
# ------------------------------------------------------------

log "STEP 3: Installing Jenkins"

if ! dpkg-query -W -f='${Status}' jenkins 2>/dev/null \
    | grep -q "install ok installed"; then

    sudo install -m 0755 -d /etc/apt/keyrings

    sudo curl -fsSL \
        https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
        -o /etc/apt/keyrings/jenkins-keyring.asc

    echo \
      "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
      | sudo tee /etc/apt/sources.list.d/jenkins.list \
      > /dev/null

    sudo apt-get update

    sudo apt-get install -y jenkins

else
    echo "Jenkins already installed. Skipping installation."
fi

sudo systemctl enable --now jenkins

# ------------------------------------------------------------
# STEP 4: Configure Jenkins Docker permissions
# ------------------------------------------------------------

log "STEP 4: Configuring Jenkins Docker access"

# WARNING:
# Docker group membership grants root-equivalent host access.
# Use only with trusted Jenkins jobs in this isolated lab.

sudo usermod -aG docker jenkins

# Refresh Jenkins group membership.
sudo systemctl restart jenkins

echo "Jenkins added to Docker group."

# ------------------------------------------------------------
# STEP 5: Install kubectl
# ------------------------------------------------------------

log "STEP 5: Installing kubectl"

if ! command -v kubectl >/dev/null 2>&1; then

    TMP_DIR="$(mktemp -d)"

    curl -fsSL \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${K8S_ARCH}/kubectl" \
        -o "${TMP_DIR}/kubectl"

    curl -fsSL \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${K8S_ARCH}/kubectl.sha256" \
        -o "${TMP_DIR}/kubectl.sha256"

    (
        cd "$TMP_DIR"
        echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    )

    sudo install -o root -g root -m 0755 \
        "${TMP_DIR}/kubectl" \
        /usr/local/bin/kubectl

    rm -rf "$TMP_DIR"

else
    echo "kubectl already installed. Skipping installation."
fi

kubectl version --client

# ------------------------------------------------------------
# STEP 6: Install Kind
# ------------------------------------------------------------

log "STEP 6: Installing Kind"

if ! command -v kind >/dev/null 2>&1; then

    TMP_DIR="$(mktemp -d)"

    curl -fsSL \
        "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${K8S_ARCH}" \
        -o "${TMP_DIR}/kind"

    sudo install -o root -g root -m 0755 \
        "${TMP_DIR}/kind" \
        /usr/local/bin/kind

    rm -rf "$TMP_DIR"

else
    echo "Kind already installed. Skipping installation."
fi

kind version

# ------------------------------------------------------------
# STEP 7: Verify installed tools and services
# ------------------------------------------------------------

log "STEP 7: Final verification"

echo "Docker:"
docker --version

echo
echo "Docker Compose:"
docker compose version

echo
echo "Java:"
java -version

echo
echo "Jenkins:"
jenkins --version

echo
echo "kubectl:"
kubectl version --client

echo
echo "Kind:"
kind version

echo
echo "Docker service:"
sudo systemctl is-active docker

echo
echo "Jenkins service:"
sudo systemctl is-active jenkins

echo
echo "Disk usage:"
df -h /

echo
echo "Memory:"
free -h

log "DevOps tools installation completed"

echo "IMPORTANT:"
echo "1. Log out and reconnect via SSH to refresh Docker groups."
echo "2. Kind cluster creation is a separate step."
echo "3. Jenkins kubeconfig access must be configured separately."
echo "4. Do not expose Jenkins port 8080 publicly."

