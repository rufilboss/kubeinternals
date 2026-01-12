# Kubernetes Cluster Internals

Deep dive into Kubernetes cluster internals, component interactions, and data flows.

## Table of Contents

- [Control Plane Internals](#control-plane-internals)
- [Worker Node Internals](#worker-node-internals)
- [Request Flow](#request-flow)
- [Pod Lifecycle](#pod-lifecycle)
- [Service Discovery](#service-discovery)
- [Storage Internals](#storage-internals)
- [Network Internals](#network-internals)

## Control Plane Internals

### API Server (kube-apiserver)

**Location**: `/etc/kubernetes/manifests/kube-apiserver.yaml`

**Key Responsibilities**:
1. **Authentication**: Verify user identity
2. **Authorization**: Check permissions (RBAC, ABAC)
3. **Admission Control**: Validate and mutate requests
4. **Validation**: Ensure object schemas are correct
5. **Storage**: Read/write to etcd

**Request Flow**:
```
Client Request
    ↓
Authentication
    ↓
Authorization
    ↓
Admission Control
    ↓
Validation
    ↓
etcd (Read/Write)
    ↓
Response
```

**Key Files**:
- Static pod manifest: `/etc/kubernetes/manifests/kube-apiserver.yaml`
- Certificates: `/etc/kubernetes/pki/`
- Audit logs: `/var/log/kubernetes/audit.log`

### etcd

**Location**: `/etc/kubernetes/manifests/etcd.yaml`

**Data Structure**:
```
/registry
  /pods
    /<namespace>
      /<pod-name>
  /services
    /<namespace>
      /<service-name>
  /nodes
    /<node-name>
  /secrets
    /<namespace>
      /<secret-name>
```

**Key Operations**:
- **Write**: All object creates/updates
- **Read**: All object queries
- **Watch**: Real-time change notifications
- **Compact**: Remove old history
- **Defrag**: Reclaim disk space

**Consistency Model**:
- **Linearizable**: All operations appear to execute atomically
- **Quorum**: Majority of nodes must agree
- **Raft Consensus**: Ensures consistency across nodes

### Controller Manager (kube-controller-manager)

**Controllers**:

1. **Node Controller**
   - Monitors node health
   - Handles node failures
   - Updates node status

2. **Replication Controller**
   - Maintains desired replica count
   - Creates/deletes pods as needed

3. **Endpoint Controller**
   - Maintains service endpoints
   - Updates when pods change

4. **Service Account Controller**
   - Creates default service accounts
   - Manages service account tokens

**Control Loop**:
```
Observe Current State
    ↓
Compare with Desired State
    ↓
Take Action (if different)
    ↓
Repeat
```

### Scheduler (kube-scheduler)

**Scheduling Process**:

1. **Filtering**: Remove nodes that can't run the pod
   - Resource constraints
   - Node selectors
   - Taints/tolerations
   - Affinity rules

2. **Scoring**: Rank remaining nodes
   - Resource availability
   - Affinity preferences
   - Anti-affinity rules
   - Custom policies

3. **Binding**: Assign pod to best node

**Scheduling Algorithm**:
```
Pod Created
    ↓
Add to Scheduler Queue
    ↓
Filter Nodes (Feasible)
    ↓
Score Nodes (Priority)
    ↓
Select Best Node
    ↓
Bind Pod to Node
```

## Worker Node Internals

### Kubelet

**Key Responsibilities**:

1. **Pod Management**
   - Create/update/delete pods
   - Monitor pod health
   - Report pod status

2. **Container Runtime Interface (CRI)**
   - Communicate with container runtime
   - Pull images
   - Start/stop containers

3. **Volume Management**
   - Mount volumes
   - Unmount volumes
   - Handle volume plugins

4. **Node Status**
   - Report node conditions
   - Report resource capacity
   - Report allocatable resources

**Kubelet Process**:
```
Watch API Server for Pod Changes
    ↓
Sync Pod State
    ↓
Create/Update Containers
    ↓
Monitor Health
    ↓
Report Status to API Server
```

**Key Files**:
- Kubelet config: `/var/lib/kubelet/config.yaml`
- Pod manifests: `/var/lib/kubelet/pods/`
- Logs: `journalctl -u kubelet`

### Kube-proxy

**Modes**:

1. **iptables Mode** (Default)
   - Creates iptables rules
   - Fast and efficient
   - No userspace overhead

2. **IPVS Mode**
   - Uses IPVS for load balancing
   - Better performance at scale
   - More load balancing algorithms

**Service Proxy Flow**:
```
Service Created
    ↓
kube-proxy Watches API Server
    ↓
Create iptables Rules
    ↓
Route Traffic to Pods
```

**iptables Rules Structure**:
```
PREROUTING
    ↓
KUBE-SERVICES (Service chain)
    ↓
KUBE-SVC-<hash> (Service-specific chain)
    ↓
KUBE-SEP-<hash> (Endpoint chain)
    ↓
Pod IP
```

### Container Runtime

**CRI Interface**:
- **Image Service**: Pull/manage images
- **Runtime Service**: Create/start/stop containers
- **Streaming**: Attach/exec/logs

**Container Lifecycle**:
```
Pull Image
    ↓
Create Container
    ↓
Start Container
    ↓
Monitor Container
    ↓
Stop Container (on termination)
    ↓
Remove Container
```

## Request Flow

### Pod Creation Request

```
1. User: kubectl apply -f pod.yaml
   ↓
2. kubectl: POST /api/v1/namespaces/{namespace}/pods
   ↓
3. API Server: Authenticate & Authorize
   ↓
4. API Server: Validate & Admission Control
   ↓
5. API Server: Write to etcd
   ↓
6. etcd: Store pod object
   ↓
7. API Server: Return success
   ↓
8. Scheduler: Watch for unscheduled pods
   ↓
9. Scheduler: Filter & Score nodes
   ↓
10. Scheduler: Bind pod to node (write to etcd)
    ↓
11. Kubelet: Watch for pods assigned to node
    ↓
12. Kubelet: Create container via CRI
    ↓
13. Container Runtime: Start container
    ↓
14. Kubelet: Report status to API Server
    ↓
15. API Server: Update etcd with pod status
```

### Service Request Flow

```
1. Client Pod: DNS lookup for service
   ↓
2. CoreDNS: Resolve service name to ClusterIP
   ↓
3. Client Pod: Send request to ClusterIP
   ↓
4. iptables: Match KUBE-SERVICES chain
   ↓
5. iptables: Load balance to endpoint
   ↓
6. Request routed to Pod IP
   ↓
7. Pod: Process request
   ↓
8. Response: Reverse path
```

## Pod Lifecycle

### Pod States

```
Pending
    ↓
ContainerCreating
    ↓
Running
    ↓
Succeeded / Failed
```

### Pod Creation Steps

1. **Pending**: Pod accepted, but not scheduled
2. **Scheduling**: Scheduler assigns node
3. **ContainerCreating**: Kubelet creates containers
4. **Running**: All containers started
5. **Ready**: Readiness probe passes

### Container States

- **Waiting**: Container is waiting to start
- **Running**: Container is running
- **Terminated**: Container has stopped

### Termination Flow

```
1. Pod Deletion Requested
   ↓
2. API Server: Set deletionTimestamp
   ↓
3. Kubelet: Receive termination signal
   ↓
4. Kubelet: Send SIGTERM to containers
   ↓
5. Containers: Graceful shutdown (terminationGracePeriodSeconds)
   ↓
6. Kubelet: Force kill if needed (SIGKILL)
   ↓
7. Kubelet: Clean up volumes
   ↓
8. Kubelet: Remove pod from API Server
```

## Service Discovery

### DNS Resolution

**Service DNS Format**:
```
<service-name>.<namespace>.svc.cluster.local
```

**Example**:
```
api-service.production.svc.cluster.local
```

### CoreDNS Configuration

**Corefile**:
```
.:53 {
    errors
    health {
        lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }
    forward . /etc/resolv.conf
    cache 30
    loop
    reload
    loadbalance
}
```

### Endpoint Management

**Endpoints Controller**:
- Watches pods and services
- Creates Endpoints object
- Updates when pods change

**Endpoint Object**:
```yaml
apiVersion: v1
kind: Endpoints
metadata:
  name: api-service
subsets:
- addresses:
  - ip: 10.244.1.5
  - ip: 10.244.2.3
  ports:
  - port: 8080
```

## Storage Internals

### Volume Lifecycle

```
1. Pod Created with Volume
   ↓
2. Kubelet: Wait for volume to be available
   ↓
3. Volume Plugin: Attach volume to node
   ↓
4. Volume Plugin: Mount volume
   ↓
5. Kubelet: Mount volume into pod
   ↓
6. Container: Access volume
   ↓
7. Pod Deleted
   ↓
8. Kubelet: Unmount volume
   ↓
9. Volume Plugin: Detach volume
```

### PersistentVolume (PV) Lifecycle

```
Available
    ↓
Bound (to PVC)
    ↓
Released (PVC deleted)
    ↓
Available (if ReclaimPolicy=Retain)
    or
Deleted (if ReclaimPolicy=Delete)
```

### Storage Classes

**Purpose**: Define storage provisioners and parameters

**Provisioning Flow**:
```
PVC Created
    ↓
Storage Class: Find provisioner
    ↓
Provisioner: Create PV
    ↓
Bind PVC to PV
    ↓
Pod: Use PVC
```

## Network Internals

### Pod Network

**CNI Plugin Responsibilities**:
1. Add network interface to pod
2. Configure IP address
3. Set up routes
4. Configure network policies

### Calico Networking

**Data Plane**:
- Uses BGP for routing
- IP-in-IP encapsulation
- Network policies via iptables

**Control Plane**:
- etcd for network state
- BGP peers for route distribution

### Network Policy Enforcement

```
Traffic Arrives
    ↓
Check Network Policies
    ↓
Match Rules?
    ↓
Allow / Deny
```

**iptables Chains**:
- `cali-fw-*`: Forward chain rules
- `cali-tw-*`: Output chain rules
- `cali-pi-*`: Input chain rules

## Component Communication

### API Server ↔ etcd

- **Protocol**: gRPC
- **Authentication**: mTLS
- **Operations**: Get, List, Watch, Create, Update, Delete

### API Server ↔ Kubelet

- **Protocol**: HTTPS
- **Authentication**: Client certificates
- **Operations**: Status updates, logs, exec, attach

### API Server ↔ Controllers

- **Protocol**: HTTPS
- **Authentication**: Service account tokens
- **Operations**: Watch resources, update objects

### Kubelet ↔ Container Runtime

- **Protocol**: CRI (gRPC)
- **Interface**: Container Runtime Interface
- **Operations**: Image pull, container lifecycle

## Performance Considerations

### API Server

- **Rate Limiting**: Prevent overload
- **Caching**: Reduce etcd load
- **Watch**: Efficient change notifications
- **Pagination**: Large list operations

### etcd

- **Compaction**: Remove old history
- **Defragmentation**: Reclaim disk space
- **Quorum**: Maintain majority
- **Backup**: Regular snapshots

### Scheduler

- **Queue**: Prioritize pods
- **Cache**: Node information
- **Parallelism**: Multiple scheduling threads

### Kubelet

- **Sync Frequency**: How often to sync with API server
- **Container GC**: Clean up stopped containers
- **Image GC**: Clean up unused images

## Debugging Internals

### Component Logs

```bash
# API Server
sudo journalctl -u kubelet | grep kube-apiserver

# etcd
kubectl logs -n kube-system -l component=etcd

# Controller Manager
kubectl logs -n kube-system -l component=kube-controller-manager

# Scheduler
kubectl logs -n kube-system -l component=kube-scheduler

# Kubelet
sudo journalctl -u kubelet -f
```

### etcd Debugging

```bash
# Check etcd data
ETCDCTL_API=3 etcdctl get / --prefix --keys-only

# Watch changes
ETCDCTL_API=3 etcdctl watch /registry/pods --prefix

# Check specific object
ETCDCTL_API=3 etcdctl get /registry/pods/production/api-service-xxx
```

### Network Debugging

```bash
# Check iptables rules
sudo iptables -t nat -L -n | grep KUBE

# Check routes
ip route show

# Check network interfaces
ip addr show
```

## Additional Resources

- [Kubernetes Architecture](https://kubernetes.io/docs/concepts/architecture/)
- [etcd Documentation](https://etcd.io/docs/)
- [CNI Specification](https://github.com/containernetworking/cni)
- [CRI Specification](https://github.com/kubernetes/cri-api)

