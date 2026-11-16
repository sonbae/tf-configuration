# Non-secret tunnel data, committed to the repo and exposed by flake.nix as
# `lib.tunnels` so nix-configuration can read tunnel IDs and hostnames.
resource "local_file" "tunnels_json" {
  filename        = "${path.module}/tunnels.json"
  file_permission = "0644"
  content = "${jsonencode({
    for name, t in local.tunnels : name => {
      id        = cloudflare_zero_trust_tunnel_cloudflared.this[name].id
      hostnames = t.ingress
    }
  })}\n"
}

output "tunnel_ids" {
  description = "Tunnel IDs by name."
  value       = { for name, t in cloudflare_zero_trust_tunnel_cloudflared.this : name => t.id }
}

# Contents of ~/.cloudflared/<tunnel-id>.json on each server, used with the
# `tunnel:` and `credentials-file:` lines nix-configuration writes.
output "tunnel_credentials" {
  description = "cloudflared credentials file contents by tunnel name."
  sensitive   = true
  value = {
    for name, t in cloudflare_zero_trust_tunnel_cloudflared.this : name => jsonencode({
      AccountTag   = var.account_id
      TunnelID     = t.id
      TunnelSecret = random_bytes.tunnel_secret[name].base64
    })
  }
}

# Alternative to the credentials file: `cloudflared tunnel run --token <token>`.
output "tunnel_tokens" {
  description = "Tunnel run tokens by tunnel name."
  sensitive   = true
  value       = { for name, t in data.cloudflare_zero_trust_tunnel_cloudflared_token.this : name => t.token }
}
