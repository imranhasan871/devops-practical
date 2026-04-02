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
  description = "Droplet size slug (see: doctl compute size list)"
  type        = string
  default     = "s-1vcpu-2gb"
}

variable "droplet_count" {
  description = "Number of app Droplets to provision behind the load balancer"
  type        = number
  default     = 2
}

variable "ssh_public_key" {
  description = "SSH public key to install on Droplets for emergency access"
  type        = string
  sensitive   = true
}

variable "app_image" {
  description = "Full Docker image reference to run on first boot (e.g. registry.digitalocean.com/myregistry/devops-practical:sha-abc)"
  type        = string
  default     = "ghcr.io/imranhasan871/devops-practical:latest"
}

variable "registry_name" {
  description = "DigitalOcean Container Registry name"
  type        = string
  default     = "devops-practical"
}
