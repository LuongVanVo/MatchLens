data "aws_ami" "nat" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_security_group" "nat_instance" {
  name        = "${local.name_prefix}-nat-instance-sg"
  description = "Security group for NAT Instance"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow outbound traffic from private app subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  egress {
    description = "Allow all outbound traffic to internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-nat-instance-sg"
  }
}

resource "aws_instance" "nat" {
  count = var.nat_instance_count

  ami                         = data.aws_ami.nat.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[count.index].id
  vpc_security_group_ids      = [aws_security_group.nat_instance.id]
  source_dest_check           = false
  associate_public_ip_address = true

  tags = {
    Name = "${local.name_prefix}-nat-instance-${count.index + 1}"
    Role = "nat"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/98-nat.conf
    sysctl -p /etc/sysctl.d/98-nat.conf
    iptables -t nat -A POSTROUTING -j MASQUERADE
    dnf install -y iptables-services
    service iptables save
    systemctl enable iptables
  EOF
}

resource "aws_route" "private_app_nat" {
  count = var.az_count

  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[min(count.index, var.nat_instance_count - 1)].primary_network_interface_id
}