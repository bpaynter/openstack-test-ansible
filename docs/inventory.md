# Hardware Inventory

Five retired Dell OptiPlex desktops were available. **Four are used** in the
cluster; the OptiPlex **5080 is retired** (its power supply died, and the retired
7050's PSU is not compatible) and serves as a parts donor — its 512GB NVMe and
2× 8GB RAM are salvaged. The 7050 is back in the cluster as the fourth node.

All machines originally shipped with 2× 8GB DDR4 sticks. All original HDDs/SSDs
were removed before the build, **except** the M.2 NVMe drives in the two SFF
machines (5090 and 5080).

## Machines

| Service Tag | Model | CPU | Cores/Threads | Form Factor | DIMM Slots | Original Drive (removed) | Cluster Role |
|---|---|---|---|---|---|---|---|
| GSLX243 | OptiPlex 7071 MT | i7-9700 | 8C / 8T (up to 4.7 GHz) | Mini Tower | 4 | 1TB SATA HDD | **Controller + Ceph MON/MGR** (`controller`) |
| 5MN6MR2 | OptiPlex 7060 MT | i7-8700 | 6C / 12T (up to 4.6 GHz) | Mini Tower | 4 | 1TB SATA HDD | **Compute + Ceph OSD** (`compute1`) |
| 6VVT1N3 | OptiPlex 5090 SFF | i7-10700 | 8C / 16T (up to 4.8 GHz) | Small Form Factor | 4 | — (512GB NVMe retained) | **Compute + Ceph OSD** (`compute2`) |
| 7SMVXM2 | OptiPlex 7050 MT | i7-7700 | 4C / 8T (up to 4.2 GHz) | Mini Tower | 4 | 500GB SATA HDD | **Compute + Ceph OSD** (`compute3`) |
| DMGWQ53 | OptiPlex 5080 SFF | i7-10700 | 8C / 16T (up to 4.8 GHz) | Small Form Factor | 4 | — (512GB NVMe retained) | **RETIRED — dead PSU; parts donor** |

The 7050's i7-7700 is the weakest CPU, but that matters far less for an I/O-bound
Ceph OSD node than for a compute node — so it is used mainly as an OSD/compute node
and leaned on as little as possible for VM scheduling.

**Hyperthreading** is left **enabled** (BIOS default) on the three compute nodes that
have it (7060, 5090, 7050); the 7071's i7-9700 has none. The thread counts above
reflect HT on. See [decisions.md](decisions.md) for the benchmarking caveat.

## RAM

- **Starting stock:** 10× 8GB DDR4 sticks (every machine had 2× 8GB).
- All four kept machines have **4 DIMM slots**.
- The retired 5080's 2 sticks are redistributed to the controller.

| Machine | Sticks | Total RAM |
|---|---|---|
| 7071 (controller) | 4× 8GB | **32 GB** |
| 7060 (compute/OSD) | 2× 8GB | 16 GB |
| 5090 (compute/OSD) | 2× 8GB | 16 GB |
| 7050 (compute/OSD) | 2× 8GB | 16 GB |

All 10 sticks are used. **Known constraint:** 16GB on the compute/OSD nodes is
tight once containers + OSDs + actual VMs are running — expect to launch small
flavors only. Upgrade path if needed: 2× 16GB sticks per node (slots are available).

## Storage

**Drives on hand:**

- **2× 512GB M.2 NVMe** — one still in the 5090 (its boot disk), one **harvested from
  the dead 5080** and moved to the 7071 as the controller's boot disk.
- **10× 250GB SATA SSDs** — loose, distributed across the cluster.

**Allocation:**

| Machine | OS / Boot disk | OSD disks | Notes |
|---|---|---|---|
| 7071 (controller) | 512GB NVMe (harvested from 5080) | None | NVMe boot helps the control plane (MariaDB, RabbitMQ, Keystone) |
| 7060 (compute/OSD) | 1× 250GB SATA SSD | **2× 250GB SATA SSD** | 3 SATA bays total: 1 boot + 2 OSD |
| 5090 (compute/OSD) | 512GB NVMe (its own) | **1× 250GB SATA SSD** | 1 free SATA bay |
| 7050 (compute/OSD) | 1× 250GB SATA SSD | **2× 250GB SATA SSD** | 3 SATA bays total: 1 boot + 2 OSD |

- **Ceph OSD topology:** 2 + 1 + 2 = **5 OSDs across 3 hosts** (7060 / 5090 / 7050).
  Better balanced than the original 3+1+1, and all 5 OSDs sit on **matched 250GB
  SATA SSDs** (keeping the harvested NVMe out of the pool avoids a heterogeneous pool
  that would muddy benchmarks).
- **SATA SSD usage:** 7 of 10 used (3 on the 7060, 1 on the 5090, 3 on the 7050),
  leaving **3 spares**. Both NVMe drives are in use (5090 + 7071 boot).
- **Spare hardware after build:** ~3× 250GB SATA SSDs, plus the entire retired 5080
  chassis.

**OSD disk handling at install time:** leave all OSD SATA SSDs completely **raw** —
no partitions, no filesystem (Ceph wants whole, empty block devices). The OS
installer must touch the **boot disk only**; explicitly deselect the OSD disks as
install targets. **Record the serial numbers of every SSD across all machines** so
the boot disk and the two OSD disks on each of the 7060 and 7050 can be positively
identified later (`lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,SERIAL`).

## Cabling

- The **7060** and **7050** each take **3 SATA SSDs total** (bay + power + data
  capacity) — this is the *total*, so it is split 1 boot + 2 OSD on each, not 3 OSDs
  plus a separate boot drive.
- The **5090 SFF** cleanly takes **one** SATA SSD (its single OSD); a second SATA SSD
  would require improvised power (110V→SATA adapters) — explicitly rejected (see
  [decisions.md](decisions.md)).
- The controller (7071) boots from NVMe and carries no SATA SSDs.

## Networking

- 4× 1G network ports available, one NIC per machine.
- A 10/100 switch is available but **not** used.
- **Static IP addressing, configured at install time — no DHCP.** See
  [project-plan.md](project-plan.md) and [decisions.md](decisions.md) for the
  rationale.

### Address plan

Domain suffix is **`lab.internal`**. Static IPs, confirmed:

| Machine | Hostname (FQDN) | IP |
|---|---|---|
| 7071 | `controller.lab.internal` | `192.168.1.130` |
| 7060 | `compute1.lab.internal` | `192.168.1.131` |
| 5090 | `compute2.lab.internal` | `192.168.1.132` |
| 7050 | `compute3.lab.internal` | `192.168.1.133` |

The 7050 is `compute3` because it is the weakest node. The subnet is
`192.168.1.0/24`; the block sits outside the home router's DHCP pool. With no DNS for
these names, every node carries the full hostname→IP map in `/etc/hosts`.

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-22 | Initial inventory documented from the 5 OptiPlex purchase-spec sheets. Selected 4 machines for the cluster; retired the 7050 as a parts donor. |
| 2026-05-22 | **Correction:** all 5 machines have **4 DIMM slots** (initially assumed the SFFs had only 2). This removed the "SFFs capped at 16GB" constraint and enabled full RAM consolidation. |
| 2026-05-22 | **Correction:** the **7071 and 7060** (not the 7050) are the machines that each take 3 SATA SSDs. The 7071 was confirmed as the controller and the 7050 retired. |
| 2026-05-22 | RAM consolidated to 32 / 16 / 16 / 16 (controller / 7060 / 5090 / 5080) using all 10 sticks. |
| 2026-05-23 | **5080 retired** (dead PSU; the 7050's PSU is incompatible). The **7050 returns** as the fourth node (`compute3`, compute + OSD). The 5080 becomes the parts donor instead of the 7050; its 512GB NVMe and 2× 8GB RAM are salvaged. RAM distribution stays 32/16/16/16, now on 7071/7060/5090/7050. |
| 2026-05-23 | Harvested 5080 NVMe placed in the **7071 as its boot disk** (controller now NVMe-boots); the 5090 keeps its own NVMe. |
| 2026-05-23 | **Correction:** "3 SATA SSDs" on the 7060/7050 is the **total** bay capacity (1 boot + 2 OSD), not 3 OSDs plus a separate boot disk. Earlier docs over-counted (following the chunk-01 build plan). OSD topology revised to **2 + 1 + 2 = 5 OSDs across 3 hosts** (was 3 + 1 + 1; same total of 5, better balanced). Spare SATA SSDs revised from ~4 to 3. |
| 2026-05-23 | Address plan confirmed (replacing the earlier example): domain **`lab.internal`**; `controller` .130/7071, `compute1` .131/7060, `compute2` .132/5090, `compute3` .133/7050. |
