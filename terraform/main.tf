locals {
  tags = {
    created-by   = "personal-eks-workshop"
    cluster_name = var.cluster_name
  }
}



locals {
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 3, k + 3)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 3, k)]
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)



  network_acls = {
    default_inbound = [
      {
        rule_number = 50
        rule_action = "allow"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_block  = module.vpc.vpc_cidr_block # our own VPC!
      },
      {
        rule_number = 51
        rule_action = "allow"
        from_port   = 1024
        to_port     = 65535
        protocol    = "tcp"
        cidr_block  = "0.0.0.0/0" # Ephemeral ports Allows inbound return IPv4 traffic from the internet (that is, for requests that originate in the subnet).
      },
      {
        rule_number = 60
        rule_action = "allow"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_block  = var.cidr_passlist
      },
      {
        rule_number = 600
        rule_action = "deny"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_block  = "0.0.0.0/0"
      },
      {
        rule_number     = 601
        rule_action     = "deny"
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        ipv6_cidr_block = "::/0"
      },
    ]


    # default_outbound_acl_rules = [
    #   {
    #     rule_number = 100
    #     rule_action = "allow"
    #     from_port   = 0
    #     to_port     = 0
    #     protocol    = "-1"
    #     cidr_block  = "0.0.0.0/0"
    #   },
    #   {
    #     rule_number     = 110
    #     rule_action     = "allow"
    #     from_port       = 0
    #     to_port         = 0
    #     protocol        = "-1"
    #     ipv6_cidr_block = "::/0"
    #   },
    # ]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.18.1"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs                   = local.azs
  public_subnets        = local.public_subnets
  private_subnets       = local.private_subnets
  public_subnet_suffix  = "SubnetPublic"
  private_subnet_suffix = "SubnetPrivate"

  enable_nat_gateway   = true
  create_igw           = true
  enable_dns_hostnames = true
  single_nat_gateway   = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${var.cluster_name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${var.cluster_name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${var.cluster_name}-default" }

  public_dedicated_network_acl = true
  public_inbound_acl_rules     = local.network_acls["default_inbound"]

  public_subnet_tags = merge(local.tags, {
    "kubernetes.io/role/elb" = "1"
  })
  private_subnet_tags = merge(local.tags, {
    "kubernetes.io/role/internal-elb" = "1",
    "karpenter.sh/discovery"          = var.cluster_name
  })

  tags = merge(local.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  })
}
