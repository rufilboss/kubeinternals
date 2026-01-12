#!/bin/bash
set -euo pipefail

# Kubernetes Worker Node Join Script
# This script joins a worker node to an existing Kubernetes cluster
# Usage: ./join-worker-node.sh <token> <discovery-token-ca-cert-hash>

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Check arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: $0 <token> <discovery-token-ca-cert-hash>${NC}"
    echo -e "${YELLOW}Or run on control plane: kubeadm token create --print-join-command${NC}"
    exit 1
fi

TOKEN=$1
DISCOVERY_HASH=$2
CONTROL_PLANE_IP=${3:-$(echo "Please provide control plane IP as third argument")}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "Kubernetes Worker Node Join"
echo "=========================================="

# Step 1: Disable swap
print_status "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Step 2: Load kernel modules
print_status "Loading required kernel modules..."
modprobe overlay
modprobe br_netfilter

# Step 3: Configure sysctl
print_status "Configuring sysctl parameters..."
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# Step 4: Install container runtime (containerd)
print_status "Installing containerd..."
if ! command -v containerd &> /dev/null; then
    apt-get update
    apt-get install -y containerd
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd
    systemctl enable containerd
else
    print_warning "containerd already installed"
fi

# Step 5: Install kubeadm, kubelet, kubectl
print_status "Installing Kubernetes components..."
if ! command -v kubeadm &> /dev/null; then
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gpg
    
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
    
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
else
    print_warning "Kubernetes components already installed"
fi

# Step 6: Join the cluster
print_status "Joining Kubernetes cluster..."
if [ ! -f /etc/kubernetes/kubelet.conf ]; then
    kubeadm join $CONTROL_PLANE_IP:6443 \
        --token $TOKEN \
        --discovery-token-ca-cert-hash sha256:$DISCOVERY_HASH
else
    print_warning "Node already joined to cluster"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Worker Node Join Complete!${NC}"
echo "=========================================="
echo ""
echo "Verify node status on control plane:"
echo "  kubectl get nodes"
echo ""

