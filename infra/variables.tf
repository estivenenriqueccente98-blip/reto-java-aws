variable "aws_region" {
  description = "Region para desplegar el reto"
  type        = string
  default = "us-east-2"
}

variable "image_tag" {
  description = "Tag unico de imagen Docker publicada en ECR"
  type        = string
  default     = "bootstrap"
}
