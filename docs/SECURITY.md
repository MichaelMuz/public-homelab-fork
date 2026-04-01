# Security model

## Physical network

Two isolated subnets behind OPNsense. Homelab cannot initiate to personal, personal can reach homelab for admin access. SSH is key-only everywhere (OPNsense, all Proxmox nodes). Admin GUIs (OPNsense, Proxmox) use passwords. OPNsense web GUI on personal interface only (igc2).

WAN port forwards: TCP 443 and 6881 (all protocols) → 192.168.1.210 (public Envoy). Destination NAT rules + manual WAN pass rules. Logging disabled on OPNsense — Envoy handles access logging in-cluster.

## Ingress to the cluster

- **Public Envoy** (192.168.1.210): `*.michaelmuzafarov.dev`. World and cluster nodes.
- **Private Envoy** (192.168.1.212): `*.admin.michaelmuzafarov.dev`. `tailscale-system`, personal subnet (172.16.20.0/24).

Tailscale for remote admin. Auth endpoints on public apps are rate limited via BackendTrafficPolicy to mitigate brute force.

## Encryption

All cross-node pod traffic is encrypted via Cilium WireGuard. Control plane uses Talos mTLS/TLS. Secrets in etcd are encrypted at rest with secretbox.

## In-cluster network policy

Default deny ingress, explicit allow. Egress unrestricted except to Proxmox management IPs (denied clusterwide). Enforcement at namespace level — same namespace can talk, cross-namespace requires explicit allow. kube-system excluded from ingress policy, included in egress deny.

Cilium L4 enforcement on the Envoy pods uses the `gateway.envoyproxy.io/owning-gateway-name` label to target each proxy independently. `socketLB.hostNamespaceOnly` is required — the Tailscale Connector is a router, so service IP translation must happen at the network interface, not the socket layer.

## Traffic source IPs as seen by Envoy

- **Home direct (172.16.20.0/24):** Real client IP preserved through OPNsense DNAT. Envoy sees `172.16.20.x`.
- **Tailscale:** Connector pod forwards traffic. Envoy sees the pod IP (`10.244.x.x`). Cilium enforces access by namespace identity, not source IP.

## Admin access strategy

Admin services (`*.admin.michaelmuzafarov.dev`) restricted by Cilium L4 — only allowed namespaces and CIDRs reach the private Envoy. Passwordless — network position is the credential.

## Observability

Hubble Relay and UI enabled. `hubble observe --verdict DROPPED -f` for live policy drops cluster-wide. Ring buffer is small — always stream live, don't query history.

## DNS

Cloudflare hosts the `michaelmuzafarov.dev` zone. A `cloudflare-ddns` pod (favonia/cloudflare-ddns) runs in-cluster and updates the `michaelmuzafarov.dev` and `*.michaelmuzafarov.dev` A records every 5 minutes. It detects the WAN IP by querying Cloudflare's own `cdn-cgi/trace` endpoint over HTTPS — no third-party IP services, no plaintext HTTP. Records are unproxied (DNS only) so Cloudflare does not terminate TLS or inspect traffic.
