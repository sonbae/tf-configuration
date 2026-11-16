variable "account_id" {
  description = "Cloudflare account ID (dashboard > Account home > ⋯ next to the account > Copy account ID)."
  type        = string
}

variable "zone" {
  description = "The zone (domain) the tunnel hostnames live in."
  type        = string
  default     = "crysis.dev"
}
