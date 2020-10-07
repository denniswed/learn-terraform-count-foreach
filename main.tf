terraform {
  required_version = ">= 0.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "2.69.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  shared_credentials_file = "C:/users/denni/.aws/credentials"
  profile                 = "dwmfa"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.44.0"

  for_each = var.project

  cidr = var.vpc_cidr_block

  azs             = data.aws_availability_zones.available.names
  #private_subnets = slice(var.private_subnet_cidr_blocks, 0, var.private_subnets_per_vpc)
  #public_subnets  = slice(var.public_subnet_cidr_blocks, 0, var.public_subnets_per_vpc)
  private_subnets = slice(var.private_subnet_cidr_blocks, 0, each.value.private_subnets_per_vpc)
  public_subnets  = slice(var.public_subnet_cidr_blocks, 0, each.value.public_subnets_per_vpc)

  enable_nat_gateway = true
  enable_vpn_gateway = false

 # project_name = each.key
 # environment  = each.value.environment

  tags = {
    #for_each = var.project

    Terraform   = "true"
    Project     = "${each.key}"
    Environment = "${each.value.environment}"
  }

}

module "app_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.12.0"

  for_each = var.project

  #name        = "web-server-sg-${var.project_name}-${var.environment}"
  name        = "web-server-sg-${each.key}-${each.value.environment}"
  description = "Security group for web-servers with HTTP ports open within VPC"
  #vpc_id      = module.vpc.vpc_id
  vpc_id      = module.vpc[each.key].vpc_id

  #ingress_cidr_blocks = module.vpc.public_subnets_cidr_blocks
  ingress_cidr_blocks = module.vpc[each.key].public_subnets_cidr_blocks

#  project_name = each.key
#  environment  = each.value.environment

  tags = {
    Terraform   = "true"
    Project     = "${each.key}"
    Environment = "${each.value.environment}"
  }

}

module "lb_security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/web"
  version = "3.12.0"
  
  for_each = var.project
  
  #name = "load-balancer-sg-${var.project_name}-${var.environment}"
  name = "load-balancer-sg-${each.key}-${each.value.environment}"

  description = "Security group for load balancer with HTTP ports open within VPC"
  #vpc_id      = module.vpc.vpc_id
  vpc_id      = module.vpc[each.key].vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]

 # project_name = each.key
 # environment  = each.value.environment

  tags = {
    Terraform   = "true"
    Project     = "${each.key}"
    Environment = "${each.value.environment}"
  }

}

resource "random_string" "lb_id" {
  length  = 4
  special = false
}

module "elb_http" {
  source  = "terraform-aws-modules/elb/aws"
  version = "2.4.0"

  for_each = var.project

  # Comply with ELB name restrictions 
  # https://docs.aws.amazon.com/elasticloadbalancing/2012-06-01/APIReference/API_CreateLoadBalancer.html
  #name     = trimsuffix(substr(replace(join("-", ["lb", random_string.lb_id.result, var.project_name, var.environment]), "/[^a-zA-Z0-9-]/", ""), 0, 32), "-")
  name = trimsuffix(substr(replace(join("-", ["lb", random_string.lb_id.result, each.key, each.value.environment]), "/[^a-zA-Z0-9-]/", ""), 0, 32), "-")
  internal = false

  #security_groups = [module.lb_security_group.this_security_group_id]
  #subnets         = module.vpc.public_subnets
  security_groups = [module.lb_security_group[each.key].this_security_group_id]
  subnets         = module.vpc[each.key].public_subnets

  #number_of_instances = length(aws_instance.app)
  #instances           = aws_instance.app.*.id
  number_of_instances = length(module.ec2_instances[each.key].instance_ids)
  instances           = module.ec2_instances[each.key].instance_ids

 # project_name = each.key
 # environment  = each.value.environment

  tags = {
    Terraform   = "true"
    Project     = "${each.key}"
    Environment = "${each.value.environment}"
  }

  listener = [{
    instance_port     = "80"
    instance_protocol = "HTTP"
    lb_port           = "80"
    lb_protocol       = "HTTP"
  }]

  health_check = {
    target              = "HTTP:80/index.html"
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 10
    timeout             = 5
  }
}

module "ec2_instances" {
  source = "./modules/aws-instance"

  for_each = var.project

  instance_count     = each.value.instances_per_subnet * length(module.vpc[each.key].private_subnets)
  instance_type      = each.value.instance_type
  subnet_ids         = module.vpc[each.key].private_subnets[*]
  security_group_ids = [module.app_security_group[each.key].this_security_group_id]

  project_name = each.key
  environment  = each.value.environment
}

/*
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


resource "aws_instance" "app" {
  count = var.instances_per_subnet * length(module.vpc.private_subnets)

  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  subnet_id              = module.vpc.private_subnets[count.index % length(module.vpc.private_subnets)]
  vpc_security_group_ids = [module.app_security_group.this_security_group_id]

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install httpd -y
    sudo systemctl enable httpd
    sudo systemctl start httpd
    echo "<html><body><div>Hello, world!</div></body></html>" > /var/www/html/index.html
    EOF

  tags = {
    Terraform   = "true"
    Project     = var.project_name
    Environment = var.environment
  }
}
*/
