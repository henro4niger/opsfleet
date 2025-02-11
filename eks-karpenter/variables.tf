variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "opsfleet-test-cluster"
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster will be created"
  type        = string
  default     = "isf34352343"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
  default     = ["sub-afdjfdk45454", "sub-454dgf"]
}

variable "is_private_cluster" {
  description = "Whether the cluster should be private (true) or public (false)"
  type        = bool
  default     = true
}