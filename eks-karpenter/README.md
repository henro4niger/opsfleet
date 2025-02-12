# EKS Cluster with Karpenter Autoscaling

This Terraform configuration sets up an Amazon EKS cluster with Karpenter for efficient node autoscaling. The configuration prioritizes ARM64 (Graviton) instances and Spot pricing for cost optimization.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- kubectl
- A VPC with at least two private subnets

## Features

- Private or public EKS cluster deployment
- Karpenter autoscaling with:
  - Priority for ARM64 (Graviton) instances
  - Spot instance usage for cost optimization
  - Fallback to x86 instances when needed
- Automatic subnet tagging for EKS and Karpenter
- IRSA (IAM Roles for Service Accounts) enabled


## Usage

1. Initialize Terraform:
```
terraform init
```


2. Create a terraform.tfvars file with your values:
```
egion = "us-west-2"
cluster_name = "my-eks-cluster"
vpc_id = "vpc-xxxxxx"
private_subnet_ids = ["subnet-xxxxxx", "subnet-yyyyyy"]
is_private_cluster = true
```

3. Review the planned changes:

```
terraform plan
```


4. Apply the configuration:
```
terraform apply
```


5. Configure kubectl to interact with your cluster:
```
aws eks update-kubeconfig --region <region> --name <cluster_name>
```


6. Verify Karpenter installation:
```
kubectl get pods -n karpenter
```