terraform {
  required_version = ">= 1.6"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.36"
    }
  }

  # store state in DigitalOcean Spaces (S3-compatible) so the team shares it
  # create the bucket manually before the first apply:
  #   doctl spaces create devops-practical-tfstate --region nyc3
  backend "s3" {
    endpoint                    = "https://nyc3.digitaloceanspaces.com"
    bucket                      = "devops-practical-tfstate"
    key                         = "prod/terraform.tfstate"
    region                      = "us-east-1"   # placeholder - DO Spaces ignores this
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}

provider "digitalocean" {
  token = var.do_token
}

# ------------------------------------------------------------------ #
# SSH Key                                                             #
# ------------------------------------------------------------------ #

resource "digitalocean_ssh_key" "deploy" {
  name       = "devops-practical-deploy"
  public_key = var.ssh_public_key
}

# ------------------------------------------------------------------ #
# Container Registry                                                  #
# ------------------------------------------------------------------ #

# starter tier is free and supports unlimited private repos
resource "digitalocean_container_registry" "main" {
  name                   = var.registry_name
  subscription_tier_slug = "starter"
  region                 = var.region
}

# ------------------------------------------------------------------ #
# VPC                                                                 #
# ------------------------------------------------------------------ #

resource "digitalocean_vpc" "main" {
  name     = "devops-practical-vpc"
  region   = var.region
  ip_range = "10.10.0.0/16"
}

# ------------------------------------------------------------------ #
# Droplets                                                            #
# ------------------------------------------------------------------ #

resource "digitalocean_droplet" "app" {
  count  = var.droplet_count
  name   = "devops-practical-${count.index + 1}"
  image  = "ubuntu-22-04-x64"
  size   = var.droplet_size
  region = var.region
  vpc_uuid = digitalocean_vpc.main.id

  ssh_keys = [digitalocean_ssh_key.deploy.fingerprint]

  # bootstrap: install docker, pull the image, start the container
  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    app_image     = var.app_image
    registry_name = var.registry_name
    do_token      = var.do_token
  })

  tags = ["devops-practical", var.environment, "app"]
}

# ------------------------------------------------------------------ #
# Load Balancer                                                       #
# ------------------------------------------------------------------ #

resource "digitalocean_loadbalancer" "main" {
  name   = "devops-practical-lb"
  region = var.region
  vpc_uuid = digitalocean_vpc.main.id

  # forward external HTTP to the app port on Droplets
  forwarding_rule {
    entry_port      = 80
    entry_protocol  = "http"
    target_port     = 8080
    target_protocol = "http"
  }

  # health check against our liveness probe
  healthcheck {
    port                     = 8080
    protocol                 = "http"
    path                     = "/healthz"
    check_interval_seconds   = 10
    response_timeout_seconds = 5
    healthy_threshold        = 2
    unhealthy_threshold      = 3
  }

  # sticky sessions are off intentionally - app is stateless
  sticky_sessions {
    type = "none"
  }

  droplet_tag = "app"
}

# ------------------------------------------------------------------ #
# Firewall                                                            #
# ------------------------------------------------------------------ #

resource "digitalocean_firewall" "app" {
  name = "devops-practical-fw"
  tags = ["app"]

  # allow SSH only from within the VPC (use the load balancer for public traffic)
  # in practice you'd restrict this further or use a bastion / tailscale
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = [digitalocean_vpc.main.ip_range]
  }

  # app port - only accept connections from the load balancer
  inbound_rule {
    protocol                  = "tcp"
    port_range                = "8080"
    source_load_balancer_uids = [digitalocean_loadbalancer.main.id]
  }

  # allow all outbound so Droplets can pull images, run apt, etc.
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# ------------------------------------------------------------------ #
# Project (groups all resources in the DO dashboard)                  #
# ------------------------------------------------------------------ #

resource "digitalocean_project" "main" {
  name        = "devops-practical"
  description = "Go API service - DevOps practical"
  purpose     = "Web Application"
  environment = title(var.environment)

  resources = concat(
    [for d in digitalocean_droplet.app : d.urn],
    [
      digitalocean_loadbalancer.main.urn,
      digitalocean_container_registry.main.urn,
    ]
  )
}
