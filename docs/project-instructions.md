# Project Instructions — How to Help on This Project

Working guidance for any assistant (or person) helping with this cluster. It is *not*
a substitute for the reference docs — it explains **how** to engage with them. For the
*why* behind the project, see [project-principles.md](project-principles.md); for the
*what*, see the documents listed below.

## What this project is

A temporary, hands-on **learning** build of a 4-node OpenStack + Ceph cluster on
retired Dell OptiPlex desktops. The goal is to understand how the services work, not to
ship production infrastructure. The cluster is stood up, benchmarked, and torn down
within a few days, and is built deliberately the slow way so each step is motivated by
the friction of the previous one (see [project-principles.md](project-principles.md)).

## Source-of-truth documents

These docs are authoritative; treat them as the source of truth and keep them current.

| Doc | Holds |
|---|---|
| [project-principles.md](project-principles.md) | The guiding principles (the *why*). |
| [project-plan.md](project-plan.md) | Goals, parameters, the Phase 0–3 structure, open items. |
| [decisions.md](decisions.md) | Every settled decision with rationale, plus rejected options. |
| [inventory.md](inventory.md) | Hardware, RAM, disk, and the host/IP/network map. |
| [project-phase-0.md](project-phase-0.md) … [project-phase-2.md](project-phase-2.md) | Per-phase planned steps and execution logs. |

When these and any older pasted "build plan" disagree, **these docs win** — they carry
the corrections (e.g. the real cause of the Phase 1 Glance 401 was the missing `service`
project, not a typo; the project is a four-phase 0–3 plan and **Phase 3 — the Kolla
rebuild — is still planned**, not dropped).

## Current status

- **Phase 0 (hardware prep + OS install)** — complete.
- **Phase 1 (Ceph + controller by hand)** — **complete and verified.** Ceph (cephadm,
  5 OSDs, `HEALTH_OK`) plus Keystone, Glance (Ceph RBD-backed), and Placement run on the
  controller.
- **Phase 2 (compute nodes via hand-rolled Ansible)** — **active.** Design is done
  (VXLAN self-service networking, the staged Ansible approach). **Stages 0–1 (Ansible
  control node + cluster inventory) are complete and verified; Stage 2 (the throwaway
  `common` role rendering `/etc/hosts`) is in progress.** Open items are tracked in
  [project-plan.md](project-plan.md) and [project-phase-2.md](project-phase-2.md).
- **Phase 3 (full teardown + rebuild with Kolla-Ansible)** — planned, later.

## How to help

- **It's a learning exercise — explain the *why*, not just the *what*.** Point out the
  gotchas and the reasoning behind each step. Prefer "find a template and modify it" over
  handing over copy-paste playbooks (principles 1–3).
- **Pace the work section by section.** The user drives the tempo — deliver
  implementation steps one section at a time, not as a single dump, unless asked.
- **Respect settled decisions.** Don't relitigate things already deliberately closed in
  [decisions.md](decisions.md) unless asked. But if a past decision looks genuinely
  wrong, **say so plainly** rather than silently working around it.
- **Stick to the established stack:** AlmaLinux 9, OpenStack 2025.1, Ceph Squid via
  `cephadm`, Linux bridge mechanism driver, VXLAN self-service tenant networking, and
  Ansible installed via `uv` (community 13 / `ansible-core` 2.20) — match Ansible docs
  to **version 13**.
- **Stay consistent with what's already built.** When writing config, follow the Phase 1
  patterns (the `[keystone_authtoken]` block, the service-account three-step pattern —
  *including ensuring the `service` project exists* — Glance multi-store keys, FQDNs
  everywhere) so Phase 2 matches the existing cluster.
- **Verify, don't assume** (principle 10): cross-check the official 2025.1/RDO/Ceph docs
  rather than generic instructions, and confirm actions took effect.

---

## Changelog

| Date | Change |
|---|---|
| 2026-06-06 | Created from the chunk-07 standardization attempt, adapted to this repo's doc set, the 0–3 phase structure (Phase 3 retained), and the corrected Phase 1 issue #5 root cause. |
| 2026-05-24 | Updated status (Phase 2 Stages 0–1 complete, Stage 2 next) and added Ansible (uv community 13 / core 2.20, docs v13) to the established stack. |
| 2026-06-04 | Updated status: Stage 2 (the `common` role) in progress. |
