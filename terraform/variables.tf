variable "cidr_passlist" {
  description = "CIDR block to allow all traffic from"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "personal-eks-workshop"
}

variable "eks_managed_node_groups" {
  type = object({
    min_size     = number # 3 
    max_size     = number # 6
    desired_size = number # 3
  })
  default = {
    desired_size = 1
    min_size     = 1
    max_size     = 4
  }
}


variable "tf_state" {
  description = "Terraform state file configuration"
  type = object({
    bucket = string
    key    = string
    region = string
  })
}

variable "vpc_cidr" {
  description = "Defines the CIDR block used on Amazon VPC created for Amazon EKS."
  type        = string
  default     = "10.42.0.0/16"
}
