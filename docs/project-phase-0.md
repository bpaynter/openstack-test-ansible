# Phase 0 — Hardware Prep and OS Installation

Physical preparation of the four machines and a clean base OS on each, leaving every
node statically addressed, correctly named, and ready for the Phase 1 Ceph +
controller bring-up.

> **Status:** Planned. The processed conversations cover the planning of this phase
> in detail but contain **no explicit confirmation that the installs were completed**.
> The "Actual work completed" section will be filled in as evidence appears in later
> chunks.

See [inventory.md](inventory.md) for the hardware and address plan, and
[decisions.md](decisions.md) for the reasoning behind the OS and networking choices.

## Planned steps

### Hardware prep

- **RAM consolidation** to 32 / 16 / 16 / 16 GB (controller 7071 / 7060 / 5090 /
  7050), using all 10× 8GB sticks including the two pulled from the retired 5080.
- **Disk placement** (the 5080 is retired with a dead PSU; the 7050 is the fourth
  node; the 5080's 512GB NVMe is harvested into the 7071):
  - Controller (7071): 512GB NVMe (harvested from 5080) boot, no OSDs.
  - 7060: 1× 250GB SATA SSD boot + 2× 250GB SATA SSD OSDs (3 SATA bays total).
  - 5090: 512GB NVMe boot + 1× 250GB SATA SSD OSD.
  - 7050: 1× 250GB SATA SSD boot + 2× 250GB SATA SSD OSDs (3 SATA bays total).
  - OSD topology: 2 + 1 + 2 = 5 OSDs across 3 hosts.
- **Record the serial number of every SSD** so the boot disk and OSD disks can be
  positively identified at install time and in Phase 1.
- **BIOS:** leave **hyperthreading enabled** (default) on the compute nodes (7060,
  5090, 7050); the 7071 has none. See [decisions.md](decisions.md).

### OS install (per node) — AlmaLinux 9, Minimal Install

- **Software selection:** Minimal Install (both the manual install and Kolla assume a
  lean base).
- **Partitioning / boot disk:** keep it simple — a single root partition; do not let
  the installer carve out a large `/home` or consume the whole disk with an awkward
  LVM layout. The installer must touch the **boot disk only**.
- **OSD disks:** leave completely **raw** — no partitions, no filesystem. If the
  installer auto-detects them, explicitly **deselect** them as install targets.
- **Swap:** give each node a modest swap (a few GB) as a pressure-relief valve; plan
  to set `vm.swappiness` low later (post-install sysctl) so the 16GB nodes don't swap
  out OSD/nova memory under pressure.
- **Hostname:** set the full FQDN at install time —
  `controller.lab.internal`, `compute1.lab.internal` (7060),
  `compute2.lab.internal` (5090), `compute3.lab.internal` (7050).
- **Network:** configure the NIC as **static / manual** in the installer (IP,
  netmask, gateway, DNS per the address plan) and set it to connect automatically. No
  DHCP transaction ever happens, which is exactly the isolation wanted.
- **SELinux:** leave **enforcing** (RDO and Kolla both ship SELinux policy and expect
  it on).
- **Users / SSH:** create the admin user and, if possible, paste your SSH public key
  during install — passwordless SSH from the workstation to all four nodes is a
  prerequisite for the Phase 2 Ansible work and for Kolla.

### Post-install (install-adjacent)

- Populate `/etc/hosts` on **every** node with all four hostname→IP mappings (no DNS
  exists for these names).
- Check for and fix the installer's habit of mapping the hostname to `127.0.0.1` /
  `::1`. A Ceph MON bound to loopback is useless to peers — each node's hostname must
  resolve to its real LAN IP; loopback lines should map to `localhost` only.

## Open / unconfirmed for Phase 0

All Phase 0 open items have since been settled (at the start of Phase 1 — see
[project-phase-1.md](project-phase-1.md)):

- **Gateway / DNS** → addresses on `192.168.1.0/24` (.130–.133); name resolution is
  purely local `/etc/hosts` (no DNS), with the normal LAN gateway for outbound.
- **Firewall** → **firewalld disabled**.
- **SELinux** → **enforcing**.

## Actual work completed

Phase 0 was carried out — the Phase 1 work runs on the real, installed nodes, which is
indirect but strong evidence the hardware prep and OS installs were completed:

- All four nodes run **AlmaLinux 9** with their static `lab.internal` addresses
  (Ceph bootstrapped on the controller at 192.168.1.130; OSD hosts enrolled at
  .131/.132/.133).
- The post-PSU-failure hardware layout was realized (7050 in service as `compute3`;
  the controller's NVMe boot; the 2+1+2 OSD disk placement).
- One disk-prep wrinkle surfaced in Phase 1: compute3's two OSD SSDs were left over
  from an old mdadm RAID array (`md127`) and had to be cleared before Ceph would use
  them — see [project-phase-1.md](project-phase-1.md).

Not separately evidenced in the conversations: the exact partition/swap choices and
whether SSH keys were pasted at install time vs. generated later (the Phase 1 base-OS
prep generates the SSH keys regardless).

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-22 | Phase 0 planning captured: AlmaLinux 9 Minimal Install, static networking, raw OSD disks, RAM consolidation, install-adjacent `/etc/hosts` setup. |
| 2026-05-23 | Updated hardware prep for the PSU failure: 5080 retired, 7050 added as `compute3`, 512GB NVMe harvested into the 7071 boot, OSD topology 2+1+2. Confirmed FQDNs/IPs on `lab.internal` (.130–.133). |
| 2026-05-23 | Marked the Phase 0 open items (firewall, SELinux, gateway/DNS) resolved (settled at the start of Phase 1); recorded the BIOS hyperthreading decision. |
| 2026-05-23 | Updated "actual work completed" from "not yet evidenced" to **carried out**, based on Phase 1 running on the real installed nodes. |
