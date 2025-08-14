resource "cloudflare_zero_trust_access_identity_provider" "ident_provider" {
  account_id = var.account_id
  name       = "Google Oauth"
  type       = "google"
  config = {
    client_id     = var.google_oauth_client_id
    client_secret = var.google_oauth_client_secret
  }
}

resource "cloudflare_zero_trust_access_policy" "access_policy" {
  account_id = var.account_id
  name       = "allow_michael_policy"
  decision   = "allow"

  include = [{
    email = {
      email = var.email
    }
  }]
}

resource "cloudflare_zero_trust_access_application" "access" {
  account_id = var.account_id
  name       = "homelab"
  type       = "self_hosted"
  domain     = var.domain
  destinations = [
    {
      type = "public"
      uri  = var.domain
    },
    {
      type = "public"
      uri  = "*.${var.domain}"
    }
  ]
  session_duration          = "24h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.ident_provider.id]
  policies = [{
    id         = cloudflare_zero_trust_access_policy.access_policy.id
    precedence = 1
  }]
}
