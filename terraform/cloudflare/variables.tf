variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare account id"
  type        = string
  sensitive   = true
}

variable "zone_id" {
  description = "Cloudflare zone id"
  type        = string
  sensitive   = true
}

variable "domain" {
  type    = string
  default = "michaelmuzafarov.dev"
}

variable "google_oauth_client_id" {
  description = "Google OAuth Client ID"
  type        = string
  sensitive   = true
}

variable "google_oauth_client_secret" {
  description = "Google OAuth Client Secret"
  type        = string
  sensitive   = true
}

variable "email" {
  description = "Email used to sign up for cloudflare"
  type        = string
  sensitive   = true
}
