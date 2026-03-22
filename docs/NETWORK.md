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

| Interface | Rule                   | Direction                                 |
|-----------|------------------------|-------------------------------------------|
| WAN       | Block all (default)    | Internet cannot initiate to any LAN       |
| Homelab   | Block to Personal net  | Homelab cannot initiate to 172.16.20.0/24 |
| Homelab   | Pass all (below block) | Homelab can reach internet                |
| Personal  | Pass all               | Personal can reach homelab and internet   |

## IPv6

Personal: identity association (prefix delegation from WAN). Homelab: disabled.

## DNS

Unbound on OPNsense, listening on Homelab and Personal interfaces. Query forwarding: `admin.michaelmuzafarov.dev` → 192.168.1.211 (cluster CoreDNS).

## NAT

Automatic outbound NAT for all interfaces.
