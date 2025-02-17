variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "opsfleet-test-cluster"
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster will be created"
  type        = string
  default     = "vpc-02a00502ebd88a427"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
  default     = ["subnet-0bdfc662890f59367", "subnet-080a705d6db263e88"]
}

variable "is_private_cluster" {
  description = "Whether the cluster should be private (true) or public (false)"
  type        = bool
  default     = false
}