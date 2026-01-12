# Deployment Guide

Step-by-step guide to deploy the complete Kubernetes cluster and services.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Control Plane Setup](#control-plane-setup)
- [Worker Node Setup](#worker-node-setup)
- [Service Deployment](#service-deployment)
- [Verification](#verification)
- [Post-Deployment Configuration](#post-deployment-configuration)

## Prerequisites

### System Requirements

- **Control Plane Node**: 2+ CPU, 2GB+ RAM, 20GB+ disk
- **Worker Nodes**: 2+ CPU, 2GB+ RAM, 20GB+ disk each
- **Network**: All nodes must be able to communicate
- **OS**: Ubuntu 20.04+, CentOS 7+, or RHEL 8+

### Software Requirements

- Docker 20.10+ or containerd 1.6+
- kubeadm 1.28+
- kubectl 1.28+
- kubelet 1.28+

### Network Requirements

- Port 6443: Kubernetes API server
- Port 10250: Kubelet API
- Port 10259: Kube-scheduler
- Port 10257: Kube-controller-manager
- Port 2379-2380: etcd server client API
- Port 30000-32767: NodePort services

## Control Plane Setup

### Step 1: Prepare Control Plane Node

```bash
# SSH into control plane node
ssh user@control-plane-ip

# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### Step 2: Install Container Runtime

#### Option A: containerd (Recommended)

```bash
# Install containerd
sudo apt-get install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Enable systemd cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
```

#### Option B: Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Configure Docker for Kubernetes
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

sudo systemctl restart docker
sudo systemctl enable docker
```

### Step 3: Install Kubernetes Components

```bash
# Add Kubernetes repository
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubeadm, kubelet, kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

### Step 4: Initialize Control Plane

#### Option A: Using Script (Recommended)

```bash
# Clone or copy project files to control plane node
# Then run setup script
sudo ./scripts/setup-control-plane.sh
```

#### Option B: Manual Setup

```bash
# Get control plane IP
CONTROL_PLANE_IP=$(hostname -I | awk '{print $1}')

# Initialize cluster
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=$CONTROL_PLANE_IP \
  --control-plane-endpoint=$CONTROL_PLANE_IP

# Setup kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Step 5: Install CNI Plugin (Calico)

```bash
# Install Calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

# Wait for Calico to be ready
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s
```

### Step 6: Generate Join Command

```bash
# Generate join command for worker nodes
kubeadm token create --print-join-command

# Save the output - you'll need it for worker nodes
```

## Worker Node Setup

### Step 1: Prepare Worker Node

```bash
# SSH into worker node
ssh user@worker-node-ip

# Follow same preparation steps as control plane:
# - Disable swap
# - Load kernel modules
# - Configure sysctl
# - Install container runtime
# - Install Kubernetes components
```

### Step 2: Join Worker Node to Cluster

#### Option A: Using Script

```bash
# Use token and hash from control plane
sudo ./scripts/join-worker-node.sh <token> <discovery-hash> <control-plane-ip>
```

#### Option B: Manual Join

```bash
# Use the join command from control plane
sudo kubeadm join <control-plane-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### Step 3: Verify Worker Node

```bash
# On control plane node
kubectl get nodes

# Worker node should show as Ready
```

## Service Deployment

### Step 1: Create Namespaces

```bash
# From your local machine (with kubectl configured)
kubectl apply -f manifests/namespace.yaml

# Verify
kubectl get namespaces
```

### Step 2: Deploy Stateful Services First

```bash
# Deploy PostgreSQL
kubectl apply -f manifests/postgresql/postgres-statefulset.yaml

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod -l app=postgresql -n production --timeout=300s

# Deploy Redis
kubectl apply -f manifests/redis/redis-statefulset.yaml

# Wait for Redis to be ready
kubectl wait --for=condition=ready pod -l app=redis -n production --timeout=300s
```

### Step 3: Deploy Application Services

```bash
# Deploy API service
kubectl apply -f manifests/api-service/api-deployment.yaml

# Deploy Worker service
kubectl apply -f manifests/worker-service/worker-deployment.yaml

# Wait for services to be ready
kubectl wait --for=condition=ready pod -l app=api-service -n production --timeout=300s
kubectl wait --for=condition=ready pod -l app=worker-service -n production --timeout=300s
```

### Step 4: Verify All Services

```bash
# Check all pods
kubectl get pods -n production

# Check services
kubectl get svc -n production

# Check all resources
kubectl get all -n production
```

## Verification

### Cluster Health

```bash
# Check nodes
kubectl get nodes

# All nodes should be Ready
# Control plane should have master role

# Check system pods
kubectl get pods -n kube-system

# All system pods should be Running
```

### Service Health

```bash
# Check application pods
kubectl get pods -n production

# All pods should be Running

# Check pod logs
kubectl logs -l app=api-service -n production
kubectl logs -l app=worker-service -n production

# Test API service
kubectl run test-curl --image=curlimages/curl --rm -it -- \
  curl http://api-service.production.svc.cluster.local
```

### Resource Usage

```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n production
```

## Post-Deployment Configuration

### Setup etcd Backups

```bash
# Create backup directory
sudo mkdir -p /var/backups/etcd

# Test backup
sudo ./scripts/etcd-backup.sh

# Setup cron job for automated backups
sudo crontab -e

# Add line (backup every 5 minutes):
*/5 * * * * /path/to/scripts/etcd-backup.sh
```

### Configure Monitoring (Optional)

```bash
# Install metrics server (if not already installed)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify metrics
kubectl top nodes
kubectl top pods
```

### Setup Load Balancer (Optional)

If you need external access:

```bash
# Install MetalLB (for bare metal)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# Or use NodePort services
kubectl patch svc api-service -n production -p '{"spec":{"type":"NodePort"}}'
```

### Network Policies (Optional)

```bash
# Apply network policies for security
# kubectl apply -f manifests/network-policies/
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n production

# Check events
kubectl get events -n production --sort-by='.lastTimestamp'

# Check logs
kubectl logs <pod-name> -n production
```

### Services Not Accessible

```bash
# Check service endpoints
kubectl get endpoints -n production

# Check service configuration
kubectl describe svc <service-name> -n production

# Test DNS
kubectl run test-dns --image=busybox --rm -it -- \
  nslookup <service-name>.production.svc.cluster.local
```

### Node Not Joining

```bash
# Check kubelet status on worker node
sudo systemctl status kubelet

# Check kubelet logs
sudo journalctl -u kubelet -n 50

# Verify network connectivity
ping <control-plane-ip>
telnet <control-plane-ip> 6443
```

## Next Steps

1. **Test Failure Scenarios**: Use `scripts/simulate-failures.sh`
2. **Run Load Tests**: Use `scripts/load-test.sh`
3. **Practice Recovery**: Follow [recovery-procedures.md](recovery-procedures.md)
4. **Read Documentation**: Review all docs in `docs/` directory

## Additional Resources

- [Architecture Documentation](architecture.md)
- [Recovery Procedures](recovery-procedures.md)
- [Debugging Guide](debugging-guide.md)
- [etcd Operations](etcd-operations.md)

