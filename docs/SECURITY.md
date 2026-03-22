# Security model

## Physical network

Two isolated subnets behind OPNsense. Homelab cannot initiate to personal, personal can reach homelab for admin access. WAN blocks all inbound. No ports forwarded yet. SSH is key-only everywhere (OPNsense, all Proxmox nodes). Admin GUIs (OPNsense, Proxmox) use passwords. OPNsense web GUI on personal interface only (igc2).

## Ingress to the cluster

- **Public Envoy** (192.168.1.210): `*.michaelmuzafarov.dev`. World, cluster nodes, Cloudflare Tunnel.
- **Private Envoy** (192.168.1.212): `*.admin.michaelmuzafarov.dev`. Cluster nodes (Tailscale), personal subnet (172.16.20.0/24).

Cloudflare Tunnel with Zero Trust (Google SSO) still active for remote access to public services. Tailscale for remote admin.

## Encryption

All cross-node pod traffic is encrypted via Cilium WireGuard. Control plane uses Talos mTLS/TLS. Secrets in etcd are encrypted at rest with secretbox.

## In-cluster network policy

Default deny ingress, explicit allow. Egress unrestricted except to Proxmox management IPs (denied clusterwide). Enforcement at namespace level — same namespace can talk, cross-namespace requires explicit allow. kube-system excluded from ingress policy, included in egress deny.

Cilium L4 enforcement on the Envoy pods uses the `gateway.envoyproxy.io/owning-gateway-name` label to target each proxy independently. Envoy SecurityPolicy on the private gateway filters by source IP.

## Traffic source IPs as seen by Envoy

- **Home direct (172.16.20.0/24):** Real client IP preserved through OPNsense DNAT. Envoy sees `172.16.20.x`.
- **Tailscale:** Appears as the node IP of whatever host the Tailscale pod runs on. Envoy sees `192.168.1.x`. Matches `remote-node` entity in Cilium.
- **Cloudflare Tunnel:** Appears as the pod IP from the cloudflare-tunnel namespace. Envoy sees `10.244.x.x`. CF tunnel only routes to the public Envoy.

## Admin access strategy

Admin services (`*.admin.michaelmuzafarov.dev`) are restricted at two layers:
1. **Cilium L4:** Only remote-node and 172.16.20.0/24 can reach the private Envoy pods.
2. **Envoy SecurityPolicy:** Allows 192.168.1.0/24 and 172.16.20.0/24.

Passwordless — network position is the credential.

## What is not yet done

- Port forwarding (WAN 443 only → 192.168.1.210)
- DNS cutover (Cloudflare CNAME → A record)
- Drop HTTP entirely — only expose port 443, no port 80 listener
- Cloudflare Tunnel retirement (remove remaining CF tunnel Cilium rules and tunnel infrastructure)
