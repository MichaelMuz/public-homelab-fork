resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab_tunnel" {
  account_id    = var.account_id
  name          = "homelab-tunnel"
  config_src    = "local"
  tunnel_secret = base64encode(random_password.tunnel_secret.result)
}


resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab_tunnel_config" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab_tunnel.id
  config = {
    ingress = [
      # could leave of hostname and have one rule, but here for explicitness
      {
        hostname = var.domain
        service  = "http://192.168.1.210:80"
        origin_request = {
          access = {
            aud_tag   = [cloudflare_zero_trust_access_application.access.aud]
            team_name = "michaelmuzafarov"
            required  = true
          }
        }
      },
      {
        hostname =  "*.${var.domain}"
        service  = "http://192.168.1.210:80"
        origin_request = {
          access = {
            aud_tag   = [cloudflare_zero_trust_access_application.access.aud]
            team_name = "michaelmuzafarov"
            required  = true
          }
        }
      },
      {
        service = "http_status:404"
      }
    ]
  }
}
