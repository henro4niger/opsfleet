# GPU Slicing on Amazon EKS

This document outlines how to implement GPU slicing on Amazon EKS clusters, including those using Karpenter for autoscaling.

## What is GPU Slicing?

GPU slicing allows multiple pods to share a single GPU, enabling better resource utilization and cost optimization. This is implemented through NVIDIA's Multi-Instance GPU (MIG) feature.

Key points:
- Only supported on NVIDIA A100 GPUs
- Enables fractional GPU allocation
- Managed via NVIDIA Device Plugin and MIG Manager
- Compatible with EKS and Karpenter

## Implementation Steps

### 1. Configure Karpenter Provisioner

Create a dedicated provisioner for GPU instances:

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: gpu-provisioner
spec:
  requirements:
    - key: "node.kubernetes.io/instance-type"
      operator: In
      values: ["p4d.24xlarge", "p3.16xlarge"]  # Instance types with NVIDIA A100 GPUs
    - key: "kubernetes.io/arch"
      operator: In
      values: ["amd64"]
    - key: "karpenter.sh/capacity-type"
      operator: In
      values: ["on-demand"]  # GPU workloads typically use on-demand
  limits:
    resources:
      nvidia.com/gpu: 8
  providerRef:
    name: default
  ttlSecondsAfterEmpty: 30
```

### 2. Install Required Components

Install NVIDIA Device Plugin and MIG Manager using Helm:

```bash
helm repo add nvidia https://nvidia.github.io/k8s-device-plugin
helm repo add nvidia-mig https://nvidia.github.io/mig-manager

helm install nvidia-device-plugin nvidia/nvidia-device-plugin \
  --namespace kube-system \
  --set migStrategy=mixed

helm install nvidia-mig-manager nvidia-mig/nvidia-mig-manager \
  --namespace kube-system \
  --set config.default.name=all-1g.5gb
```

### 3. Configure MIG Strategy

Create a ConfigMap to define GPU slicing configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-mig-config
  namespace: kube-system
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 7  # Number of virtual GPUs per physical GPU
```

### 4. Using GPU Slicing in Pods

Example pod specification requesting a fractional GPU:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  containers:
  - name: gpu-container
    image: nvidia/cuda:11.0.3-base-ubuntu20.04
    resources:
      limits:
        nvidia.com/gpu: "0.5"  # Request half a GPU
    command: ["nvidia-smi"]
```

## Available MIG Profiles

The A100 GPU supports several MIG profiles:
- 1g.5gb: 1/7 of GPU (smallest slice)
- 2g.10gb: 2/7 of GPU
- 3g.20gb: 3/7 of GPU
- 4g.40gb: 4/7 of GPU
- 7g.80gb: Full GPU

## Monitoring and Verification

1. Check MIG configuration:
```bash
kubectl exec -it <pod-name> -- nvidia-smi mig -lgi
```

2. Monitor GPU utilization:
```bash
kubectl exec -it <pod-name> -- nvidia-smi
```

3. Verify GPU slicing is working:
```bash
kubectl describe node <node-name> | grep nvidia.com/gpu
```

## Best Practices

1. **Resource Planning**
   - Start with larger GPU slices and adjust based on workload requirements
   - Monitor performance impact of GPU sharing
   - Use node selectors to ensure pods land on GPU nodes

2. **Cost Optimization**
   - Use monitoring tools to track GPU utilization
   - Adjust slice sizes based on actual workload needs
   - Consider using spot instances for fault-tolerant workloads

3. **Performance Considerations**
   - Not all applications are compatible with MIG
   - Test applications thoroughly with GPU slicing
   - Monitor for performance degradation

## Limitations and Considerations

1. **Hardware Requirements**
   - Only works with NVIDIA A100 GPUs
   - Requires specific AWS instance types (p4d.24xlarge)

2. **Application Compatibility**
   - Not all CUDA applications support MIG
   - Some applications may require code modifications

3. **Resource Management**
   - GPU memory is divided along with compute resources
   - Consider memory requirements when planning slices

## Integration with Karpenter

Karpenter automatically manages GPU nodes based on pod requirements:

1. **Node Provisioning**
   - Karpenter recognizes GPU resource requests
   - Automatically provisions appropriate instance types

2. **Scaling**
   - Scales based on aggregated GPU demands
   - Considers both whole and fractional GPU requests

3. **Deprovisioning**
   - Automatically removes underutilized GPU nodes
   - Respects pod disruption budgets

## Troubleshooting

Common issues and solutions:

1. **Pod Pending State**
   - Check node capacity for GPU resources
   - Verify MIG configuration
   - Check pod resource requests

2. **Performance Issues**
   - Monitor GPU utilization
   - Check for resource contention
   - Verify MIG profile compatibility

3. **Device Plugin Issues**
   - Check device plugin logs
   - Verify driver installation
   - Check MIG manager status

## References

- [NVIDIA MIG Documentation](https://docs.nvidia.com/datacenter/tesla/mig-user-guide/)
- [EKS GPU Documentation](https://docs.aws.amazon.com/eks/latest/userguide/gpu-ami.html)
- [Karpenter Documentation](https://karpenter.sh/)
