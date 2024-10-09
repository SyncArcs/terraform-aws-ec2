##==================================================================
## Provider block added, Use the Amazon Web Services (AWS) provider to interact with the many resources supported by AWS.
##====================================================================

provider "aws" {
  region = "us-east-1"
}

locals {
  environment = "app"
  label_order = ["name", "environment"]
}

##======================================================================================
## A VPC is a virtual network that closely resembles a traditional network that you'd operate in your own data center.
##=====================================================================================
module "vpc" {
  source      = "git::https://github.com/SyncArcs/terraform-aws-vpc.git?ref=v1.0.0"
  name        = "app"
  environment = local.environment
  label_order = local.label_order
  cidr_block  = "172.16.0.0/16"
}

##=======================================================================
## A subnet is a range of IP addresses in your VPC.
##========================================================================
module "public_subnets" {
  source             = "git::https://github.com/SyncArcs/terraform-aws-subnet.git?ref=v1.0.0"
  name               = "public-subnet"
  environment        = local.environment
  label_order        = local.label_order
  availability_zones = ["us-east-1a", "us-east-1b"]
  vpc_id             = module.vpc.id
  cidr_block         = module.vpc.vpc_cidr_block
  type               = "public"
  igw_id             = module.vpc.igw_id
  ipv6_cidr_block    = module.vpc.ipv6_cidr_block
}

module "iam-role" {
  source             = "git::https://github.com/SyncArcs/terraform-aws-iam-role.git?ref=v1.0.0"
  name               = "iam-role"
  environment        = local.environment
  label_order        = local.label_order
  assume_role_policy = data.aws_iam_policy_document.default.json
  policy_enabled     = true
  policy             = data.aws_iam_policy_document.iam-policy.json
}

data "aws_iam_policy_document" "default" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "iam-policy" {
  statement {
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
    "ssmmessages:OpenDataChannel"]
    effect    = "Allow"
    resources = ["*"]
  }
}

##=====================================================================================
## Terraform module to create ec2 instance module on AWS.
##=====================================================================================
module "ec2" {
  source               = "./../../."
  name                 = "ec2"
  environment          = local.environment
  vpc_id               = module.vpc.id
  ssh_allowed_ip       = ["0.0.0.0/0"]
  ssh_allowed_ports    = [22]
  instance_count       = 2
  ami                  = "ami-0866a3c8686eaeeba"
  instance_type        = "t2.micro"
  public_key           = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDb073dkknt6Y3/qvC7LZmUEDWpNQo1FNwbIpVlxxAdzIDyXkwvjuE+vu0yXwK3dR2tqe6ZkBs/hJiTzqIe7i3eubOeN7WeOfs//8t0TFExbDz29P786i7wu09nfX+VUJhmr2WXL7+yRf4pYwvhcQkDchcEs9u+/uxiHxzZRAIU0w5U7AOWlmoDpKJ3KGVP54LK4JhDSepQ5DBiICyffSjM+zigP6elp9ygzexHUT/euA/2noUdvEQ40QIq0t0fbvB4MB1I41P3oline1PNA9YlEzj8B3U6KUo6tr9iM6ATpUGvCIYg1kMAAJ1vDzPVIpo9Cpy9kkCuTngv3r6gA6U5vtFxmq2WCa9oKrPuN08bYDZnN5R0XNYERSo8UR78HwyDcUiB+XooXt3zuDkWK4Q90r3L2r14nVSIxmPYQAid/qJv9+1SgjIU649Q1WafeekZvL8MlaH6EYODNB5aYjCtPt1oXkykZGPRgRXYwqaqym4xbqDElv6seKJRpiA2pyE= rohit@rohit"
  subnet_ids           = tolist(module.public_subnets.public_subnet_id)
  iam_instance_profile = module.iam-role.name

  root_block_device = [
    {
      volume_type           = "gp2"
      volume_size           = 15
      delete_on_termination = true
    }
  ]

  ebs_volume_enabled = true
  ebs_volume_type    = "gp2"
  ebs_volume_size    = 30

  instance_tags = { "snapshot" = true }

  #Mount EBS With User Data
  user_data = file("user-data.sh")
}
