# Kubernetes Cluster Architecture

## Overview

This document provides a detailed explanation of the Kubernetes cluster architecture built in this project, including component interactions, data flows, and design decisions.

## Cluster Topology

### Control Plane Components

The control plane is the brain of the Kubernetes cluster, responsible for maintaining the desired state of the cluster.

#### 1. API Server (kube-apiserver)

- **Role**: Central management point for the cluster
- **Responsibilities**:
  - Validates and processes all API requests
  - Manages authentication and authorization
  - Maintains cluster state in etcd
  - Serves as the front-end for the control plane

**Key Configuration**:
- Audit logging enabled for compliance
- Bind address: `0.0.0.0` (accessible from all interfaces)
- Port: `6443` (HTTPS)

#### 2. etcd

- **Role**: Distributed key-value store
- **Responsibilities**:
  - Stores all cluster data (pods, services, configs, secrets)
  - Provides consistency and availability guarantees
  - Single node in this setup (production should use HA)

**Data Stored**:
- Cluster state
- Configuration objects
- Secrets and ConfigMaps
- Service endpoints

**Backup Strategy**:
- Automated backups every 5 minutes
- Manual backups before major operations
- Retention: 7 days

#### 3. Controller Manager (kube-controller-manager)

- **Role**: Runs controller processes
- **Controllers**:
  - Node Controller
  - Replication Controller
  - Endpoints Controller
  - Service Account & Token Controllers

**Responsibilities**:
- Monitor cluster state
- Make changes to move current state toward desired state
- Handle node failures, pod replication, etc.

#### 4. Scheduler (kube-scheduler)

- **Role**: Assigns pods to nodes
- **Responsibilities**:
  - Watches for newly created pods
  - Selects optimal node based on:
    - Resource requirements
    - Affinity/anti-affinity rules
    - Taints and tolerations
    - Node availability

### Worker Node Components

#### 1. Kubelet

- **Role**: Primary node agent
- **Responsibilities**:
  - Manages pod lifecycle
  - Reports node and pod status to API server
  - Mounts volumes
  - Executes container health checks

#### 2. Kube-proxy

- **Role**: Network proxy
- **Responsibilities**:
  - Maintains network rules on nodes
  - Enables service discovery
  - Load balancing for services
  - Uses iptables mode for performance

#### 3. Container Runtime

- **Runtime**: containerd
- **Responsibilities**:
  - Pulling container images
  - Running containers
  - Managing container lifecycle

## Network Architecture

### Pod Network

- **CNI Plugin**: Calico
- **Pod CIDR**: `10.244.0.0/16`
- **Service CIDR**: `10.96.0.0/12`

### Service Discovery

- **DNS**: CoreDNS (default)
- **Service Types**:
  - ClusterIP: Internal cluster access
  - NodePort: External access via node IP
  - LoadBalancer: Cloud provider integration

## Application Architecture

### API Service

```
┌─────────────────────────────────────┐
│         API Service Pods            │
│  ┌──────────┐  ┌──────────┐        │
│  │   Pod 1  │  │   Pod 2  │  ...   │
│  └──────────┘  └──────────┘        │
└─────────────────────────────────────┘
           │              │
           ▼              ▼
    ┌──────────┐   ┌──────────┐
    │  Redis   │   │PostgreSQL│
    └──────────┘   └──────────┘
```

**Characteristics**:
- **Replicas**: 3 (high availability)
- **Resource Limits**: CPU 500m, Memory 512Mi
- **Health Checks**: Liveness and readiness probes
- **Strategy**: Rolling update (zero downtime)

### Worker Service

**Characteristics**:
- **Replicas**: 2
- **Resource Limits**: CPU 1000m, Memory 1Gi
- **Queue Integration**: Redis-based job queue
- **Graceful Shutdown**: 60-second termination grace period

### Stateful Services

#### Redis

- **Type**: StatefulSet
- **Storage**: 10Gi PVC
- **Persistence**: AOF (Append Only File)
- **Memory Policy**: LRU eviction

#### PostgreSQL

- **Type**: StatefulSet
- **Storage**: 20Gi PVC
- **Backup**: Automated daily backups
- **Credentials**: Kubernetes Secrets

## Data Flow

### Pod Creation Flow

1. User submits pod spec via `kubectl`
2. API Server validates and stores in etcd
3. Scheduler assigns pod to node
4. Kubelet on target node creates pod
5. Container runtime starts containers
6. Kubelet reports status back to API server

### Service Discovery Flow

1. Service created with ClusterIP
2. kube-proxy creates iptables rules
3. CoreDNS creates DNS record
4. Pods resolve service via DNS name
5. Traffic routed via iptables rules

## High Availability Considerations

### Current Setup (Single Control Plane)

- **Risk**: Single point of failure
- **Impact**: Complete cluster unavailability if control plane fails
- **Mitigation**: Regular etcd backups, documented recovery procedures

### Production Recommendations

1. **HA Control Plane**: 3+ control plane nodes
2. **etcd Cluster**: 3+ etcd nodes with quorum
3. **Load Balancer**: For API server access
4. **Multi-AZ**: Distribute nodes across availability zones
5. **Monitoring**: Real-time alerts for component health

## Resource Management

### Resource Quotas

- **Namespace**: `production`
- **CPU Request**: Sum of all pod requests
- **Memory Request**: Sum of all pod requests
- **Storage**: PVC-based for stateful services

### Limit Ranges

- **Default CPU Request**: 100m
- **Default Memory Request**: 128Mi
- **Default CPU Limit**: 500m
- **Default Memory Limit**: 512Mi

## Security Considerations

### Network Policies

- **Default**: Allow all (for simplicity)
- **Production**: Implement least-privilege policies

### RBAC

- **Service Accounts**: Per-namespace
- **Role Bindings**: Least privilege access

### Secrets Management

- **Storage**: Kubernetes Secrets (base64 encoded)
- **Production**: Use external secret management (Vault, AWS Secrets Manager)

## Monitoring Points

### Control Plane Health

- API server response time
- etcd latency and quorum status
- Scheduler queue depth
- Controller manager error rates

### Node Health

- Kubelet heartbeat
- Node resource utilization
- Pod eviction rates
- Container runtime status

### Application Health

- Pod readiness
- Service endpoint availability
- Application metrics (latency, errors)
- Resource consumption

## Disaster Recovery

### Backup Strategy

1. **etcd Backups**: Every 5 minutes
2. **PVC Snapshots**: Daily for stateful services
3. **Configuration**: Git-versioned manifests
4. **Secrets**: External secret management

### Recovery Procedures

See [recovery-procedures.md](recovery-procedures.md) for detailed steps.

## Scaling Considerations

### Horizontal Pod Autoscaling (HPA)

- **Metrics**: CPU, Memory, Custom
- **Min Replicas**: 2
- **Max Replicas**: 10

### Vertical Pod Autoscaling (VPA)

- **Recommendations**: Based on historical usage
- **Update Mode**: Auto or Off

### Cluster Autoscaling

- **Node Autoscaler**: Add/remove nodes based on demand
- **Pod Disruption Budgets**: Maintain availability during scaling

## Performance Optimization

### API Server

- **Audit Logging**: Rotate logs regularly
- **Rate Limiting**: Configure appropriate limits
- **Caching**: Enable watch caching

### etcd

- **Compaction**: Regular history compaction
- **Defragmentation**: Periodic defragmentation
- **Quorum**: Maintain odd number of nodes

### Network

- **CNI Plugin**: Calico for performance
- **Service Proxy**: iptables mode (vs userspace)
- **DNS**: CoreDNS with caching

## Troubleshooting Architecture

### Log Aggregation

- **Control Plane**: `/var/log/kubernetes/`
- **Kubelet**: `journalctl -u kubelet`
- **Containers**: `kubectl logs`

### Debugging Tools

- `kubectl describe`: Resource details
- `kubectl get events`: Cluster events
- `kubectl top`: Resource usage
- `kubectl debug`: Interactive debugging

## Future Enhancements

1. **Service Mesh**: Istio or Linkerd
2. **Ingress Controller**: NGINX or Traefik
3. **Monitoring Stack**: Prometheus + Grafana
4. **Logging Stack**: ELK or Loki
5. **GitOps**: ArgoCD or Flux
6. **Policy Engine**: OPA Gatekeeper

