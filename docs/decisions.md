# Decisions

Decisions made during planning and execution, with the reasoning behind each.

## Decisions taken

| # | Decision | Choice | Reason |
|---|---|---|---|
| 1 | Number of machines | **4** | Matches the 4 available 1G ports exactly; a 4th machine adds real value (3 OSD hosts + multiple compute nodes) over a 3-machine layout. |
| 2 | Machine to retire | **7050** (i7-7700) | Weakest CPU by a clear margin (4C/8T, oldest generation). Becomes a parts donor (RAM + SATA cabling). |
| 3 | Controller | **7071** | 8 cores, mini-tower chassis with 3 SATA bays, and gets the most RAM. The natural "brain" of the cluster. |
| 4 | RAM split | **32 / 16 / 16 / 16** GB | The controller is the most service-dense node (control plane + Ceph MON/MGR), so it gets 32GB. Uses all 10 sticks (4+2+2+2). |
| 5 | Ceph OSD layout | **5 OSDs across 3 hosts (3 + 1 + 1)** | Minimum for default 3× replication with a `host` failure domain. The 7060 carries 3 OSDs; each SFF carries 1. Lopsided, but Ceph handles it via CRUSH weighting, and watching it rebalance is part of the learning value. |
| 6 | Network speed | **1G, flat** | 10/100 is too slow for Ceph replication; a single flat network is fine for a learning cluster. Ceph saturating the 1G link is an intended, instructive observable. |
| 7 | Deployment method | **Manual → hand-rolled Ansible → Kolla-Ansible** | Explicit 3-phase learning progression; each phase is motivated by the friction of the previous one. |
| 8 | Cluster lifespan | **Temporary (a few days)** | Build, benchmark, tear down. This is a test/learning cluster, not a permanent deployment. |

## Decisions deliberately NOT taken (rejected options)

| # | Option considered | Verdict | Reason |
|---|---|---|---|
| R1 | Frankenstein power (110V→SATA adapters) for a 2nd SATA SSD in the SFFs | **Rejected** | External power bricks dangling from a sealed SFF chassis is a corruption risk that works for a week then quietly fails. A learning cluster does not need balanced OSDs, and the "really good reason" bar isn't met. |
| R2 | Drop the 7060 to free RAM (3-node, 4/4/2 sticks) | **Rejected** | Would cut Ceph to 2 OSD hosts — cannot satisfy 3× replication with a `host` failure domain — and would lose a 6-core compute node. The RAM gain (one node from 16→32GB) doesn't justify crippling the storage layer. |
| R3 | Use the 10/100 switch instead of 1G ports | **Rejected** | Ceph recovery over 100Mbit would be painful and teach bad latency lessons. Stay on 1G. |
| R4 | Kolla-Ansible-only build (skip the manual + hand-rolled Ansible phases) | **Rejected** | Although tempting given the temporary cluster, learning Ansible and OpenStack internals is an explicit goal, so the 3-phase progression was kept. |

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-22 | Initial decision log recorded (machine count, retired machine, controller, RAM split, Ceph layout, networking, deployment method, lifespan). |
| 2026-05-22 | Recorded rejected options: Frankenstein SFF power, dropping the 7060, the 10/100 switch, and a Kolla-only build. |
