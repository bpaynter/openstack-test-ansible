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
| 7 | Deployment method | **Phase 0 (prep/OS) → Phase 1 (manual Ceph + controller) → Phase 2 (hand-rolled Ansible compute) → Phase 3 (Kolla-Ansible rebuild)** | Explicit phased learning progression; each phase is motivated by the friction of the previous one. |
| 8 | Cluster lifespan | **Temporary (a few days)** | Build, benchmark, tear down. This is a test/learning cluster, not a permanent deployment. |
| 9 | Operating system | **AlmaLinux 9**, Minimal Install, SELinux enforcing | Switched from an initial lean toward AlmaLinux 10: RDO's EL10 packaging was still maturing in early 2026, which would bite the manual Phase 1 install hard. EL9 has mature, well-trodden RDO repos. |
| 10 | OpenStack release | **2025.1 "Epoxy"** | Recent release with complete, stable RDO/EL9 repos and lots of install-guide coverage — the sweet spot on EL9. |
| 11 | Ceph version | **Squid (19.x)** (Reef 18.x acceptable fallback) | Pairs with Epoxy-era OpenStack; installed via `centos-release-ceph-squid` on EL9. |
| 12 | Ceph bootstrap method | **cephadm** | Chosen by the user over the assistant's lean toward a fully-manual MON/MGR/OSD bring-up. Trade-off on record: cephadm is itself a container-orchestration layer, so Kolla in Phase 3 becomes the *second* such layer, not the first. Learning value holds because daemons are still placed by hand. |
| 13 | IP addressing | **Static IPs, no DHCP, no reservations** | Deterministic, always-known addressing (Ceph MONs configured by IP, Keystone endpoints are URLs, Kolla inventory is IP-based). Avoids dependence on the home router's lease table and guarantees no interference with the home network. Working example: controller .10, compute1 .11, compute2 .12, compute3 .13 (subnet TBD). |
| 14 | Tenant networking | **Overlays (VXLAN/Geneve) only; provider nets on their own VLAN** | Keeps Neutron's dnsmasq off the untagged home LAN so it cannot answer DHCP for the whole house. |
| 15 | Ceph MON quorum | **Single MON on the controller (accepted SPOF)** | Recorded as a deliberate choice, not an oversight: the controller is a single point of failure for both Ceph and the OpenStack control plane. Acceptable for a days-long cluster. |
| 16 | OSD memory target | **Lowered to ~1.5–2GB** (from the 4GB default) | The 16GB OSD nodes cannot afford 4GB BlueStore cache per OSD; baked into the Ceph config from the start. |

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
| 2026-05-22 | Reworded decision #7 (deployment method) to use the 0–3 phase numbering. |
