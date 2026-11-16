# tf-configuration

Terraform for Cloudflare: one [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/) per server, its ingress rules, and the DNS records pointing at it.

Terraform owns everything on Cloudflare's side. [nix-configuration](https://github.com/sonbae/nix-configuration) owns the server side (the `cloudflared` binary, its config and service) and reads tunnel IDs from this repo, so nothing gets copied by hand except the credentials secret.

```
tf-configuration                                  nix-configuration
────────────────                                  ─────────────────
tunnels.tf ── terraform apply ──▶ tunnels.json ──▶ inputs.tf-configuration.lib.tunnels
                (Cloudflare API)   (committed,       ├─ server: config.yml `tunnel: <id>`
                                    no secrets)      │          + systemd service
                                                     └─ laptop: ssh ProxyCommand per ssh:// host
```

## Layout

```
flake.nix                 terraform + jq dev shell; exposes tunnels.json as lib.tunnels
versions.tf               provider versions
variables.tf              account_id, zone
tunnels.tf                the tunnels map, tunnel + ingress + DNS resources
outputs.tf                writes tunnels.json; sensitive credentials and token outputs
terraform.tfvars.example  copy to terraform.tfvars (gitignored)
tunnels.json              written by `terraform apply`; commit it
.terraform.lock.hcl       pinned provider versions; commit it
```

## Prerequisites

- Nix with flakes. `nix develop` gives you a shell with `terraform` and `jq` pinned by `flake.lock`. (Terraform is BUSL-licensed, so nixpkgs doesn't cache it and the first `nix develop` builds it from source, which takes a few minutes.)
- A Cloudflare API token. Create one at **My Profile > API Tokens > Create Token > Custom token** with:
  - Account / **Cloudflare Tunnel** / Edit
  - Zone / **DNS** / Edit, for your zone
  - Zone / **Zone** / Read, for your zone
- Your Cloudflare account ID.

## First apply

```sh
nix develop
cp terraform.tfvars.example terraform.tfvars   # fill in account_id
export CLOUDFLARE_API_TOKEN=<token>
terraform init
terraform plan
terraform apply
```

If a hostname in `tunnels.tf` already has a DNS record, for example from a tunnel you set up by hand, the apply fails with "record already exists". Delete the old record in the dashboard, or import it:

```sh
terraform import 'cloudflare_dns_record.tunnel["ssh.dev1.crysis.dev"]' <zone_id>/<record_id>
```

Then commit the generated files:

```sh
git add tunnels.json .terraform.lock.hcl
git commit -m "Apply tunnels"
git push
```

## Adding a tunnel or hostname

Edit `local.tunnels` in `tunnels.tf`:

```hcl
tunnels = {
  dev1 = {
    ingress = {
      "ssh.dev1.${var.zone}" = "ssh://localhost:22"
      "app.dev1.${var.zone}" = "http://localhost:8080"
    }
  }
}
```

Each hostname gets a proxied CNAME to `<tunnel-id>.cfargotunnel.com` and an ingress rule. The ingress rules are stored in Cloudflare (`config_src = "cloudflare"`), so changing a route is just `terraform apply` with no change on the server. A new tunnel or a new `ssh://` hostname needs the steps below to reach nix-configuration.

## Using it from nix-configuration

After applying and pushing:

```sh
cd ~/projects/nix-configuration
nix flake update tf-configuration
home-manager switch --flake .
```

### On the server

1. In nix-configuration's `flake.nix`, give the server's entry `modules = [ { cloudflared.tunnel = "dev1"; } ];`. That writes the tunnel ID into `~/.cloudflared/config.yml` and, on Linux, adds a `cloudflared-tunnel` systemd user service.

2. Copy the credentials secret to the server. It never goes in either repo. Run this here, using direct SSH (not the tunnel, which isn't up yet):

   ```sh
   ID=$(terraform output -json tunnel_ids | jq -r .dev1)
   terraform output -json tunnel_credentials | jq -r .dev1 \
     | ssh <server> "mkdir -p ~/.cloudflared && umask 077 && cat > ~/.cloudflared/$ID.json"
   ```

3. On the server, apply the config and keep the service running after you log out:

   ```sh
   home-manager switch --flake .
   sudo loginctl enable-linger $USER
   systemctl --user status cloudflared-tunnel
   ```

`terraform output -json tunnel_tokens` gives a token instead, for `cloudflared tunnel run --token <token>`, if you'd rather run the tunnel without nix-configuration.

### On your laptop

home-manager writes `~/.ssh/cloudflare-tunnels.conf` with a `ProxyCommand cloudflared access ssh` block for every `ssh://` hostname. Add this line at the **top** of `~/.ssh/config` once:

```
Include ~/.ssh/cloudflare-tunnels.conf
```

Then `ssh ssh.dev1.crysis.dev` goes through the tunnel. Your existing `Host` blocks (user, key, port) still apply.

## Security notes

- **State holds secrets.** `terraform.tfstate` contains the tunnel secrets and is gitignored. Back it up, or move it to a remote backend (for example an R2 bucket with the `s3` backend) before running from more than one machine.
- **`tunnels.json` is not secret.** It only holds tunnel IDs and hostnames. A tunnel ID alone can't run the tunnel.
- **SSH is exposed to the internet.** Anyone can reach the SSH hostname through Cloudflare, so the server's own SSH auth is the only gate. Use key-only auth, or put a [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/applications/non-http/cloudflared-authentication/) application in front of the hostname (`cloudflare_zero_trust_access_application`).
