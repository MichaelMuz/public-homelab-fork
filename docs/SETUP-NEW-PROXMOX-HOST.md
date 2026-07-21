# New Proxmox host setup

A fresh install ships with the paid enterprise repos, an old point release, and password SSH. These steps fix that and bring the host in line with the rest of the fleet.

Order: copy SSH key → harden SSH → swap repos → kill nag → upgrade → reboot → prep reused disks (if any).

## 1. SSH key + hardening

Copy your key over password SSH (once, from the workstation). Clear any stale host key first, since a reinstall on a reused IP changes it:

```
ssh-keygen -R <ip> && ssh-copy-id -o PreferredAuthentications=password -o PubkeyAuthentication=no -i ~/.ssh/id_ed25519_20muzm01.pub root@<ip>
```

The `-o` flags force password auth for the copy itself. Without them, if your agent holds several keys, ssh offers each as a separate attempt and trips the server's `MaxAuthTries` (default 6) before it ever reaches the password prompt, failing with "Too many authentication failures".

Then edit `/etc/ssh/sshd_config` to turn off password login (comment the original line, add the new one):

| Setting                  | Default           | Change to           |
|--------------------------|-------------------|---------------------|
| `PermitRootLogin`        | `yes`             | `prohibit-password` |
| `PasswordAuthentication` | (commented) `yes` | `no`                |
| `PermitEmptyPasswords`   | (commented) `no`  | `no`                |
| `PubkeyAuthentication`   | (commented) `yes` | `yes`               |
| `X11Forwarding`          | `yes`             | `no`                |

Or just run (idempotent, rewrites each line whether it's commented or active) **ON THE MACHINE**:

```
sed -i -E \
  -e 's/^#?[[:space:]]*PermitRootLogin[[:space:]]+.*/PermitRootLogin prohibit-password/' \
  -e 's/^#?[[:space:]]*PasswordAuthentication[[:space:]]+.*/PasswordAuthentication no/' \
  -e 's/^#?[[:space:]]*PermitEmptyPasswords[[:space:]]+.*/PermitEmptyPasswords no/' \
  -e 's/^#?[[:space:]]*PubkeyAuthentication[[:space:]]+.*/PubkeyAuthentication yes/' \
  -e 's/^#?[[:space:]]*X11Forwarding[[:space:]]+.*/X11Forwarding no/' \
  /etc/ssh/sshd_config
```

Apply and verify the **effective** config, which resolves any `sshd_config.d/*.conf` drop-in that would otherwise silently override the main file:

```
sshd -t && systemctl reload ssh && sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|permitemptypasswords|pubkeyauthentication|x11forwarding) '
```

Effect: root can only log in with a key, password login is off. Expect:
```
permitrootlogin without-password
pubkeyauthentication yes
passwordauthentication no
x11forwarding no
permitemptypasswords no
```
If a value is wrong, a drop-in is winning; set it there instead of the main file.

## 2. apt repos

A fresh box points at the **paid enterprise** repos. With no subscription they return `401 Unauthorized` on every `apt update`. 

The fix: disable the enterprise repos and add the free one. All in `/etc/apt/sources.list.d/`.

### Disable the enterprise PVE repo: `pve-enterprise.sources`
Paid Proxmox repo, enabled by default, 401s without a subscription. Add `Enabled: no` at the end:

```
Types: deb
URIs: https://enterprise.proxmox.com/debian/pve
Suites: trixie
Components: pve-enterprise
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
Enabled: no
```

### Add the free PVE repo: `proxmox.sources`
Does not exist by default. Create it:

```
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
```

### Delete the Ceph repo: `ceph.sources`
Another paid enterprise repo that 401s, and we run no Ceph. Delete the file: `rm /etc/apt/sources.list.d/ceph.sources`.

Or just run all three **ON THE MACHINE** (`$CODENAME` auto-detects the Debian release, so this doesn't rot when the base OS moves):

```
sed -i '/^Enabled:/d' /etc/apt/sources.list.d/pve-enterprise.sources && echo 'Enabled: no' >> /etc/apt/sources.list.d/pve-enterprise.sources

CODENAME=$(. /etc/os-release; echo "$VERSION_CODENAME")
cat > /etc/apt/sources.list.d/proxmox.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: $CODENAME
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

rm -f /etc/apt/sources.list.d/ceph.sources
apt update
```

Effect: `apt update` is clean and pulls from `pve-no-subscription`.

## 3. Kill the subscription nag

The "No valid subscription" popup in the web UI is client-side JS in `proxmoxlib.js`, with no setting to disable it. You can `sed` it out, but every `proxmox-widget-toolkit` upgrade restores the original. So install an apt hook that re-patches it after each upgrade.

Create `/etc/apt/apt.conf.d/no-nag-script`:

```
DPkg::Post-Invoke { "dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\.js$'; if [ $? -eq 1 ]; then { echo 'Removing subscription nag from UI...'; sed -i '/.*data\.status\.toLowerCase().*/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi"; };
```

Or just write it **ON THE MACHINE** with a **quoted** heredoc, so the shell writes the hook verbatim instead of expanding `$?` and the backticks:

```
cat > /etc/apt/apt.conf.d/no-nag-script <<'EOF'
DPkg::Post-Invoke { "dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\.js$'; if [ $? -eq 1 ]; then { echo 'Removing subscription nag from UI...'; sed -i '/.*data\.status\.toLowerCase().*/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi"; };
EOF
```

It runs automatically during the upgrade in the next step. To apply it now without upgrading: `apt --reinstall install proxmox-widget-toolkit && systemctl restart pveproxy`.
Effect: the popup is gone. Confirm the patch took with `grep -c NoMoreNagging /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js` (expect `2`).

## 4. Upgrade + reboot

```
apt update && apt full-upgrade -y \
  -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
update-grub   # register the new kernel on GRUB / single-disk boxes
reboot
```

`confold` keeps our edited configs (the sshd changes above) instead of prompting. Target versions are in VERSIONS.md.
After reboot, `pveversion` and `uname -r` should match the fleet, and `apt list --upgradable` should be empty.

## 5. Prepare reused disks for passthrough (if any)

If the box has extra disks we pass through to a Talos VM for Longhorn (see PROXMOX-STORAGE.md), inventory and wipe them first. Reused drives often carry a whole old install, and stale LVM is a real hazard: a salvaged Proxmox boot disk brings its own volume group **also named `pve`**, which collides with the host's real one.

### Inventory

```
lsblk -d -o NAME,SIZE,ROTA,MODEL          # ROTA: 1 = HDD, 0 = SSD (this is your tier)
ls -l /dev/disk/by-id/ | grep -E 'sd[ab]$' # stable names; passthrough config uses these, never /dev/sdX
pvs                                        # healthy = one PV on the nvme; extras mean leftover LVM
ls /sys/block/sdX/holders/                 # empty = nothing is using it, safe to wipe
```

`/dev/sdX` names are assigned in boot-probe order and can renumber, so always reference disks by their `/dev/disk/by-id/` symlink (firmware identity, stable). A second PV in a VG named `pve` is the tell that a disk was a prior Proxmox boot disk.

### Wipe

Destructive. Target the reused data disks only, **never the nvme boot disk**.

```
wipefs -af /dev/sda /dev/sdb      # erase fs/LVM signatures
sgdisk --zap-all /dev/sda /dev/sdb # destroy the partition table
pvscan --cache && pvs              # refresh LVM cache; confirm only the real pve remains
```

Effect: bare disks, no duplicate-VG warnings. The by-id symlinks survive the wipe, so the paths you put in `pass_through_disks` stay valid. Talos formats and mounts them on first boot.

## Notes

- Unplug the old machine before reusing its IP. If `ssh` says `REMOTE HOST IDENTIFICATION HAS CHANGED`, the host key changed: run `ssh-keygen -R <ip>`, then reconnect.
- These are host-OS changes, outside the Terraform/ArgoCD scope, hence this manual doc.
