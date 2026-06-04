# Hardware Inventory

This document describes the physical hardware that makes up the cluster: which
machines are used in which role, how RAM and disks are distributed, and the
network addressing.

For the project plan, phases, and decision history, see
[`overall_plan.md`](overall_plan.md).

---

## 1. Machines

Five Dell OptiPlex desktops were available. **Four are used.** The OptiPlex
5080 was the intended fourth node but its power supply failed and no
compatible PSU was available; it is retired and serves as a parts donor (M.2
NVMe + RAM). The OptiPlex 7050 takes its place.

| Machine | Model | CPU | Cores/Threads | Form Factor | Role |
|---|---|---|---|---|---|
| GSLX243 | OptiPlex 7071 MT | i7-9700 | 8C / 8T | Mini Tower | **Controller** |
| 5MN6MR2 | OptiPlex 7060 MT | i7-8700 | 6C / 12T | Mini Tower | **Compute + OSD** |
| 6VVT1N3 | OptiPlex 5090 SFF | i7-10700 | 8C / 16T | Small Form Factor | **Compute + OSD** |
| 7SMVXM2 | OptiPlex 7050 MT | i7-7700 | 4C / 8T | Mini Tower | **Compute + OSD** |
| DMGWQ53 | OptiPlex 5080 SFF | i7-10700 | 8C / 16T | Small Form Factor | **RETIRED — dead PSU, donor** |

**HT note:** The three compute nodes have hyperthreading **enabled** (a
deliberate choice — more logical CPUs for a RAM-constrained cluster, accepting
the variance for CPU-bound benchmarks). The controller's i7-9700 has no HT at
all. CPU-bound benchmark results should be interpreted with this in mind.

## 2. Disk inventory

- 2× 512GB M.2 NVMe — one in the 5090 (its own), one harvested from the
  retired 5080 and installed in the controller.
- 10× 250GB SATA SSDs — distributed across the build (7 in use, 3 spare).

**SATA capacity constraint:** The 7060 and 7050 each support **3 SATA SSDs
total** (bays + cabling) — this is the total, inclusive of the boot disk, not
3 plus a boot disk. This is what limits each tower to 2 OSDs.

## 3. RAM consolidation

Starting point was 10× 8GB DDR4 sticks (every machine had 2×8GB). All four
kept machines have 4 DIMM slots. The retired 5080's 2 sticks were harvested
and redistributed.

| Machine | Sticks | Total RAM | Rationale |
|---|---|---|---|
| 7071 (controller) | 4× 8GB | **32 GB** | Runs control plane + Ceph MON/MGR + network node — most always-on services |
| 7060 (compute/OSD) | 2× 8GB | 16 GB | Compute + 2 OSDs |
| 5090 (compute/OSD) | 2× 8GB | 16 GB | Compute + 1 OSD |
| 7050 (compute/OSD) | 2× 8GB | 16 GB | Compute + 2 OSDs |

All 10 sticks used. **Known constraint:** 16 GB on the compute/OSD nodes is
tight once containers + OSDs + actual VMs are running — expect to launch
small flavors only. Acceptable for a short-lived benchmark cluster. Upgrade
path if needed: 2×16GB sticks per node (slots are available).

## 4. Role and disk assignment

The 7060 and 7050 hold 3 SATA SSDs total each; one of those three is the
boot disk, leaving 2 OSDs each. The towers cannot all NVMe-boot (only 2
NVMe drives exist and the controller takes one), so SATA boot on the
compute towers is accepted.

| Machine | Role | OS / Boot disk | OSD disks |
|---|---|---|---|
| **7071** | Controller + Ceph MON/MGR + network node | 512GB NVMe (harvested from 5080) | None |
| **7060** | Compute + Ceph OSD | 1× 250GB SATA SSD | **2× 250GB SATA SSD** |
| **5090** | Compute + Ceph OSD | 512GB NVMe (its own) | **1× 250GB SATA SSD** |
| **7050** | Compute + Ceph OSD | 1× 250GB SATA SSD | **2× 250GB SATA SSD** |

**Ceph OSD topology:** 2 + 1 + 2 = **5 OSDs across 3 hosts.** This satisfies
the default 3× replication with `host` failure domain (3 OSD hosts is the
minimum). Uses 7 of the 10 SATA SSDs; **3 spares** remain.

**Disk decisions and rationale:**
- *Harvested NVMe → 7071 boot.* The controller is the one node where
  root-disk latency materially helps — MariaDB, RabbitMQ, and Keystone
  token operations all live there and are touched by every API call.
- *7060 / 7050 boot from SATA SSD.* Their OS disks do nothing
  performance-critical; NVMe would be wasted there.
- *All OSDs on matched 250GB SATA SSDs.* Mixing an NVMe-backed OSD into an
  otherwise all-SATA pool would create a heterogeneous pool and muddy
  benchmark results. Keep the pool uniform.

## 5. Networking

Static IPs on a single flat 1G underlay, one NIC per host. Domain:
`lab.internal`.

| Hostname | IP | Machine | CPU |
|---|---|---|---|
| `controller.lab.internal` | 192.168.1.130 | 7071 MT | i7-9700, 8C/8T |
| `compute1.lab.internal` | 192.168.1.131 | 7060 MT | i7-8700, 6C/12T |
| `compute2.lab.internal` | 192.168.1.132 | 5090 SFF | i7-10700, 8C/16T |
| `compute3.lab.internal` | 192.168.1.133 | 7050 MT | i7-7700, 4C/8T |

Notes:
- The 7050 is mapped to `compute3` as it is the weakest node; the mapping is
  otherwise arbitrary but is now fixed for consistency across phases.
- The single physical `192.168.1.0/24` link carries Ceph replication,
  OpenStack management/API traffic, **and** (in Phase 2) VXLAN tunnel
  traffic. Expect Ceph recovery to saturate the 1G link; this is an intended
  observable, not a problem to fix.
- A 10/100 switch is available but explicitly **not** used.

### Tenant networking model — VXLAN self-service

Phase 2 uses **VXLAN self-service networking** with the **Linux bridge**
mechanism driver. VMs live on isolated tenant networks tunneled inside
VXLAN-encapsulated UDP over the physical underlay. A Neutron router NATs to
a flat provider/external network on `192.168.1.0/24`, and floating IPs
provide 1:1 NAT for external reachability.

This model was chosen because flat provider networking would put VM DHCP on
the same L2 broadcast domain as the home router's DHCP server, causing a
dual-DHCP race. VXLAN isolates VM DHCP inside the overlay so only the
Neutron DHCP agent can respond, achieving the same result as VLAN isolation
without requiring a managed switch.

The controller (7071) is also the **network node**: it runs the Neutron L3,
DHCP, and metadata agents.

## 6. Spare hardware

- 3× 250GB SATA SSDs (unused).
- The retired OptiPlex 5080 chassis (dead PSU, M.2 and RAM already harvested).
