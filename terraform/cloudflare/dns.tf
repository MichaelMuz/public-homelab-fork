resource "cloudflare_dns_record" "tunnel_dns_record" {
  for_each = toset(["*", "@"]) # root domain and any subdomain
  zone_id  = var.zone_id
  name     = each.value
  ttl      = 1
  type     = "CNAME"
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.homelab_tunnel.id}.cfargotunnel.com"
  proxied  = true
  comment  = "send to tunnel"
}

