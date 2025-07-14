#!/bin/bash

# Kubernetes Storage Performance Testing Runner Script
set -e

echo "🧪 Running Kubernetes Storage Performance Tests"

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

# Set namespace
NAMESPACE="storage-performance-test"
kubectl config set-context --current --namespace=$NAMESPACE

# Check if setup was completed
if ! kubectl get pv hostpath-pv &> /dev/null; then
    print_error "Storage setup not found. Please run ./setup-environment.sh first"
    exit 1
fi

print_status "Starting performance tests..."

# Clean up any existing benchmark jobs
print_status "Cleaning up previous test runs..."
kubectl delete jobs -l app=fio-benchmark --ignore-not-found=true
sleep 5

# Apply benchmark configurations
print_status "Deploying benchmark jobs..."
kubectl apply -f ../benchmarks/fio-benchmark.yaml

# List of jobs to monitor
JOBS=("fio-benchmark-hostpath" "fio-benchmark-local" "fio-benchmark-emptydir")

print_status "Benchmark jobs started:"
for job in "${JOBS[@]}"; do
    echo "  - $job"
done

# Function to check job status
check_job_status() {
    local job_name=$1
    local status=$(kubectl get job $job_name -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "NotFound")
    echo $status
}

# Function to get job logs
get_job_logs() {
    local job_name=$1
    local pod_name=$(kubectl get pods -l job-name=$job_name -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ ! -z "$pod_name" ]; then
        kubectl logs $pod_name
    fi
}

# Monitor job progress
print_status "Monitoring job progress (this may take several minutes)..."
echo "Press Ctrl+C to stop monitoring (jobs will continue running)"

# Create a monitoring loop
monitor_jobs() {
    local all_completed=false
    local check_interval=30
    
    while [ "$all_completed" = false ]; do
        echo ""
        print_status "Job Status Check - $(date)"
        echo "----------------------------------------"
        
        local completed_count=0
        
        for job in "${JOBS[@]}"; do
            local status=$(check_job_status $job)
            local pod_status=$(kubectl get pods -l job-name=$job -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
            
            if [ "$status" = "True" ]; then
                echo "✅ $job: COMPLETED"
                ((completed_count++))
            elif [ "$pod_status" = "Running" ]; then
                echo "🔄 $job: RUNNING"
            elif [ "$pod_status" = "Pending" ]; then
                echo "⏳ $job: PENDING"
            else
                echo "❓ $job: $pod_status"
            fi
        done
        
        if [ $completed_count -eq ${#JOBS[@]} ]; then
            all_completed=true
            print_success "All benchmark jobs completed!"
        else
            print_status "Waiting $check_interval seconds before next check..."
            sleep $check_interval
        fi
    done
}

# Start monitoring in background and allow user to continue
monitor_jobs &
MONITOR_PID=$!

# Trap to clean up background process
trap "kill $MONITOR_PID 2>/dev/null || true" EXIT

# Wait for monitoring to complete or user interrupt
wait $MONITOR_PID 2>/dev/null || true

# Show final status
echo ""
print_status "Final Job Status:"
kubectl get jobs

# Show pod status
echo ""
print_status "Pod Status:"
kubectl get pods

# Check for any failed jobs
FAILED_JOBS=$(kubectl get jobs -o jsonpath='{.items[?(@.status.failed>0)].metadata.name}')
if [ ! -z "$FAILED_JOBS" ]; then
    print_warning "Some jobs failed: $FAILED_JOBS"
    print_status "Check logs with: kubectl logs -l job-name=<job-name>"
fi

print_success "Performance tests completed!"
print_status "Next steps:"
echo "  1. Analyze results: ./analyze-results.sh"
echo "  2. View raw results: ls -la /tmp/k8s-benchmark-results/"
echo "  3. Check job logs: kubectl logs -l app=fio-benchmark"
echo ""
print_status "To clean up: kubectl delete jobs -l app=fio-benchmark"
