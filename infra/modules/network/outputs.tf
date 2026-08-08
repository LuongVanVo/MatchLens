output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  value = aws_subnet.private_db[*].id
}

output "nat_instance_ids" {
  value = aws_instance.nat[*].id
}

output "db_subnet_group_name" {
  value = aws_db_subnet_group.this.name
}