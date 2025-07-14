#!/bin/bash

# Kubernetes Storage Performance Testing Setup Script
set -e

echo "🚀 Setting up Kubernetes Storage Performance Testing Environment"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

print_success "Connected to Kubernetes cluster"

# Get cluster info
CLUSTER_INFO=$(kubectl cluster-info | head -1)
print_status "Cluster: $CLUSTER_INFO"

# Create namespace for testing
NAMESPACE="storage-performance-test"
print_status "Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Set default namespace
kubectl config set-context --current --namespace=$NAMESPACE

# Create directories on nodes (for local storage)
print_status "Setting up storage directories on nodes..."

# Get node names
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
print_status "Found nodes: $NODES"

# Create a job to setup directories on each node
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: setup-storage-dirs
  namespace: $NAMESPACE
spec:
  template:
    spec:
      hostNetwork: true
      hostPID: true
      restartPolicy: Never
      containers:
      - name: setup
        image: busybox
        command: ["/bin/sh"]
        args:
        - -c
        - |
          echo "Setting up storage directories..."
          mkdir -p /host/tmp/k8s-storage-test
          mkdir -p /host/mnt/local-storage
          mkdir -p /host/tmp/k8s-benchmark-results
          chmod 777 /host/tmp/k8s-storage-test
          chmod 777 /host/mnt/local-storage
          chmod 777 /host/tmp/k8s-benchmark-results
          echo "Storage directories created successfully"
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-root
          mountPath: /host
      volumes:
      - name: host-root
        hostPath:
          path: /
      nodeSelector:
        kubernetes.io/os: linux
EOF

# Wait for setup job to complete
print_status "Waiting for storage directory setup to complete..."
kubectl wait --for=condition=complete job/setup-storage-dirs --timeout=60s

# Clean up setup job
kubectl delete job setup-storage-dirs

print_success "Storage directories setup completed"

# Update local-pv.yaml with actual node names
print_status "Updating local PV configuration with actual node names..."
FIRST_NODE=$(echo $NODES | awk '{print $1}')
sed -i.bak "s/minikube/$FIRST_NODE/g" ../storage-configs/local-pv.yaml
print_status "Updated local-pv.yaml to use node: $FIRST_NODE"

# Apply storage configurations
print_status "Applying storage configurations..."
kubectl apply -f ../storage-configs/

# Wait for PVs to be available
print_status "Waiting for Persistent Volumes to be ready..."
sleep 5

# Check PV status
kubectl get pv
kubectl get pvc

print_success "Environment setup completed!"
print_status "Next steps:"
echo "  1. Run performance tests: ./run-performance-tests.sh"
echo "  2. Monitor tests: kubectl get jobs -w"
echo "  3. Analyze results: ./analyze-results.sh"
echo ""
print_status "Namespace: $NAMESPACE"
print_status "Results will be stored in: /tmp/k8s-benchmark-results"
