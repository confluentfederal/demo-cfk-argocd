# KRaft + Argo CD: Considerations for Non-CFK Deployments

## Overview

When deploying Apache Kafka in KRaft mode with Argo CD **without** Confluent for Kubernetes (CFK), there are several configuration challenges that must be addressed to ensure stability during GitOps-driven updates.

## The Core Problem

KRaft controller quorum requires stable node identities. When Argo CD triggers a sync or rollout:
1. Pods may be deleted and recreated
2. New pods receive new IP addresses
3. If configurations reference IPs instead of DNS names, the quorum breaks

## Key Requirements

### 1. Use DNS Hostnames, Not Pod IPs

**Wrong (will break on restart):**
```properties
controller.quorum.voters=1@10.244.0.5:9093,2@10.244.0.6:9093,3@10.244.0.7:9093
```

**Correct (stable across restarts):**
```properties
controller.quorum.voters=1@kraft-0.kraft-headless.kafka.svc.cluster.local:9093,2@kraft-1.kraft-headless.kafka.svc.cluster.local:9093,3@kraft-2.kraft-headless.kafka.svc.cluster.local:9093
```

### 2. Create Headless Services

StatefulSet pods need a headless service for stable DNS:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kraft-headless
  namespace: kafka
spec:
  clusterIP: None  # Headless
  selector:
    app: kraft
  ports:
    - name: controller
      port: 9093
```

This enables DNS names like: `kraft-0.kraft-headless.kafka.svc.cluster.local`

### 3. Use StatefulSets (Not Deployments)

KRaft controllers and Kafka brokers **must** use StatefulSets:
- Provides stable network identities (`pod-0`, `pod-1`, etc.)
- Provides stable storage (PVCs are retained)
- Provides ordered, graceful deployment/scaling

### 4. Configure Advertised Listeners Correctly

Each broker must advertise its stable DNS name:

```properties
# In kafka-0's config:
advertised.listeners=PLAINTEXT://kafka-0.kafka-headless.kafka.svc.cluster.local:9092
```

Use a ConfigMap with per-pod configuration or environment variable substitution.

### 5. Argo CD Sync Strategy

Configure Argo CD to avoid simultaneous pod restarts:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
    # Avoid replacing StatefulSets
    managedNamespaceMetadata:
      labels:
        argocd.argoproj.io/managed-by: argocd
```

For StatefulSets, use `OnDelete` or `RollingUpdate` with `partition`:

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0  # Update one pod at a time
```

### 6. Pod Disruption Budgets

Prevent Argo CD or cluster operations from disrupting quorum:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: kraft-pdb
spec:
  minAvailable: 2  # Maintain quorum (majority of 3)
  selector:
    matchLabels:
      app: kraft
```

### 7. Cluster ID Consistency

KRaft requires a consistent cluster ID across all nodes. Generate once and store in a Secret:

```bash
kafka-storage.sh random-uuid > cluster-id.txt
kubectl create secret generic kraft-cluster-id --from-file=cluster-id.txt
```

Format storage with the same ID on all nodes:

```bash
kafka-storage.sh format -t $(cat /etc/kafka/cluster-id) -c /etc/kafka/kraft.properties
```

### 8. Init Containers for Ordering

Ensure KRaft controllers are ready before brokers start:

```yaml
initContainers:
  - name: wait-for-kraft
    image: busybox
    command:
      - sh
      - -c
      - |
        until nc -z kraft-0.kraft-headless.kafka.svc.cluster.local 9093; do
          echo "Waiting for KRaft controller..."
          sleep 5
        done
```

## Common Failure Modes

| Issue | Symptom | Solution |
|-------|---------|----------|
| IP-based quorum config | Quorum lost after pod restart | Use DNS hostnames |
| Missing headless service | DNS resolution fails | Create headless service |
| Using Deployment instead of StatefulSet | No stable identity | Switch to StatefulSet |
| All pods restart at once | Complete cluster outage | Use PodDisruptionBudget |
| Inconsistent cluster ID | Nodes refuse to join | Use shared Secret for cluster ID |
| Brokers start before controllers | Broker fails to register | Add init container dependency |

## CFK Advantages

Confluent for Kubernetes handles all of this automatically:
- Creates headless services
- Uses StatefulSets with proper update strategies
- Configures DNS-based listeners and quorum voters
- Manages cluster ID consistently
- Handles dependency ordering between components
- Sets appropriate PodDisruptionBudgets

## Recommendation

For production KRaft deployments with Argo CD:
1. **Use CFK** if possible - it handles all edge cases
2. If manual deployment is required, implement all items above
3. Test Argo CD sync operations in staging before production
4. Monitor quorum health during any GitOps-triggered changes

## References

- [KRaft Configuration](https://kafka.apache.org/documentation/#kraft)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Argo CD Sync Options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)
