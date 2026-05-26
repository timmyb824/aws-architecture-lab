# -----------------------------------------------------------------------------
# Elastic IP for the NAT Gateway
# A NAT Gateway needs a static public IP to source outbound traffic from
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "${var.project_name}-nat-eip"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# NAT Gateway
# Lives in a PUBLIC subnet — it needs internet access to forward traffic out
# Private instances route outbound traffic here, it forwards to the IGW
# Cost Reminder: NAT Gateway costs ~$30/month per gateway + data processing fees
# terraform destroy -target=aws_nat_gateway.main -target=aws_eip.nat
# terraform apply -target=aws_nat_gateway.main -target=aws_eip.nat
# -----------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name    = "${var.project_name}-nat"
    Project = var.project_name
  }

  # NAT Gateway depends on the IGW existing first
  # Without this Terraform might try to create the NAT before the IGW is ready
  depends_on = [aws_internet_gateway.main]
}
