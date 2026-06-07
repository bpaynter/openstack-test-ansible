# Project Plan

## Goals

- **Learn how OpenStack and Ceph work** by building a real (if small) cluster.
- **Learn Ansible** along the way, with a deliberate transition point from manual
  work into automation.
- **Run benchmarks** on the cluster, then **tear it down** after a few days. This is
  a temporary test cluster, not a permanent deployment.

## Parameters / Rules / Guidelines

The concrete constraints below operationalize the project's guiding philosophy — see
[project-principles.md](project-principles.md) for the *why*.

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

### Phase 1 — Ceph and the controller node, by hand — **complete**

Build the storage and control plane by hand to learn what the services *are*.
Details and execution log in [project-phase-1.md](project-phase-1.md).

- Bootstrap Ceph with **cephadm** (Ceph Squid 19.2.x), enroll all hosts, place the
  5 OSDs (2+1+2), and create the `images` RBD pool for Glance. (The `volumes`/`vms`
  pools for Cinder/Nova are deferred — those services aren't part of Phase 1.)
- On the controller (7071), manually install and wire up a minimal OpenStack control
  plane: **Keystone, Glance (Ceph RBD backend), Placement** — plus its supporting
  cast (RabbitMQ, MariaDB, memcached) — following the OpenStack 2025.1 install guide.
- Outcome: understand Keystone tokens, the Glance→Ceph RBD integration, and why
  Placement exists.

### Phase 2 — Compute nodes with hand-rolled Ansible — **in progress**

Adding nova-compute + Neutron agents to the 7060, 5090, and 7050 is the *same steps
three times* — the natural seam to introduce Ansible. No teardown; the controller
keeps its Phase 1 services. Done in stages 0–5; **Stages 0–1 (Ansible control node +
inventory) are complete.** Details and step plan in
[project-phase-2.md](project-phase-2.md).

- Controller-side Nova/Neutron is done **manually** (one-time, not repeated); the
  repetitive compute-node work becomes idempotent Ansible roles (`nova_compute`,
  `neutron_compute`) looped across the compute group. Taught learning-first: a
  throwaway `common` role establishes `template`/idempotence before Nova/Neutron.
- **Tenant networking is VXLAN self-service** (Linux bridge): VMs on tunneled tenant
  networks, a Neutron router NATing to a flat provider/external network, and floating
  IPs — chosen to keep VM DHCP off the home LAN without a managed switch. The
  controller becomes the network node.
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
- **RDO repo for 2025.1 on EL9** → `centos-release-openstack-epoxy` (worked; Keystone,
  Glance, and Placement installed and run).
- **Ceph release for `cephadm`** → **Squid 19.2.x** (cephadm default). RDO Epoxy was
  validated against Reef 18.2.0 — skew noted, no problems in Phase 1.
- **Name resolution / gateway** → local `/etc/hosts` on all nodes, no DNS; normal LAN
  gateway for outbound.
- **Firewall** → **firewalld disabled**. **SELinux** → **enforcing**.

Phase 0 and Phase 1 are complete. **Phase 2 implementation open items** (to settle in
the Phase 2 chat):

- **Tenant subnet CIDR** (e.g. `10.0.0.0/24`).
- **Floating-IP allocation pool** from `192.168.1.0/24`, confirmed against the home
  router's DHCP range and the static host IPs.
- **VXLAN MTU handling** (raise underlay MTU vs. tenant network MTU 1450).
- **Nova ephemeral disk backend** — local qcow2 vs. a Ceph RBD `vms` pool.
- **`kvm` vs `qemu`** — `kvm` expected (VT-x i7s), pending a BIOS-virtualization check
  per node.

The remaining phases are Phase 2 (compute nodes via hand-rolled Ansible) and Phase 3
(Kolla-Ansible rebuild).

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
| 2026-05-23 | Phase 1 completed. Resolved the last open items (RDO Epoxy repo, Ceph Squid 19.2.x, local `/etc/hosts`/gateway, firewall disabled, SELinux enforcing) — no planning open items remain. Marked Phase 1 done and corrected its Ceph-pool note (only `images` created; `volumes`/`vms` deferred). |
| 2026-05-23 | Phase 2 designed: added VXLAN self-service networking and the network-node role to the Phase 2 description; added Phase 2 implementation open items (tenant CIDR, floating-IP pool, MTU, Nova disk backend, kvm/qemu). Phases 0–3 left unchanged (a momentary "Kolla dropped" framing in the source chat was a confusion — Phase 3 remains planned). |
| 2026-05-23 | Refined the Phase 2 method to learning-first/manual-controller-side: controller Nova/Neutron done by hand, only the compute work as Ansible roles. |
| 2026-05-24 | Marked Phase 2 in progress — Stages 0–1 (Ansible control node + inventory) complete. |
