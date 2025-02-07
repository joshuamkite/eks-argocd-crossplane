variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "personal-eks-workshop"
}

# variable "cluster_version" {
#   description = "EKS cluster version."
#   type        = string
#   default     = "1.29"
# }

# variable "ami_release_version" {
#   description = "Default EKS AMI release version for node groups"
#   type        = string
#   default     = "1.29.0-20240129"
# }

variable "vpc_cidr" {
  description = "Defines the CIDR block used on Amazon VPC created for Amazon EKS."
  type        = string
  default     = "10.42.0.0/16"
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

variable "cidr_passlist" {}
