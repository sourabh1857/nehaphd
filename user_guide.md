# Kubernetes Storage Performance Analysis - Usage Guide

This comprehensive guide will walk you through using the Kubernetes Storage Performance Analysis toolkit to benchmark and analyze local storage performance in your Kubernetes cluster.

## Prerequisites

Before starting, ensure you have:

- **Kubernetes cluster** (minikube, kind, or full cluster)
- **kubectl** configured and connected to your cluster
- **Sufficient permissions** to create namespaces, persistent volumes, and jobs
- **Available storage space** on cluster nodes (at least 10GB recommended)

## Quick Start

### 1. Setup Environment

Navigate to the scripts directory and run the setup script:

```bash
cd k8s-storage-performance/scripts
./setup-environment.sh
```

This script will:
- Create a dedicated namespace (`storage-performance-test`)
- Set up required directories on cluster nodes
- Deploy storage configurations (PVs, PVCs, StorageClasses)
- Verify the environment is ready for testing

### 2. Run Performance Tests

Execute the performance testing suite:

```bash
./run-performance-tests.sh
```

This will:
- Deploy FIO benchmark jobs for different storage types
- Monitor job progress in real-time
- Test HostPath, Local PV, and EmptyDir storage types
- Run multiple test scenarios (random I/O, sequential I/O, mixed workloads)

### 3. Analyze Results

Once tests complete, analyze the results:

```bash
./analyze-results.sh
```

This generates:
- Detailed performance summary report
- CSV data for further analysis
- Comparison between storage types
- Recommendations based on results

## Detailed Usage

### Storage Types Tested

#### 1. HostPath Storage
- **Description**: Direct access to host filesystem
- **Use Case**: Development, testing, single-node clusters
- **Pros**: Simple setup, good performance
- **Cons**: Not portable across nodes

#### 2. Local Persistent Volumes
- **Description**: Kubernetes-managed local storage
- **Use Case**: Production workloads requiring local storage
- **Pros**: Proper lifecycle management, node affinity
- **Cons**: Tied to specific nodes

#### 3. EmptyDir Storage
- **Description**: Temporary storage tied to pod lifecycle
- **Use Case**: Caching, temporary data processing
- **Pros**: Fast (often memory-backed), automatic cleanup
- **Cons**: Data lost when pod terminates

### Test Scenarios

#### Random I/O Test
- **Block Size**: 4KB
- **Pattern**: Random read/write
- **Jobs**: 4 concurrent
- **Duration**: 60 seconds
- **Measures**: IOPS, latency for small random operations

#### Sequential I/O Test
- **Block Size**: 1MB
- **Pattern**: Sequential read/write
- **Jobs**: 1 per operation
- **Duration**: 60 seconds
- **Measures**: Throughput for large sequential operations

#### Mixed Workload Test
- **Block Size**: 4KB
- **Pattern**: 70% read, 30% write
- **Jobs**: 2 concurrent
- **Duration**: 60 seconds
- **Measures**: Real-world mixed workload performance

### Understanding Results

#### Key Metrics

1. **IOPS (Input/Output Operations Per Second)**
   - Higher is better
   - Important for databases, small file operations
   - Typical ranges:
     - HDD: 100-200 IOPS
     - SSD: 1,000-100,000+ IOPS
     - NVMe: 10,000-1,000,000+ IOPS

2. **Throughput (MB/s)**
   - Higher is better
   - Important for large file transfers, streaming
   - Depends on storage medium and interface

3. **Latency (microseconds)**
   - Lower is better
   - Critical for real-time applications
   - Affects user experience and application responsiveness

#### Performance Comparison

| Storage Type | IOPS | Throughput | Latency | Use Case |
|--------------|------|------------|---------|----------|
| EmptyDir | Highest | Highest | Lowest | Temporary/Cache |
| HostPath | High | High | Low | Development |
| Local PV | High | High | Low | Production |

### Advanced Usage

#### Custom Test Configuration

Modify `benchmarks/fio-benchmark.yaml` to customize tests:

```yaml
# Example: Increase test duration
runtime=300  # 5 minutes instead of 60 seconds

# Example: Change block size
bs=8k  # 8KB instead of 4KB

# Example: Adjust concurrency
numjobs=8  # 8 jobs instead of 4
```

#### Testing Real Workloads

Deploy sample applications to test with realistic workloads:

```bash
kubectl apply -f examples/sample-workload.yaml
```

This includes:
- PostgreSQL database with pgbench load testing
- File I/O intensive workload
- Log processing workload

#### Monitoring Setup

Deploy Prometheus and Grafana for continuous monitoring:

```bash
kubectl apply -f monitoring/prometheus-monitoring.yaml
```

Access monitoring:
```bash
# Port forward Grafana
kubectl port-forward svc/grafana 3000:3000

# Port forward Prometheus
kubectl port-forward svc/prometheus 9090:9090
```

### Troubleshooting

#### Common Issues

1. **Permission Denied**
   ```bash
   # Ensure scripts are executable
   chmod +x scripts/*.sh
   ```

2. **Storage Setup Failed**
   ```bash
   # Check node names and update local-pv.yaml
   kubectl get nodes
   # Edit storage-configs/local-pv.yaml with correct node names
   ```

3. **Jobs Stuck in Pending**
   ```bash
   # Check PVC status
   kubectl get pvc
   
   # Check events
   kubectl get events --sort-by=.metadata.creationTimestamp
   ```

4. **No Results Generated**
   ```bash
   # Check job logs
   kubectl logs -l app=fio-benchmark
   
   # Verify results directory
   ls -la /tmp/k8s-benchmark-results/
   ```

#### Debugging Commands

```bash
# Check cluster status
kubectl cluster-info

# List all resources in test namespace
kubectl get all -n storage-performance-test

# Check storage resources
kubectl get pv,pvc,sc

# Monitor job progress
kubectl get jobs -w

# Check pod logs
kubectl logs <pod-name>

# Describe problematic resources
kubectl describe pvc <pvc-name>
kubectl describe job <job-name>
```

### Cleanup

#### Remove Test Resources

```bash
# Delete all jobs
kubectl delete jobs -l app=fio-benchmark

# Delete sample workloads
kubectl delete -f examples/sample-workload.yaml

# Delete monitoring stack
kubectl delete -f monitoring/prometheus-monitoring.yaml

# Delete entire namespace (removes everything)
kubectl delete namespace storage-performance-test
```

#### Clean Host Directories

```bash
# Remove test directories (run on each node)
sudo rm -rf /tmp/k8s-storage-test
sudo rm -rf /mnt/local-storage
sudo rm -rf /tmp/k8s-benchmark-results
```

## Best Practices

### Before Testing

1. **Baseline the system** - Run tests on idle cluster
2. **Document environment** - Note hardware, OS, Kubernetes version
3. **Plan test duration** - Longer tests provide more accurate results
4. **Consider resource limits** - Ensure tests don't impact other workloads

### During Testing

1. **Monitor system resources** - Watch CPU, memory, network usage
2. **Run multiple iterations** - Average results across multiple runs
3. **Test different scenarios** - Vary block sizes, concurrency levels
4. **Document conditions** - Note any concurrent workloads or issues

### After Testing

1. **Archive results** - Save raw data and analysis reports
2. **Compare over time** - Track performance changes
3. **Share findings** - Document insights for team
4. **Plan improvements** - Identify optimization opportunities

## Integration with CI/CD

### Automated Testing

Create a pipeline stage for storage performance testing:

```yaml
# Example GitLab CI stage
storage-performance-test:
  stage: test
  script:
    - cd k8s-storage-performance/scripts
    - ./setup-environment.sh
    - ./run-performance-tests.sh
    - ./analyze-results.sh
  artifacts:
    paths:
      - k8s-storage-performance/results/
    expire_in: 1 week
  only:
    - schedules  # Run on scheduled pipelines
```

### Performance Regression Detection

Set up alerts for performance degradation:

```bash
# Example: Alert if IOPS drops below threshold
if [ "$current_iops" -lt "$baseline_iops" ]; then
  echo "Performance regression detected!"
  exit 1
fi
```

## Next Steps

1. **Customize for your environment** - Adjust configurations for your specific needs
2. **Integrate with monitoring** - Set up continuous performance tracking
3. **Automate testing** - Include in CI/CD pipelines
4. **Expand testing** - Add network storage, different workload patterns
5. **Optimize based on results** - Use findings to improve storage configuration

For more advanced configurations and troubleshooting, refer to the individual component documentation in each directory.
