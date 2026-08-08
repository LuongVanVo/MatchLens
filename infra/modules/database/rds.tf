resource "aws_security_group" "rds" {
  name        = "matchlens-${var.environment}-rds-sg"
  description = "Security group for RDS PostgreSQL - ingress rules added by compute/messaging modules"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "matchlens-${var.environment}-rds-sg"
  }
}

resource "aws_db_instance" "master" {
  identifier     = "matchlens-${var.environment}-postgres"
  engine         = "postgres"
  engine_version = "17.10"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_master_username
  password = random_password.db_master.result

  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                = var.multi_az
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = {
    Name = "matchlens-${var.environment}-postgres"
  }
}

resource "random_password" "db_master" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name_prefix             = "matchlens-${var.environment}-db-credentials-secret"
  description             = "RDS PostgreSQL master credentials for MatchLens ${var.environment}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db_master.result
    engine   = "postgres"
    host     = aws_db_instance.master.address
    port     = aws_db_instance.master.port
    dbname   = var.db_name
  })
}