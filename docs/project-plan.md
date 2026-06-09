# Project Plan

## Goals

- **Learn how OpenStack and Ceph work** by building a real (if small) cluster.
- **Learn Ansible** along the way, with a deliberate transition point from manual
  work into automation.
- **Run benchmarks** on the cluster, then **tear it down** after a few days. This is
  a temporary test cluster, not a permanent deployment.

## Parameters / Rules / Guidelines

The key operating constraints, at a glance. The full reasoning for each is in
[decisions.md](decisions.md); the guiding philosophy behind them is in
[project-principles.md](project-principles.md).

- **Temporary cluster** — build, benchmark, tear down within a few days.
- **4 nodes, one 1G NIC each; stay on 1G** (the 10/100 switch is deliberately unused).
- **Single flat underlay** carries Ceph, OpenStack management, and (from Phase 2) VXLAN
  traffic; it is expected to saturate during Ceph recovery — an intended observable.
- **Ceph 3× replication, `host` failure domain** → 3 OSD hosts minimum.
- **Small VM flavors only** — the 16GB compute/OSD nodes are tight.
- **OS: AlmaLinux 9 Minimal, SELinux enforcing; firewalld disabled.**
- **Static IPs, no DHCP**, on `lab.internal` — so the cluster can't interfere with the
  home network. (Address plan in [inventory.md](inventory.md).)
- **Tenant networking: VXLAN self-service** (Linux bridge) — keeps VM DHCP off the home
  LAN without a managed switch.
- **4 Ceph MONs** (cephadm auto-placed one per host; not the single MON originally
  planned — see [decisions.md](decisions.md) #15); **`osd_memory_target` ~1.5–2 GB.**
- **Learning prioritized over speed** — built by hand, then rebuilt (see phases).

## Phases

The cluster is built up by hand and then rebuilt, each phase motivated by the
friction of the previous one. Phases are numbered 0–3.

### Phase 0 — Hardware prep and OS installation

Physical preparation and a clean base OS on all four nodes. RAM consolidation
(32/16/16/16), boot/OSD disk placement, and a fresh **AlmaLinux 9 Minimal Install**
with static networking on every node. Details and execution log in
[project-phase-0.md](project-phase-0.md).

### Phase 1 — Ceph and the controller node, by hand — **complete**

Build the storage and control plane by hand: `cephadm` Ceph (5 OSDs, 2+1+2) plus a
manual OpenStack 2025.1 control plane (Keystone, Glance on Ceph RBD, Placement) on the
controller. Full steps, config notes, and execution log in
[project-phase-1.md](project-phase-1.md).

### Phase 2 — Compute nodes with hand-rolled Ansible — **in progress**

Add Nova + Neutron to the existing cluster with hand-rolled Ansible (no teardown) —
controller-side bring-up by hand, the repetitive compute work as idempotent roles, and
**VXLAN self-service** tenant networking. Done in stages 0–5; **Stages 0–2 complete,
Stage 3 next.** Full design, step plan, and execution log in
[project-phase-2.md](project-phase-2.md).

### Phase 3 — Full teardown and rebuild with Kolla-Ansible

Tear down and redeploy the whole cluster with Kolla-Ansible.

- Ansible is now concrete, not abstract.
- Reading Kolla's playbooks, every service is recognizable from the manual phase.
- Teardown is clean (containers), which suits the temporary nature of the cluster.

## Open Items

All earlier planning questions (OS, OpenStack release, Ceph method/version, domain,
static IPs, RDO repo, name resolution, firewall, SELinux) are **settled** — each is
recorded with its rationale in [decisions.md](decisions.md).

The remaining open items are Phase 2 implementation choices (tenant CIDR, floating-IP
pool, VXLAN MTU, Nova disk backend, `kvm`/`qemu`), tracked in
[project-phase-2.md](project-phase-2.md#open-items-for-phase-2-implementation).

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
| 2026-06-04 | Stage 2 (throwaway `common` role) in progress. |
| 2026-06-07 | Consistency/dedup pass: trimmed Parameters and the Phase 1/2 descriptions to brief summaries; replaced the "settled" recap and the Phase 2 open-items list with pointers to [decisions.md](decisions.md) and [project-phase-2.md](project-phase-2.md); fixed the stale "provider-on-its-own-VLAN" tenant-networking item to the VXLAN model. |
| 2026-06-08 | Marked Phase 2 **Stages 0–2 complete** (the throwaway `common` role is done and idempotent); **Stage 3** (manual controller-side Nova/Neutron) is next. Corrected the Parameters MON count to **4** (cephadm default placement; see [decisions.md](decisions.md) #15), superseding the single-MON note. |
