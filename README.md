# Confluent Platform 8.1 GitOps Demo with Argo CD

Complete GitOps demonstration showing declarative management of the entire Confluent Platform ecosystem using Argo CD and Helm on Kubernetes.

## What This Demo Shows

| Component | GitOps Capability |
|-----------|-------------------|
| **Kafka Cluster (KRaft)** | Declarative broker configuration, scaling, no Zookeeper |
| **Kafka Connect** | Connector CRDs - add/modify connectors via Git |
| **ksqlDB** | Queries as code - SQL stored in Git |
| **Kafka Streams** | Application deployments managed by Argo CD |
| **Content Router** | Content-based routing application (NEW) |
| **Flink** | FlinkApplication CRDs (requires CMF operator) |
| **Schema Registry** | Schema evolution managed alongside code |
| **Control Center** | Monitoring configuration as code |

## Project Structure

```
.
├── charts/
│   └── confluent-platform/           # Helm chart for all components
│       ├── Chart.yaml                # Chart metadata
│       ├── values.yaml               # Base/default values
│       ├── values-dev.yaml           # Development overrides
│       ├── values-prod.yaml          # Production overrides
│       └── templates/                # Helm templates
│           ├── kafka.yaml            # Kafka CRD
│           ├── kraftcontroller.yaml  # KRaft Controller CRD
│           ├── schemaregistry.yaml   # Schema Registry CRD
│           ├── connect.yaml          # Connect CRD
│           ├── connectors.yaml       # Connector CRDs
│           ├── ksqldb.yaml           # ksqlDB CRD
│           ├── ksqldb-queries.yaml   # ksqlDB queries ConfigMap + init Job
│           ├── controlcenter.yaml    # Control Center CRD
│           ├── kstreams-app.yaml     # Kafka Streams Deployment
│           ├── content-router.yaml   # Content Router Deployment (NEW)
│           └── flink.yaml            # Flink resources
├── argocd/
│   ├── project.yaml                  # ArgoCD AppProject
│   └── applications/
│       ├── confluent-platform-dev.yaml   # Dev environment app
│       └── confluent-platform-prod.yaml  # Prod environment app
├── docs/                             # Documentation
├── eks-cluster-config.yaml           # eksctl config for AWS EKS
└── quick-start.sh                    # One-command local setup
```

## Quick Start (Local Development)

```bash
# Ensure Docker Desktop is running, then:
chmod +x quick-start.sh
./quick-start.sh
```

This will:
1. Create a k3d cluster with 3 nodes
2. Install CFK operator
3. Install Argo CD
4. Deploy Confluent Platform 8.1

## Manual Helm Deployment

```bash
# Dev environment (reduced resources)
helm upgrade --install confluent-platform charts/confluent-platform \
  --namespace confluent --create-namespace \
  -f charts/confluent-platform/values.yaml \
  -f charts/confluent-platform/values-dev.yaml

# Prod environment (full resources)
helm upgrade --install confluent-platform charts/confluent-platform \
  --namespace confluent --create-namespace \
  -f charts/confluent-platform/values.yaml \
  -f charts/confluent-platform/values-prod.yaml
```

## AWS EKS Deployment

### Create EKS Cluster

```bash
# Create cluster with proper tagging
eksctl create cluster -f eks-cluster-config.yaml

# Install EBS CSI driver
eksctl create addon --name aws-ebs-csi-driver --cluster cfk-argocd-demo --region us-east-1

# Add EC2 permissions to node role (for EBS)
ROLE_NAME=$(aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-cfk-argocd-demo-nodegroup')].RoleName" --output text)
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
```

### Install Operators

```bash
# CFK Operator
helm repo add confluentinc https://packages.confluent.io/helm
kubectl create namespace confluent-operator
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes \
  --namespace confluent-operator --set namespaced=false

# Argo CD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Deploy via ArgoCD

```bash
# Apply ArgoCD project and application
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applications/confluent-platform-prod.yaml
```

## Components Deployed

### Core Platform (CP 8.1 KRaft Mode)
- **KRaft Controllers** - Metadata management (3 replicas prod, 1 dev)
- **Kafka** - Event streaming (3 brokers prod, 1 dev)
- **Schema Registry** - Schema management
- **Control Center** - Monitoring UI (Next-Gen 2.3.1)

### Data Integration
- **Kafka Connect** - With declarative connector management
  - DataGen connector (users topic)
  - DataGen connector (pageviews topic)
  - DataGen connector (orders topic)
  - DataGen connector (stock-trades topic)
- **ksqlDB** - Stream processing with queries as code

### Stream Processing
- **Kafka Streams** - Sample pageview-enricher application
- **Content Router** - Content-based routing application (disabled by default)
- **Flink** - FlinkApplication for aggregations (requires CMF)

## GitOps Workflow Examples

### 1. Add a New Connector
Edit `charts/confluent-platform/values.yaml`:

```yaml
connectors:
  items:
    - name: my-new-connector
      class: io.confluent.kafka.connect.datagen.DatagenConnector
      taskMax: 1
      topic: my-new-topic
      quickstart: orders
```

Commit, push, watch Argo CD deploy it.

### 2. Scale Kafka Cluster
Edit `charts/confluent-platform/values-prod.yaml`:

```yaml
kafka:
  replicas: 5
```

### 3. Enable Content Router
Edit the appropriate values file:

```yaml
contentRouter:
  enabled: true
  image:
    repository: your-registry/kstream-content-router
    tag: "1.0.0"
  inputTopics:
    - raw-events
  routing:
    inputTopicFormat: AVRO
    inputMessageField: eventType
    rules:
      - regEx: ".*ERROR.*"
        outputTopic: error-events
      - substring: "ORDER"
        outputTopic: order-events
```

### 4. Add ksqlDB Query
Edit `charts/confluent-platform/values.yaml`:

```yaml
ksqldb:
  queries:
    items:
      05-my-aggregation.sql: |
        CREATE TABLE my_aggregation AS
        SELECT key, COUNT(*) as cnt
        FROM my_stream
        GROUP BY key;
```

## Environment Comparison

| Setting | Dev (k3d) | Prod (EKS/AKS) |
|---------|-----------|----------------|
| KRaft replicas | 1 | 3 |
| Kafka replicas | 1 | 3 |
| Kafka storage | 10Gi | 100Gi |
| Connect workers | 1 | 2 |
| ksqlDB replicas | 1 | 2 |
| Flink | Enabled | Enabled |

## Accessing Services

### Control Center
```bash
kubectl port-forward controlcenter-0 9021:9021 -n confluent
# http://localhost:9021
```

### Argo CD
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080
# Username: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### ksqlDB CLI
```bash
kubectl exec -it ksqldb-0 -n confluent -- ksql http://localhost:8088
```

## Troubleshooting

### Pods Pending
```bash
kubectl describe pod <pod> -n confluent
# Check PVC binding, resource limits
```

### Connector Not Creating
```bash
kubectl get connector -n confluent
kubectl describe connector <name> -n confluent
kubectl logs -l app=connect -n confluent
```

### Argo CD Out of Sync
```bash
# Force sync
kubectl patch application confluent-platform-prod -n argocd \
  --type merge -p '{"operation": {"sync": {}}}'
```

### Validate Helm Templates
```bash
# Lint the chart
helm lint charts/confluent-platform

# Render templates to check output
helm template test charts/confluent-platform \
  -f charts/confluent-platform/values.yaml \
  -f charts/confluent-platform/values-dev.yaml
```

## Cleanup

```bash
# Delete ArgoCD application
kubectl delete application confluent-platform-prod -n argocd

# Delete via Helm
helm uninstall confluent-platform -n confluent

# Delete local cluster
k3d cluster delete cfk-demo

# Delete EKS cluster
eksctl delete cluster --name cfk-argocd-demo --region us-east-1
```

## Technologies

- **Confluent Platform 8.1** - Apache Kafka with KRaft mode
- **CFK 3.1** - Confluent for Kubernetes operator
- **Argo CD** - GitOps continuous delivery
- **Helm** - Kubernetes package manager
- **k3d** - Local Kubernetes (development)
- **AWS EKS** - Production Kubernetes

## References

- [CFK Documentation](https://docs.confluent.io/operator/current/overview.html)
- [Declarative Connectors](https://www.confluent.io/blog/declarative-connectors-with-confluent-for-kubernetes/)
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Helm Documentation](https://helm.sh/docs/)
