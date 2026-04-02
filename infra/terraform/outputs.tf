output "droplet_ip" {
  description = "Public IP of the Droplet"
  value       = digitalocean_droplet.app.ipv4_address
}
