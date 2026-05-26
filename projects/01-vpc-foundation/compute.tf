# -----------------------------------------------------------------------------
# Security Group — ALB
# Accepts HTTP from the internet, allows all outbound
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP inbound to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-alb-sg"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Security Group — EC2
# Only accepts traffic from the ALB security group — not from the internet
# This is security group chaining — source is a SG, not a CIDR
# -----------------------------------------------------------------------------
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow HTTP inbound from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-ec2-sg"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# AMI lookup — gets the latest Amazon Linux 2023 AMI automatically
# This means your code never has a hardcoded AMI ID that goes stale
# -----------------------------------------------------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# Launch Template — defines how EC2 instances are configured
# Used by the Auto Scaling Group below
# -----------------------------------------------------------------------------
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  # Attach the instance profile so SSM works without SSH keys
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
  }

  # User data runs on first boot — installs and starts nginx
  # This gives us something to hit through the ALB to prove traffic flows
  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Ensure SSM agent is running — AL2023 ships with it but needs explicit start
    # Install SSM agent explicitly — not present on this AL2023 AMI
    dnf install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # Install and start nginx
    dnf install -y nginx
    systemctl enable nginx
    systemctl start nginx
    # Replace default page with something identifiable
    echo "<h1>arch-lab-01 - $(hostname -f)</h1>" > /usr/share/nginx/html/index.html
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "${var.project_name}-app"
      Project = var.project_name
    }
  }
}

# -----------------------------------------------------------------------------
# Auto Scaling Group — manages EC2 instances across AZs
# Even for a lab, ASG is the correct pattern — it handles replacement
# if an instance dies and spreads instances across AZs automatically
# -----------------------------------------------------------------------------
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-asg"
  desired_capacity    = 2
  min_size            = 1
  max_size            = 4
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

# -----------------------------------------------------------------------------
# Application Load Balancer — internet-facing, lives in public subnets
# -----------------------------------------------------------------------------
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name    = "${var.project_name}-alb"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Target Group — the ALB forwards traffic here
# Health check hits / on port 80 — instance is healthy if it returns 200
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name    = "${var.project_name}-tg"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# ALB Listener — listens on port 80, forwards to target group
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
