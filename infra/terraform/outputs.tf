output "load_balancer_ip" {
  description = "Public IP of the DigitalOcean Load Balancer - point your DNS A record here"
  value       = digitalocean_loadbalancer.main.ip
}

output "droplet_ips" {
  description = "Private IPs of the app Droplets"
  value       = [for d in digitalocean_droplet.app : d.ipv4_address_private]
}

output "registry_endpoint" {
  description = "Container registry endpoint (use this as your IMAGE prefix)"
  value       = "registry.digitalocean.com/${digitalocean_container_registry.main.name}"
}

output "registry_name" {
  description = "Container registry name"
  value       = digitalocean_container_registry.main.name
}
