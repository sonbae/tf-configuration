# One Cloudflare Tunnel per server. Edit this map to add tunnels or hostnames.
#
# Each hostname gets a proxied CNAME to the tunnel, and an ingress rule
# sending its traffic to the service on the server. `ssh://` services are
# also picked up by nix-configuration, which adds a `cloudflared access ssh`
# ProxyCommand for them.
locals {
  tunnels = {
    dev1 = {
      ingress = {
        "ssh.dev1.${var.zone}" = "ssh://localhost:22"
      }
    }
  }

  # Flatten to { "<hostname>" = { tunnel = "<name>", service = "<url>" } }.
  hostnames = merge([
    for name, t in local.tunnels : {
      for host, service in t.ingress : host => { tunnel = name, service = service }
    }
  ]...)
}

data "cloudflare_zone" "this" {
  filter = {
    name = var.zone
  }
}

# Generating the secret here (rather than letting Cloudflare pick one) lets
# Terraform build the credentials file cloudflared reads on the server.
resource "random_bytes" "tunnel_secret" {
  for_each = local.tunnels
  length   = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  for_each = local.tunnels

  account_id    = var.account_id
  name          = each.key
  tunnel_secret = random_bytes.tunnel_secret[each.key].base64

  # Ingress rules live in Cloudflare (the resource below), so changing a
  # route is a `terraform apply` and never touches the server.
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  for_each = local.tunnels

  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this[each.key].id

  config = {
    ingress = concat(
      [for host, service in each.value.ingress : { hostname = host, service = service }],
      # cloudflared requires a final catch-all rule.
      [{ service = "http_status:404" }],
    )
  }
}

resource "cloudflare_dns_record" "tunnel" {
  for_each = local.hostnames

  zone_id = data.cloudflare_zone.this.zone_id
  name    = each.key
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this[each.value.tunnel].id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # automatic; required for proxied records
  comment = "Cloudflare Tunnel ${each.value.tunnel}, managed by tf-configuration"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  for_each = local.tunnels

  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this[each.key].id
}
