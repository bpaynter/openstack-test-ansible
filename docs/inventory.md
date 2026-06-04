# Hardware Inventory

Five retired Dell OptiPlex desktops were available. **Four are used** in the
cluster; the OptiPlex 7050 is **retired** and serves as a parts donor (RAM and
SATA cabling).

All machines originally shipped with 2× 8GB DDR4 sticks. All original HDDs/SSDs
were removed before the build, **except** the M.2 NVMe drives in the two SFF
machines (5090 and 5080).

## Machines

| Service Tag | Model | CPU | Cores/Threads | Form Factor | DIMM Slots | Original Drive (removed) | Cluster Role |
|---|---|---|---|---|---|---|---|
| GSLX243 | OptiPlex 7071 MT | i7-9700 | 8C / 8T (up to 4.7 GHz) | Mini Tower | 4 | 1TB SATA HDD | **Controller + Ceph MON/MGR** |
| 5MN6MR2 | OptiPlex 7060 MT | i7-8700 | 6C / 12T (up to 4.6 GHz) | Mini Tower | 4 | 1TB SATA HDD | **Compute + Ceph OSD** |
| 6VVT1N3 | OptiPlex 5090 SFF | i7-10700 | 8C / 16T (up to 4.8 GHz) | Small Form Factor | 4 | — (512GB NVMe retained) | **Compute + Ceph OSD** |
| DMGWQ53 | OptiPlex 5080 SFF | i7-10700 | 8C / 16T (up to 4.8 GHz) | Small Form Factor | 4 | — (512GB NVMe retained) | **Compute + Ceph OSD** |
| 7SMVXM2 | OptiPlex 7050 MT | i7-7700 | 4C / 8T (up to 4.2 GHz) | Mini Tower | 4 | 500GB SATA HDD | **RETIRED — parts donor** |

## RAM

- **Starting stock:** 10× 8GB DDR4 sticks (every machine had 2× 8GB).
- All four kept machines have **4 DIMM slots**.
- The retired 7050's 2 sticks are redistributed to the controller.

| Machine | Sticks | Total RAM |
|---|---|---|
| 7071 (controller) | 4× 8GB | **32 GB** |
| 7060 (compute/OSD) | 2× 8GB | 16 GB |
| 5090 (compute/OSD) | 2× 8GB | 16 GB |
| 5080 (compute/OSD) | 2× 8GB | 16 GB |

All 10 sticks are used. **Known constraint:** 16GB on the compute/OSD nodes is
tight once containers + OSDs + actual VMs are running — expect to launch small
flavors only. Upgrade path if needed: 2× 16GB sticks per node (slots are available).

## Storage

**Drives on hand:**

- **2× 512GB M.2 NVMe** — already installed in the two SFF machines (5090, 5080);
  used as their boot/OS disks.
- **10× 250GB SATA SSDs** — loose, distributed across the cluster.

**Allocation:**

| Machine | OS / Boot disk | OSD disks |
|---|---|---|
| 7071 (controller) | 1× 250GB SATA SSD | None (storage kept off the controller) |
| 7060 (compute/OSD) | 1× 250GB SATA SSD | **3× 250GB SATA SSD** |
| 5090 (compute/OSD) | 512GB NVMe | **1× 250GB SATA SSD** |
| 5080 (compute/OSD) | 512GB NVMe | **1× 250GB SATA SSD** |

- **Ceph OSD topology:** 3 + 1 + 1 = **5 OSDs across 3 hosts**.
- **Spare hardware after build:** ~4× 250GB SATA SSDs, plus the entire retired 7050
  chassis.

## Cabling

- The **7071** and **7060** each have SATA power + data cables for **3 SSDs**.
- The **SFF machines (5090, 5080)** cleanly take **one** SATA SSD each. A second
  SATA SSD would require improvised power (110V→SATA adapters) — explicitly rejected
  (see [decisions.md](decisions.md)).
- The retired **7050** can donate a SATA power/data cable if the controller needs
  more.

## Networking

- 4× 1G network ports available, one NIC per machine.
- A 10/100 switch is available but **not** used.

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-22 | Initial inventory documented from the 5 OptiPlex purchase-spec sheets. Selected 4 machines for the cluster; retired the 7050 as a parts donor. |
| 2026-05-22 | **Correction:** all 5 machines have **4 DIMM slots** (initially assumed the SFFs had only 2). This removed the "SFFs capped at 16GB" constraint and enabled full RAM consolidation. |
| 2026-05-22 | **Correction:** the **7071 and 7060** (not the 7050) are the machines that each take 3 SATA SSDs. The 7071 was confirmed as the controller and the 7050 retired. |
| 2026-05-22 | RAM consolidated to 32 / 16 / 16 / 16 (controller / 7060 / 5090 / 5080) using all 10 sticks. |
