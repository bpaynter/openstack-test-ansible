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

- **RAM consolidation** to 32 / 16 / 16 / 16 GB (controller / 7060 / 5090 / 5080),
  using all 10× 8GB sticks including the two pulled from the retired 7050.
- **Disk placement:**
  - Controller (7071): 1× 250GB SATA SSD as the boot disk, no OSDs.
  - 7060: 1× 250GB SATA SSD boot + 3× 250GB SATA SSD as OSDs.
  - 5090 / 5080: 512GB NVMe boot + 1× 250GB SATA SSD as an OSD each.
- **Record the serial number of every SSD** so the boot disk and OSD disks can be
  positively identified at install time and in Phase 1.

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
- **Hostname:** set the real hostname at install time (`controller`, `compute1`,
  `compute2`, `compute3`) — ideally the full FQDN once the domain suffix is chosen.
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

- **Domain / DNS suffix** — `cluster.lab.internal` proposed (fallback `os.test`); not
  yet confirmed, so the FQDN form of each hostname is pending.
- **Exact subnet / IP block** — `192.168.1.10–.13` is the working example; the real
  home-LAN subnet must be confirmed and kept outside the router's DHCP pool.
- **Firewall on or off** — undecided; applies consistently across all four nodes once
  chosen.

## Actual work completed

No completion of the hardware prep or OS installs is explicitly reported in the
conversations processed so far. What is confirmed:

- The OS was committed to **AlmaLinux 9** (the user explicitly switched from
  AlmaLinux 10).
- The static-IP, no-DHCP networking approach was accepted.

_To be updated as later chunks provide evidence of the installs actually being
carried out._

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-22 | Phase 0 planning captured: AlmaLinux 9 Minimal Install, static networking, raw OSD disks, RAM consolidation, install-adjacent `/etc/hosts` setup. |
