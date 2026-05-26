# -----------------------------------------------------------------------------
# Generate a random password — Terraform creates it, never stores it in state
# -----------------------------------------------------------------------------
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|;:,.<>?"
}

# -----------------------------------------------------------------------------
# Secrets Manager secret — the container for the credential
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project_name}/db/credentials"
  description             = "RDS MySQL credentials for ${var.project_name}"
  recovery_window_in_days = 0 # immediate deletion — lab only, not for production

  # Disable automatic rotation for lab simplicity
  # In production you'd enable rotation with a Lambda rotator
  tags = {
    Name    = "${var.project_name}-db-credentials"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Secret version — the actual credential values stored as JSON
# Applications retrieve this and parse the JSON to get individual fields
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    dbname   = var.db_name
    engine   = "mysql"
    port     = 3306
    # host added after RDS is created — updated in rds.tf output
  })
}
