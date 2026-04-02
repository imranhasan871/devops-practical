terraform {
  required_version = ">= 1.6"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.36"
    }
  }

  # using local state for initial bootstrap
  backend "local" {}
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
# Single Droplet  (~$6/month, s-1vcpu-1gb)                          #
# Images are stored on GitHub Container Registry (free)              #
# ------------------------------------------------------------------ #

resource "digitalocean_droplet" "app" {
  name   = "devops-practical"
  image  = "ubuntu-22-04-x64"
  size   = var.droplet_size
  region = var.region

  ssh_keys = [digitalocean_ssh_key.deploy.fingerprint]

  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    app_image   = var.app_image
    nginx_image = var.nginx_image
    ghcr_user   = var.ghcr_user
    ghcr_token  = var.ghcr_token
  })

  tags = ["devops-practical", var.environment, "app"]
}

# ------------------------------------------------------------------ #
# Firewall                                                            #
# ------------------------------------------------------------------ #

resource "digitalocean_firewall" "app" {
  name       = "devops-practical-fw"
  tags       = ["app"]
  depends_on = [digitalocean_droplet.app]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "8080"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

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
# Project                                                             #
# ------------------------------------------------------------------ #

resource "digitalocean_project" "main" {
  name        = "devops-practical"
  description = "Go API service - DevOps practical"
  purpose     = "Web Application"
  environment = title(var.environment)

  resources = [digitalocean_droplet.app.urn]
}
