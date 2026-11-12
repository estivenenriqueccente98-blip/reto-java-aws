output "ecr_repository_url" {
  description = "URL del repositorio en ECR"
  value       = aws_ecr_repository.app.repository_url
}

output "app_url" {
  description = "Endpoint HTTP publico del desafio"
  value       = "http://${aws_lb.app.dns_name}/"
}

output "health_url" {
  description = "Endpoint para comprobar salud"
  value       = "http://${aws_lb.app.dns_name}/health"
}

output "ecs_cluster" {
  value = aws_ecs_cluster.app.name
}
