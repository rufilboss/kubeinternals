#!/bin/bash
set -euo pipefail

# Kubernetes Control Plane Setup Script
# This script initializes a Kubernetes control plane node using kubeadm
# Run this script on the node designated as the control plane

echo "=========================================="
echo "Kubernetes Control Plane Setup"
echo "=========================================="

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

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

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
    # Enable systemd cgroup driver
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
    
    # Add Kubernetes repository
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
    
    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
else
    print_warning "Kubernetes components already installed"
fi

# Step 6: Initialize control plane
print_status "Initializing Kubernetes control plane..."
if [ ! -f /etc/kubernetes/admin.conf ]; then
    # Use kubeadm config if provided, otherwise use defaults
    if [ -f "$(dirname "$0")/../configs/kubeadm-config.yaml" ]; then
        kubeadm init --config="$(dirname "$0")/../configs/kubeadm-config.yaml"
    else
        kubeadm init \
            --pod-network-cidr=10.244.0.0/16 \
            --apiserver-advertise-address=$(hostname -I | awk '{print $1}') \
            --control-plane-endpoint=$(hostname -I | awk '{print $1}')
    fi
    
    # Setup kubeconfig for root user
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
else
    print_warning "Control plane already initialized"
fi

# Step 7: Install CNI plugin (Calico)
print_status "Installing Calico CNI plugin..."
if ! kubectl get daemonset calico-node -n kube-system &> /dev/null; then
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml
    
    # Wait for Calico to be ready
    print_status "Waiting for Calico to be ready..."
    kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s
else
    print_warning "Calico already installed"
fi

# Step 8: Generate join command
print_status "Generating join command for worker nodes..."
JOIN_COMMAND=$(kubeadm token create --print-join-command 2>/dev/null || echo "kubeadm token create --print-join-command")
DISCOVERY_TOKEN=$(kubeadm token list | grep -v TOKEN | awk '{print $1}' | head -1)
DISCOVERY_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')

echo ""
echo "=========================================="
echo -e "${GREEN}Control Plane Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "To join worker nodes, use:"
echo "  sudo kubeadm join <CONTROL_PLANE_IP>:6443 --token $DISCOVERY_TOKEN \\"
echo "    --discovery-token-ca-cert-hash sha256:$DISCOVERY_HASH"
echo ""
echo "Or run:"
echo "  sudo kubeadm token create --print-join-command"
echo ""
echo "Save this information securely!"
echo ""

