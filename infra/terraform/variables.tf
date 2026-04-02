variable "do_token" {
  description = "DigitalOcean personal access token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region slug"
  type        = string
  default     = "nyc3"
}

variable "environment" {
  description = "Deployment environment (staging | production)"
  type        = string
  default     = "production"
}

variable "droplet_size" {
  description = "Droplet size slug"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "ssh_public_key" {
  description = "SSH public key to install on the Droplet"
  type        = string
  sensitive   = true
}

variable "app_image" {
  description = "Full Docker image reference for the API"
  type        = string
  default     = "ghcr.io/imranhasan871/devops-practical-go-api:latest"
}

variable "nginx_image" {
  description = "Full Docker image reference for nginx"
  type        = string
  default     = "ghcr.io/imranhasan871/devops-practical-reverse-proxy:latest"
}

variable "ghcr_user" {
  description = "GitHub username for ghcr.io authentication"
  type        = string
  default     = "imranhasan871"
}

variable "ghcr_token" {
  description = "GitHub PAT with read:packages scope for pulling from ghcr.io"
  type        = string
  sensitive   = true
}
