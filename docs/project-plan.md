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
- **Learning is prioritized over speed.** The cluster is intentionally built three
  times (see phases below); this is not the fastest path to a running cluster, and
  that is the point.

## Phases

The cluster is built **three times**, each phase motivated by the friction of the
previous one.

### Phase 1 — Manual, controller only

Build the storage and control plane by hand to learn what the services *are*.

- Stand up Ceph manually (`cephadm` bootstrap, or fully manual MON/MGR/OSD).
- On the 7071, manually install and wire up a minimal OpenStack control plane:
  **Keystone, Glance, Placement** — following the OpenStack install guide step by
  step.
- Outcome: understand Keystone tokens, the Glance→Ceph RBD integration, and why
  Placement exists.

### Transition — adding compute nodes with hand-rolled Ansible

Adding Nova-compute + Neutron agents to the 7060, 5090, and 5080 is the *same steps
three times* — the natural seam to introduce Ansible.

- Write playbooks to add the three compute nodes.
- The manual steps are already known, so this is "translate known work into
  playbooks" — learning Ansible without simultaneously learning OpenStack.

### Phase 2 — Full rebuild with Kolla-Ansible

Tear down and redeploy the whole cluster with Kolla-Ansible.

- Ansible is now concrete, not abstract.
- Reading Kolla's playbooks, every service is recognizable from the manual phase.
- Teardown is clean (containers), which suits the temporary nature of the cluster.

## Open Items

These were deliberately left to be settled early in implementation:

- **OS choice** for the nodes (e.g., Ubuntu LTS vs. a RHEL-family distro).
- **OpenStack release** version to target.
- **IP addressing / hostname scheme** (flat network is fine for this).
- **Phase 1 Ceph method** — bootstrapped via `cephadm` or fully by hand.

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-22 | Initial project plan created: goals, 4-machine layout, 1G-only networking, and the 3-phase (manual → hand-rolled Ansible → Kolla-Ansible) progression. |
| 2026-05-22 | Considered and rejected dropping to a 3-machine layout; kept all 4 machines (see [decisions.md](decisions.md)). |
| 2026-05-22 | Confirmed the 3-phase progression over a Kolla-only build, despite the temporary nature of the cluster, because learning Ansible is an explicit goal. |
