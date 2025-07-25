data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

data  "aws_vpc" "default" {
  default = true
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]



  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}


module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.0.1"
  
  name     = "blog"
  min_size = 1
  max_size = 2

  vpc_zone_identifier = module.blog_vpc.public_subnets
  security_groups     = [module.blog_sg.security_group_id]

  image_id      = data.aws_ami.app_ami.id
  instance_type = var.instance_type
}

module "blog_alb" {
  source = "terraform-aws-modules/alb/aws"

  name            = "blog-alb"
  vpc_id          = module.blog_vpc.vpc_id
  subnets         = module.blog_vpc.public_subnets
  security_groups = [module.blog_sg.security_group_id]


  target_groups = {
    blog-instance = {
      name_prefix      = "blog-"
      protocol         = "HTTP"
      port             = 80
      target_type      = "instance"  
      create_attachment = false
    }
  }
  listeners = {
    http = {
      port            = 80
      protocol        = "HTTP"

      forward = {
        target_group_key = "blog-instance"
      }
    }
  }

  tags = {
    Environment = "dev"

  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"
  name = "blog"

  vpc_id = module.blog_vpc.vpc_id

  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = module.blog_autoscaling.autoscaling_group_name
  lb_target_group_arn    = module.blog_alb.target_groups["blog-instance"].arn
}