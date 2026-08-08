resource "aws_db_instance" "replica" {
  count = var.create_read_replica ? 1 : 0

  identifier          = "matchlens-${var.environment}-postgres-replica"
  replicate_source_db = aws_db_instance.master.identifier

  instance_class = var.db_instance_class
  storage_type   = "gp3"

  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false
  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Name = "matchlens-${var.environment}-postgres-replica"
  }
}