variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "todo-list-app"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "public_key" {
  description = "Llave publica SSH para el Key Pair"
  type        = string
}

variable "db_username" {
  type    = string
  default = "todoadmin"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "github_repo_url" {
  description = "URL HTTPS del repositorio publico (ej. https://github.com/usuario/to-do-list-api.git)"
  type        = string
}

variable "alert_email" {
  description = "Correo electronico para notificaciones de SNS"
  type        = string
}
