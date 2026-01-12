#!/bin/bash
set -euo pipefail

# etcd Restore Script
# This script restores etcd from a backup
# WARNING: This will cause cluster downtime. Use with caution!
# Run this on the control plane node

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

if [ $# -lt 1 ]; then
    echo -e "${RED}Usage: $0 <backup-file>${NC}"
    exit 1
fi

BACKUP_FILE=$1

if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}Backup file not found: $BACKUP_FILE${NC}"
    exit 1
fi

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
echo "etcd Restore Script"
echo "=========================================="
echo ""
print_warning "WARNING: This will cause cluster downtime!"
print_warning "All etcd data will be replaced with backup data."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

# Step 1: Stop kubelet
print_status "Stopping kubelet..."
systemctl stop kubelet

# Step 2: Stop etcd static pod
print_status "Stopping etcd static pod..."
ETCD_MANIFEST="/etc/kubernetes/manifests/etcd.yaml"
if [ -f "$ETCD_MANIFEST" ]; then
    mv "$ETCD_MANIFEST" "${ETCD_MANIFEST}.backup"
    sleep 5
fi

# Step 3: Backup current etcd data
print_status "Backing up current etcd data..."
ETCD_DATA_DIR="/var/lib/etcd"
BACKUP_DATA_DIR="/var/lib/etcd-backup-$(date +%Y%m%d-%H%M%S)"
if [ -d "$ETCD_DATA_DIR" ]; then
    mv "$ETCD_DATA_DIR" "$BACKUP_DATA_DIR"
    print_status "Current etcd data backed up to: $BACKUP_DATA_DIR"
fi

# Step 4: Restore from backup
print_status "Restoring etcd from backup..."
RESTORE_DIR="/tmp/etcd-restore"
mkdir -p "$RESTORE_DIR"

# Use etcdctl to restore
ETCDCTL_API=3 etcdctl snapshot restore "$BACKUP_FILE" \
    --data-dir="$RESTORE_DIR" \
    --name=etcd-$(hostname) \
    --initial-cluster=etcd-$(hostname)=https://$(hostname -I | awk '{print $1}'):2380 \
    --initial-cluster-token=etcd-cluster-1 \
    --initial-advertise-peer-urls=https://$(hostname -I | awk '{print $1}'):2380

# Step 5: Move restored data to etcd directory
print_status "Moving restored data to etcd directory..."
mkdir -p "$ETCD_DATA_DIR"
cp -r "$RESTORE_DIR"/* "$ETCD_DATA_DIR"/
chown -R root:root "$ETCD_DATA_DIR"

# Step 6: Restore etcd manifest
print_status "Restoring etcd manifest..."
if [ -f "${ETCD_MANIFEST}.backup" ]; then
    mv "${ETCD_MANIFEST}.backup" "$ETCD_MANIFEST"
fi

# Step 7: Start kubelet
print_status "Starting kubelet..."
systemctl start kubelet

# Step 8: Wait for etcd to be ready
print_status "Waiting for etcd to be ready..."
sleep 10

ETCD_POD=""
for i in {1..30}; do
    ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$ETCD_POD" ]; then
        break
    fi
    echo "Waiting for etcd pod... ($i/30)"
    sleep 2
done

if [ -z "$ETCD_POD" ]; then
    print_error "etcd pod not found after restore"
    exit 1
fi

# Wait for etcd to be healthy
print_status "Waiting for etcd to be healthy..."
for i in {1..60}; do
    if kubectl exec -n kube-system $ETCD_POD -- \
        sh -c "ETCDCTL_API=3 etcdctl \
        --endpoints=https://127.0.0.1:2379 \
        --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        endpoint health" &> /dev/null; then
        print_status "etcd is healthy!"
        break
    fi
    echo "Waiting for etcd health... ($i/60)"
    sleep 2
done

# Step 9: Verify cluster status
print_status "Verifying cluster status..."
kubectl get nodes
kubectl get pods -n kube-system

echo ""
echo "=========================================="
echo -e "${GREEN}Restore Complete!${NC}"
echo "=========================================="
echo ""
print_warning "Please verify all services are running correctly"
echo "Old etcd data backed up to: $BACKUP_DATA_DIR"
echo ""

