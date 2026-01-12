# Local Development with Kind

Guide for setting up a local Kubernetes cluster using Kind (Kubernetes in Docker) for development and testing.

## Prerequisites

- Docker installed and running
- kubectl installed
- 4GB+ RAM available
- 20GB+ disk space

## Installation

### Install Kind

```bash
# Linux/macOS
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Or using package manager
# macOS
brew install kind

# Verify installation
kind version
```

### Install kubectl

```bash
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verify installation
kubectl version --client
```

## Cluster Setup

### Create Cluster

```bash
# Basic cluster
kind create cluster --name kubeinternals

# With custom configuration
kind create cluster --name kubeinternals --config kind-config.yaml
```

### Custom Kind Configuration

Create `kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
```

Create cluster with config:
```bash
kind create cluster --name kubeinternals --config kind-config.yaml
```

### Verify Cluster

```bash
# Get cluster info
kubectl cluster-info --context kind-kubeinternals

# Get nodes
kubectl get nodes

# Get all pods
kubectl get pods -A
```

## Deploy Services

### Apply Manifests

```bash
# Set context
kubectl config use-context kind-kubeinternals

# Create namespaces
kubectl apply -f manifests/namespace.yaml

# Deploy services
kubectl apply -f manifests/api-service/
kubectl apply -f manifests/worker-service/
kubectl apply -f manifests/redis/
kubectl apply -f manifests/postgresql/
```

### Verify Deployment

```bash
# Check all resources
kubectl get all -n production

# Check pod status
kubectl get pods -n production

# Check services
kubectl get svc -n production
```

## Storage Configuration

Kind uses local storage. For PersistentVolumes, you may need a local storage provisioner:

```bash
# Install local-path-provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml

# Set as default storage class
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## Testing Failure Scenarios

### Pod Eviction

```bash
# Create resource-intensive pod
kubectl apply -f - <<EOF
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
    args: ["--vm", "1", "--vm-bytes", "250M"]
EOF

# Monitor eviction
kubectl get events --field-selector involvedObject.name=memory-hog -n production
```

### Node Failure

```bash
# Get node name
kubectl get nodes

# Cordon node
kubectl cordon kind-kubeinternals-worker

# Drain node
kubectl drain kind-kubeinternals-worker --ignore-daemonsets --delete-emptydir-data

# Uncordon node
kubectl uncordon kind-kubeinternals-worker
```

## etcd Operations

### Access etcd

```bash
# Get etcd pod
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

# Access etcd
kubectl exec -it -n kube-system $ETCD_POD -- sh
```

### Backup etcd

```bash
# Use the backup script (may need modification for Kind)
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n kube-system $ETCD_POD -- \
  sh -c "ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-snapshot.db"

# Copy backup
kubectl cp kube-system/$ETCD_POD:/tmp/etcd-snapshot.db ./etcd-backup.db
```

## Load Testing

```bash
# Port forward API service
kubectl port-forward -n production svc/api-service 8080:80

# In another terminal, run load test
./scripts/load-test.sh api-service 1000
```

## Cleanup

### Delete Cluster

```bash
# Delete cluster
kind delete cluster --name kubeinternals

# List clusters
kind get clusters
```

### Remove All Clusters

```bash
# Delete all clusters
kind get clusters | xargs -I {} kind delete cluster --name {}
```

## Limitations

1. **Single Control Plane**: Kind clusters typically have one control plane node
2. **Storage**: Local storage only, not suitable for production storage testing
3. **Networking**: Different networking model than production
4. **Performance**: Slower than bare metal or VMs

## Tips

1. **Resource Limits**: Set appropriate resource limits for Kind
2. **Image Caching**: Pre-pull images to speed up deployments
3. **Multiple Clusters**: Create separate clusters for different tests
4. **Snapshot**: Use Docker volumes for persistent data

## Troubleshooting

### Cluster Creation Fails

```bash
# Check Docker
docker ps

# Check Docker resources
docker system df

# Clean up Docker
docker system prune -a
```

### Pods Stuck in Pending

```bash
# Check node resources
kubectl describe node

# Check events
kubectl get events --sort-by='.lastTimestamp'
```

### Storage Issues

```bash
# Check storage class
kubectl get storageclass

# Check PVC status
kubectl get pvc -A
```

## Additional Resources

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Kind Examples](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [Main README](../README.md)

