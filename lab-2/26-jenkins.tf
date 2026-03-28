############################################
# Jenkins Server
############################################

# Security Group for Jenkins EC2
resource "aws_security_group" "vandelay_jenkins_sg" {
  name        = "${local.name_prefix}-jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = aws_vpc.vandelay_vpc01.id

  # Jenkins web UI
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Allow Jenkins UI from admin IP"
  }

  # SSH for troubleshooting
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
    description = "Allow SSH from admin IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-jenkins-sg"
  })
}

# IAM Role for Jenkins EC2
resource "aws_iam_role" "vandelay_jenkins_role" {
  name = "${local.name_prefix}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# SSM access so you can use Session Manager instead of raw SSH
resource "aws_iam_role_policy_attachment" "vandelay_jenkins_ssm" {
  role       = aws_iam_role.vandelay_jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent (optional but useful for Jenkins log shipping)
resource "aws_iam_role_policy_attachment" "vandelay_jenkins_cw" {
  role       = aws_iam_role.vandelay_jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "vandelay_jenkins_profile" {
  name = "${local.name_prefix}-jenkins-profile"
  role = aws_iam_role.vandelay_jenkins_role.name
}

# Jenkins EC2 Instance
resource "aws_instance" "vandelay_jenkins" {
  ami                    = var.jenkins_ami_id
  instance_type          = var.jenkins_instance_type
  subnet_id              = aws_subnet.vandelay_public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.vandelay_jenkins_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.vandelay_jenkins_profile.name

  user_data = file("${path.module}/jenkins_user_data.sh")

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-jenkins"
  })
}

############################################
# Persistent EBS Volume for Jenkins Home
############################################

# This volume survives EC2 teardown — plugins, jobs, and config are preserved.
# IMPORTANT: prevent_destroy = true means `terraform destroy` will error unless
# you remove this block first. This is intentional to protect your Jenkins data.
resource "aws_ebs_volume" "vandelay_jenkins_data" {
  availability_zone = var.azs[0]
  size              = 20
  type              = "gp3"

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-jenkins-data"
  })
}

resource "aws_volume_attachment" "vandelay_jenkins_data" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.vandelay_jenkins_data.id
  instance_id  = aws_instance.vandelay_jenkins.id
  force_detach = true
}
