# Project Plan

## Goals

- **Learn how OpenStack and Ceph work** by building a real (if small) cluster.
- **Learn Ansible** along the way, with a deliberate transition point from manual
  work into automation.
- **Run benchmarks** on the cluster, then **tear it down** after a few days. This is
  a temporary test cluster, not a permanent deployment.

## Parameters / Rules / Guidelines

- **Temporary lifespan.** The cluster exists for a few days — build, benchmark, tear
  down. Decisions favor "interesting and representative for benchmarking" over
  long-term durability.
- **4 machines, 4× 1G ports**, one NIC per host. This matches the available network
  ports exactly.
- **Stay on 1G networking.** A 10/100 switch is available but explicitly **not**
  used — 100Mbit would make Ceph recovery painful and teach the wrong lessons.
- **Single flat network** carries both Ceph replication and OpenStack traffic. This
  is accepted and is itself instructive — Ceph recovery/rebalance will saturate the
  1G link, which is an intended observable, not a problem to fix.
- **Ceph uses default 3× replication with a `host` failure domain.** This drives the
  minimum of 3 OSD hosts.
- **Small VM flavors only.** 16GB on the compute/OSD nodes is tight once containers,
  OSDs, and VMs are all running.
- **Learning is prioritized over speed.** The cluster is intentionally built up by
  hand and then rebuilt (see phases below); this is not the fastest path to a
  running cluster, and that is the point.
- **OS: AlmaLinux 9, Minimal Install, SELinux enforcing** on all four nodes.
- **Static IP addressing, no DHCP.** Nodes use hard-coded static IPs configured at
  install time; no DHCP server is run and no DHCP reservations are used, so the
  cluster cannot interfere with the home network it is plugged into.
- **Keep tenant networking on overlays.** Tenant networks use VXLAN/Geneve overlays.
  If a provider network is ever added, it must get its own VLAN — never the untagged
  home LAN — so Neutron's dnsmasq cannot start answering DHCP for the whole house.
- **Single Ceph MON on the controller (accepted SPOF).** The controller is a single
  point of failure for both the OpenStack control plane and Ceph; acceptable given
  the days-long lifespan, recorded as a deliberate choice.
- **Tune `osd_memory_target` down (~1.5–2GB).** The 4GB default is too much for the
  16GB OSD nodes; the lower target is baked into the Ceph config from the start.

## Phases

The cluster is built up by hand and then rebuilt, each phase motivated by the
friction of the previous one. Phases are numbered 0–3.

### Phase 0 — Hardware prep and OS installation

Physical preparation and a clean base OS on all four nodes. RAM consolidation
(32/16/16/16), boot/OSD disk placement, and a fresh **AlmaLinux 9 Minimal Install**
with static networking on every node. Details and execution log in
[project-phase-0.md](project-phase-0.md).

### Phase 1 — Ceph and the controller node, by hand

Build the storage and control plane by hand to learn what the services *are*.

- Bootstrap Ceph with **cephadm** (Ceph Squid 19.x), enroll all hosts, place the
  5 OSDs, and create the `images`/`volumes`/`vms` pools for OpenStack.
- On the controller (7071), manually install and wire up a minimal OpenStack control
  plane: **Keystone, Glance (Ceph RBD backend), Placement** — plus its supporting
  cast (RabbitMQ, MariaDB, memcached) — following the OpenStack install guide.
- Outcome: understand Keystone tokens, the Glance→Ceph RBD integration, and why
  Placement exists.
- Planned as 8 sections (host prep → Ceph bootstrap → OSDs → pools/RBD → OpenStack
  prereqs → Keystone → Glance → Placement).

### Phase 2 — Compute nodes with hand-rolled Ansible

Adding nova-compute + Neutron agents to the 7060, 5090, and 7050 is the *same steps
three times* — the natural seam to introduce Ansible.

- Write playbooks to add the three compute nodes.
- The manual steps are already known, so this is "translate known work into
  playbooks" — learning Ansible without simultaneously learning OpenStack.

### Phase 3 — Full teardown and rebuild with Kolla-Ansible

Tear down and redeploy the whole cluster with Kolla-Ansible.

- Ansible is now concrete, not abstract.
- Reading Kolla's playbooks, every service is recognizable from the manual phase.
- Teardown is clean (containers), which suits the temporary nature of the cluster.

## Open Items

Settled:

- **OS choice** → **AlmaLinux 9** (switched from an initial lean toward AlmaLinux 10).
- **OpenStack release** → **2025.1 "Epoxy"**.
- **Phase 1 Ceph method** → **cephadm** bootstrap (Ceph Squid 19.x; Reef 18.x fallback).
- **Domain / DNS suffix** → **`lab.internal`** (FQDNs `controller`/`compute1–3.lab.internal`).
- **Static IPs** (subnet `192.168.1.0/24`) → `controller` .130 (7071), `compute1` .131
  (7060), `compute2` .132 (5090), `compute3` .133 (7050).

Still open:

- **RDO / package repository setup** for OpenStack 2025.1 on AlmaLinux 9 — verify
  repo availability/completeness as the first real Phase 1 step.
- **Ceph release to pair with `cephadm`** — the version cephadm pulls by default vs.
  an explicitly pinned release (Squid 19.x intended).
- **Gateway / DNS specifics** — whether name resolution is purely local `/etc/hosts`
  or a real DNS server is still to confirm.
- **Firewall on or off** and **SELinux posture** — firewall left undecided (assistant
  leaned toward leaving firewalld on); SELinux planned as enforcing but flagged for a
  deliberate decision in implementation.

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-22 | Initial project plan created: goals, 4-machine layout, 1G-only networking, and the 3-phase (manual → hand-rolled Ansible → Kolla-Ansible) progression. |
| 2026-05-22 | Considered and rejected dropping to a 3-machine layout; kept all 4 machines (see [decisions.md](decisions.md)). |
| 2026-05-22 | Confirmed the 3-phase progression over a Kolla-only build, despite the temporary nature of the cluster, because learning Ansible is an explicit goal. |
| 2026-05-22 | Renumbered the phases to a 0–3 scheme: Phase 0 (hardware prep + OS install), Phase 1 (Ceph + controller by hand), Phase 2 (compute nodes via hand-rolled Ansible), Phase 3 (Kolla rebuild). Previously the docs labelled these "Phase 1 / transition / Phase 2". |
| 2026-05-22 | Resolved three former open items: OS → AlmaLinux 9 (was leaning AlmaLinux 10), OpenStack release → 2025.1 "Epoxy", Phase 1 Ceph method → cephadm. |
| 2026-05-23 | Resolved the domain (`lab.internal`) and static IPs (`.130–.133`); replaced them as open items with the remaining ones (RDO repo for 2025.1 on EL9, Ceph release pairing for cephadm, CIDR/gateway/DNS specifics, firewall/SELinux posture). Updated the Phase 2 compute-node list (5080 → 7050) for the PSU-failure hardware swap. |
