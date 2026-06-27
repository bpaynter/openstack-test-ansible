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
- **Tenant networking: VXLAN self-service** (Open vSwitch) — keeps VM DHCP off the home
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

### Phase 2 — Compute nodes with hand-rolled Ansible — **complete**

Add Nova + Neutron (and, at the end, Cinder block storage) to the existing cluster with
hand-rolled Ansible (no teardown) — controller-side bring-up by hand, the repetitive
compute work as idempotent roles, and **VXLAN self-service** tenant networking, with
VMs and volumes both backed by Ceph RBD. Built in **stages 0–6, all complete**: the
`nova_compute`/`neutron_compute` roles brought up 3 cell-mapped hypervisors (RBD-backed
ephemeral) with tunnel-only OVS agents; a CirrOS VM runs on the VXLAN overlay and is
reachable from the home LAN via a floating IP; and **Cinder** (controller-side, RBD-backed
`volumes` pool, reusing the `client.nova` libvirt secret) serves persistent volumes —
verified by attaching one to the VM. Full design, step plan, and execution log in
[project-phase-2.md](project-phase-2.md).

### Phase 3 — Full teardown and rebuild with Kolla-Ansible — **next**

Tear down and redeploy the whole cluster with Kolla-Ansible.

- Ansible is now concrete, not abstract.
- Reading Kolla's playbooks, every service is recognizable from the manual phase.
- Teardown is clean (containers), which suits the temporary nature of the cluster.

## Open Items

All earlier planning questions (OS, OpenStack release, Ceph method/version, domain,
static IPs, RDO repo, name resolution, firewall, SELinux) are **settled** — each is
recorded with its rationale in [decisions.md](decisions.md).

No planning open items remain. The Stage-5 networking choices (tenant CIDR, floating-IP
pool, VXLAN MTU) were resolved at the start of Stage 5 ([decisions.md](decisions.md) #39),
as `kvm`/`qemu` and `ansible-vault` were in Stage 4 (#36/#37). Tracked in
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
| 2026-06-09 | Closed the **Nova ephemeral disk backend** open item → **Ceph RBD-backed** ([decisions.md](decisions.md) #31). Added **Cinder** as Phase 2 **Stage 6** (RBD-backed `volumes` pool; [decisions.md](decisions.md) #32); Phase 2 is now staged **0–6**. Updated the Phase 2 description and open-items list accordingly. |
| 2026-06-12 | Amended **decision #24**: Neutron mechanism driver **Linux bridge → Open vSwitch (OVS)** — RDO 2025.1 Epoxy ships no linuxbridge agent. The VXLAN self-service model (#14) is unchanged; updated the Parameters tenant-networking line accordingly. See [decisions.md](decisions.md) #24/R12 and [project-phase-2-stage-3.md](project-phase-2-stage-3.md). |
| 2026-06-12 | Marked Phase 2 **Stage 3 complete** — Neutron controller-side is up (server + L3/DHCP/metadata + OVS agent), filling the `nova.conf [neutron]` placeholder; Stage 4 (compute roles) is next. Added [decisions.md](decisions.md) #34 (the `os_neutron_dac_override` SELinux boolean) and #35 (`restorecond` for the recurring glance/`ceph.conf` relabel — root-caused to [Ceph #9530](https://tracker.ceph.com/issues/9530), now resolved). See [project-phase-2-stage-3.md](project-phase-2-stage-3.md). |
| 2026-06-12 | Marked Phase 2 **Stage 3 Nova controller-side complete** (Cells v2 bootstrapped; `nova-scheduler`/`-conductor` both `up`); **Neutron controller-side is the remaining Stage 3 work.** Resolving it surfaced a RabbitMQ/Erlang version fix — see [decisions.md](decisions.md) #33 and [project-phase-2.md](project-phase-2.md). |
| 2026-06-18 | Marked Phase 2 **Stage 4 complete** — the `nova_compute`/`neutron_compute` roles on compute1/2/3 (3 `nova-compute` up + cell-mapped, RBD-backed ephemeral; OVS agents up tunnel-only). Closed the **`kvm`/`qemu`** and **`ansible-vault`** open items ([decisions.md](decisions.md) #36/#37; #38 records the client.nova/ceph.conf delivery). Stage 5 (bootstrap + first VM) is next. See [project-phase-2-stage-4.md](project-phase-2-stage-4.md). |
| 2026-06-18 | Stage 5 started: recorded the last three planning open items (tenant CIDR, floating-IP pool, VXLAN MTU) as [decisions.md](decisions.md) #39 — **no planning open items remain**. |
| 2026-06-19 | **Phase 2 Stage 5 complete** — OpenStack objects bootstrapped and a CirrOS VM is reachable from the home LAN via a floating IP (decisions #39–#42). **Stage 6 (Cinder) is the last Phase 2 stage.** |
| 2026-06-27 | **Phase 2 Stage 6 (Cinder) complete → Phase 2 is done.** Controller-side `cinder-api`/`-scheduler`/`-volume` with an RBD `volumes` pool, **reusing the `client.nova` libvirt secret** (resolved the Stage-6-prose vs. decision #38 contradiction in favour of #38 — no compute-side change); a 1 GB volume was created, confirmed in the `volumes` pool, and attached to the Stage 5 VM. Marked Phase 2 **complete** and Phase 3 **next**. Also moved `rbd_secret_uuid` to `group_vars/all.yml` (cluster-wide identity). See [project-phase-2-stage-6.md](project-phase-2-stage-6.md). |
