#!/bin/bash
set -euo pipefail

# Failure Simulation Script
# This script simulates various failure scenarios for testing recovery procedures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Usage: $0 <scenario> [options]"
    echo ""
    echo "Scenarios:"
    echo "  pod-eviction          - Simulate pod eviction due to resource pressure"
    echo "  node-failure <node>   - Simulate node failure (cordon and drain)"
    echo "  crashloop <pod>       - Simulate CrashLoopBackOff"
    echo "  api-server-down       - Stop API server (control plane)"
    echo "  etcd-down             - Stop etcd (control plane)"
    echo "  resource-exhaustion   - Create resource pressure"
    echo "  network-partition     - Simulate network issues"
    echo ""
    echo "Examples:"
    echo "  $0 pod-eviction"
    echo "  $0 node-failure worker-node-1"
    echo "  $0 crashloop api-service-xxx"
    exit 1
}

if [ $# -lt 1 ]; then
    show_usage
fi

SCENARIO=$1
shift

case $SCENARIO in
    pod-eviction)
        print_status "Simulating pod eviction due to resource pressure..."
        
        # Create a pod that will consume too much memory
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: memory-hog
  namespace: production
spec:
  containers:
  - name: memory-hog
    image: polinux/stress
    resources:
      requests:
        memory: "100Mi"
      limits:
        memory: "200Mi"
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "250M", "--vm-hang", "1"]
EOF
        print_warning "Pod 'memory-hog' created. It will be evicted due to memory limits."
        print_status "Monitor with: kubectl get events --field-selector involvedObject.name=memory-hog"
        ;;
    
    node-failure)
        if [ $# -lt 1 ]; then
            print_error "Node name required"
            show_usage
        fi
        NODE=$1
        
        print_warning "Simulating failure of node: $NODE"
        print_status "Cordoning node (preventing new pods)..."
        kubectl cordon $NODE
        
        print_status "Draining node (evicting existing pods)..."
        kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --force
        
        print_warning "Node $NODE is now 'failed'. To restore:"
        echo "  kubectl uncordon $NODE"
        ;;
    
    crashloop)
        if [ $# -lt 1 ]; then
            print_error "Pod name required (or use 'api-service' or 'worker-service')"
            show_usage
        fi
        POD_NAME=$1
        
        print_status "Simulating CrashLoopBackOff for pod: $POD_NAME"
        
        # Get the deployment name
        if [[ "$POD_NAME" == "api-service" ]]; then
            DEPLOYMENT="api-service"
            NAMESPACE="production"
        elif [[ "$POD_NAME" == "worker-service" ]]; then
            DEPLOYMENT="worker-service"
            NAMESPACE="production"
        else
            # Try to get deployment from pod
            DEPLOYMENT=$(kubectl get pod $POD_NAME -o jsonpath='{.metadata.labels.app}' 2>/dev/null || echo "")
            NAMESPACE=$(kubectl get pod $POD_NAME -o jsonpath='{.metadata.namespace}' 2>/dev/null || echo "default")
        fi
        
        if [ -z "$DEPLOYMENT" ]; then
            print_error "Could not find deployment for pod: $POD_NAME"
            exit 1
        fi
        
        # Patch deployment to use a bad image that will crash
        print_status "Patching deployment $DEPLOYMENT to use invalid image..."
        kubectl set image deployment/$DEPLOYMENT -n $NAMESPACE \
            $(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].name}')=invalid-image:latest
        
        print_warning "Deployment $DEPLOYMENT will now crash. To fix:"
        echo "  kubectl rollout undo deployment/$DEPLOYMENT -n $NAMESPACE"
        ;;
    
    api-server-down)
        print_warning "Stopping API server (requires root access)..."
        print_status "This will make the cluster unmanageable!"
        
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Cancelled."
            exit 0
        fi
        
        # Stop kube-apiserver static pod
        API_MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
        if [ -f "$API_MANIFEST" ] && [ "$EUID" -eq 0 ]; then
            mv "$API_MANIFEST" "${API_MANIFEST}.backup"
            print_warning "API server stopped. To restore:"
            echo "  sudo mv ${API_MANIFEST}.backup $API_MANIFEST"
        else
            print_error "Cannot stop API server. Run as root or manually move:"
            echo "  sudo mv $API_MANIFEST ${API_MANIFEST}.backup"
        fi
        ;;
    
    etcd-down)
        print_warning "Stopping etcd (requires root access)..."
        print_status "This will cause cluster data loss risk!"
        
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Cancelled."
            exit 0
        fi
        
        # Stop etcd static pod
        ETCD_MANIFEST="/etc/kubernetes/manifests/etcd.yaml"
        if [ -f "$ETCD_MANIFEST" ] && [ "$EUID" -eq 0 ]; then
            mv "$ETCD_MANIFEST" "${ETCD_MANIFEST}.backup"
            print_warning "etcd stopped. To restore:"
            echo "  sudo mv ${ETCD_MANIFEST}.backup $ETCD_MANIFEST"
        else
            print_error "Cannot stop etcd. Run as root or manually move:"
            echo "  sudo mv $ETCD_MANIFEST ${ETCD_MANIFEST}.backup"
        fi
        ;;
    
    resource-exhaustion)
        print_status "Creating resource exhaustion scenario..."
        
        # Create multiple resource-intensive pods
        for i in {1..5}; do
            cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cpu-hog-$i
  namespace: production
spec:
  containers:
  - name: cpu-hog
    image: polinux/stress
    resources:
      requests:
        cpu: "500m"
      limits:
        cpu: "1000m"
    command: ["stress"]
    args: ["--cpu", "4"]
EOF
        done
        
        print_warning "Created 5 CPU-intensive pods. This will cause resource pressure."
        print_status "Clean up with: kubectl delete pod -n production -l app=cpu-hog"
        ;;
    
    network-partition)
        print_status "Simulating network partition..."
        print_warning "This requires iptables manipulation (run as root)"
        
        if [ "$EUID" -ne 0 ]; then
            print_error "This scenario requires root access"
            exit 1
        fi
        
        # Block traffic to API server (simulate partition)
        API_SERVER_IP=$(kubectl get endpoints kubernetes -o jsonpath='{.subsets[0].addresses[0].ip}')
        print_status "Blocking traffic to API server: $API_SERVER_IP"
        
        iptables -A OUTPUT -d $API_SERVER_IP -j DROP
        print_warning "Network partition active. To restore:"
        echo "  sudo iptables -D OUTPUT -d $API_SERVER_IP -j DROP"
        ;;
    
    *)
        print_error "Unknown scenario: $SCENARIO"
        show_usage
        ;;
esac

echo ""
print_status "Scenario '$SCENARIO' executed. Monitor cluster status:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  kubectl get events --sort-by='.lastTimestamp'"
echo ""

