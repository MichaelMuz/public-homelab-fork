# Network infrastructure

Non-IaC configuration that surrounds the homelab.

## Physical topology

```
ISP (Optimum)
 |
Motorola DOCSIS 3.1 modem
 |
OPNsense router (N100 4 core fanless mini PC, 8GB RAM, 128GB SSD)
 ├── igc0 (eth0) (Homelab)  192.168.1.1/24  — no DHCP, all static
 │    |
 │    Unmanaged switch
 │     └── All Proxmox hosts
 │
 ├── igc1 (eth1) (WAN)      DHCP from modem
 ├── igc2 (eth2) (Personal) 172.16.20.1/24  — DHCP 172.16.20.100-254
 │    |
 │    OpenWrt AX3000 AP (dumb mode, 172.16.20.2)
 │     └── All personal devices
 │
 └── igc3 (eth3)            Unassigned
```

## Personal subnet (172.16.20.0/24)

| Range     | Purpose                        |
|-----------|--------------------------------|
| .1        | OPNsense gateway               |
| .2        | OpenWrt AP management          |
| .3-.99    | Static reservations (unused)   |
| .100-.254 | DHCP pool for personal devices |

## Admin consoles

| Service    | Address                        |
|------------|--------------------------------|
| OPNsense   | 172.16.20.1 (personal only)    |
| Modem      | 192.168.100.1                  |
| OpenWrt AP | 172.16.20.2                    |

## OPNsense firewall rules

| Interface | Rule                      | Direction                                               |
|-----------|---------------------------|---------------------------------------------------------|
| WAN       | Pass TCP 443              | Internet → 192.168.1.210 (public Envoy)                 |
| WAN       | Pass (all protocols) 6881 | Internet → 192.168.1.210 (qBittorrent via public Envoy) |
| WAN       | Block all (default)       | Internet cannot initiate to any LAN (everything else)   |
| Homelab   | Block to Personal net     | Homelab cannot initiate to 172.16.20.0/24               |
| Homelab   | Pass all (below block)    | Homelab can reach internet                              |
| Personal  | Pass all                  | Personal can reach homelab and internet                 |

## IPv6

Personal: identity association (prefix delegation from WAN). Homelab: disabled.

## DNS

**Internal:** Unbound on OPNsense, listening on Homelab and Personal interfaces. Query forwarding: `michaelmuzafarov.dev` → 192.168.1.211 (cluster CoreDNS). This covers all subdomains — CoreDNS routes `*.admin.michaelmuzafarov.dev` to 192.168.1.212 (private Envoy) and everything else to 192.168.1.210 (public Envoy). Without this, personal subnet devices would resolve public services to the WAN IP, which OPNsense treats as traffic to itself rather than forwarding via the WAN destination NAT rule.

**Public:** Cloudflare hosts the `michaelmuzafarov.dev` zone. A `cloudflare-ddns` pod (favonia/cloudflare-ddns) updates the A records for `michaelmuzafarov.dev` and `*.michaelmuzafarov.dev` every 5 minutes. Records are unproxied (DNS only).

## NAT

Automatic outbound NAT for all interfaces.

### Port forwards

Each port forward is a pair: a Destination NAT rule (Firewall → NAT → Destination NAT) that rewrites the destination, and a WAN pass rule (Firewall → Rules → WAN) that allows the traffic. Both are IPv4 only, firewall rule set to "Manual," logging disabled (Envoy handles access logging in-cluster where storage is easier to manage).

| Port | Target        | Purpose                                                         |
|------|---------------|-----------------------------------------------------------------|
| 443  | 192.168.1.210 | HTTPS to public Envoy                                           |
| 6881 | 192.168.1.210 | BitTorrent peers to qBittorrent (via public Envoy TCP+UDP listeners) |

**OPNsense gotchas:**

- OPNsense has two rule engines: classic (Firewall → Rules) and new (Firewall → Rules [new]). The classic Rules is where you create and manage rules. Rules [new] with Inspect mode shows the full merged view of all rules including auto-generated ones.
- The Destination NAT form has a "Firewall rule" dropdown. "Register rule" auto-creates a hidden system-managed WAN pass rule that only appears in Rules [new] under Inspect → "Automatically generated rules." This is a footgun — the rule is invisible in the classic Rules view. Use "Manual" instead and create the WAN pass rule yourself under Firewall → Rules → WAN so it is visible and manageable.
- "Pass" (another option in that dropdown) makes the NAT rule itself act as a pass — no separate firewall rule at all, also invisible in the rules tab.
