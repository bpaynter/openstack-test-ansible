# Project Instructions — How to Help on This Project

Working guidance for any assistant (or person) helping with this cluster. It is *not*
a substitute for the reference docs — it explains **how** to engage with them. For the
*why* behind the project, see [project-principles.md](project-principles.md); for the
*what*, see the docs listed in the [README](../README.md#documentation).

## What this project is

A temporary, hands-on **learning** build of a 4-node OpenStack + Ceph cluster on retired
OptiPlex desktops — understand how the services work, benchmark, then tear it down. See
the [README](../README.md) for the overview and [project-principles.md](project-principles.md)
for the philosophy.

## Source-of-truth documents

The reference docs (listed in the [README](../README.md#documentation)) are
authoritative; treat them as the source of truth and keep them current. When they and
any older pasted "build plan" disagree, **these docs win** — they carry the corrections
(e.g. the real cause of the Phase 1 Glance 401 was the missing `service` project, not a
typo; the project is a four-phase 0–3 plan and **Phase 3 — the Kolla rebuild — is still
planned**, not dropped).

## Current status

Phase 0 and Phase 1 are complete; **Phase 2 is active** (Stages 0–4 done, Stage 5 next);
Phase 3 is planned for later. The authoritative phase/stage status lives in
[project-plan.md](project-plan.md#phases).

## How to help

- **It's a learning exercise — explain the *why*, not just the *what*.** Point out the
  gotchas and the reasoning behind each step. Prefer "find a template and modify it" over
  handing over copy-paste playbooks (principles 1–3).
- **Pace the work section by section.** The user drives the tempo — deliver
  implementation steps one section at a time, not as a single dump, unless asked.
- **The user authors the files; you navigate.** Give the user the content and the
  line-by-line reasoning, and let *them* create/edit and commit the repo's working files
  (roles, templates, vars, playbooks) — that hands-on pass is the point (principle 3).
  Don't write those files for the user unless explicitly asked to. The exception is the
  **docs**: keeping the repository current (below) is the assistant's job, so doc updates
  are authored and committed directly. After the user pushes a file, verify it (read it
  back) rather than assuming it's correct.
- **A fresh chat per phase/stage.** The user typically starts a new chat for each
  implementation stage rather than carrying long context forward, so leave each stage's
  state captured in the repo (see "Keep the repository current" below) for the next one.
- **Respect settled decisions.** Don't relitigate things already deliberately closed in
  [decisions.md](decisions.md) unless asked. But if a past decision looks genuinely
  wrong, **say so plainly** rather than silently working around it.
- **Stick to the established stack:** AlmaLinux 9, OpenStack 2025.1, Ceph Squid via
  `cephadm`, Open vSwitch (OVS) mechanism driver, VXLAN self-service tenant networking, and
  Ansible installed via `uv` (community 13 / `ansible-core` 2.20) — match Ansible docs
  to **version 13**.
- **Stay consistent with what's already built.** When writing config, follow the Phase 1
  patterns (the `[keystone_authtoken]` block, the service-account three-step pattern —
  *including ensuring the `service` project exists* — Glance multi-store keys, FQDNs
  everywhere) so Phase 2 matches the existing cluster.
- **Verify, don't assume** (principle 10): cross-check the official 2025.1/RDO/Ceph docs
  rather than generic instructions, and confirm actions took effect.

## Conventions

Concrete command/tooling conventions for this cluster (the "How to help" guidance above is
about *engagement*; these are about *how commands are written*):

- **Database access:** use `sudo mysql`, **not** `mysql -u root -p`. On these AlmaLinux
  MariaDB nodes root authenticates through the unix-socket plugin, so `sudo mysql` drops
  straight into a root SQL session — no password prompt, and no DB password left in shell
  history.

## Keep the repository current

The docs are the project's living memory — keep them reflecting the **current state of
the project** as work proceeds, in the same session, not as an afterthought. Whenever you
produce something that changes the project's state, update the owning file as well as
telling the user:

- **New plan / steps:** when you generate new steps for a phase or stage, give them to the
  user **and** add them to the appropriate file (usually the relevant
  `docs/project-phase-N.md`) so the plan in the repo stays complete.
- **Decisions:** when a decision is made (or an option rejected), record it in
  [decisions.md](decisions.md) with its reasoning.
- **Problems & fixes:** when something is troubleshooted, record the problem and its fix in
  that phase's execution log ("Actual work completed" / "Problems hit").
- **Status & facts:** update phase/stage status, the hardware/address map, open items, and
  any changed fact in its owning file, and note material changes in that file's changelog.

Follow the repo's own conventions: each fact lives in **one** file and the others link to
it (prefer a direct section link). When you change a doc, say briefly what you updated so
the user can review it.

---

## Changelog

| Date | Change |
|---|---|
| 2026-06-06 | Created from the chunk-07 standardization attempt, adapted to this repo's doc set, the 0–3 phase structure (Phase 3 retained), and the corrected Phase 1 issue #5 root cause. |
| 2026-05-24 | Updated status (Phase 2 Stages 0–1 complete, Stage 2 next) and added Ansible (uv community 13 / core 2.20, docs v13) to the established stack. |
| 2026-06-04 | Updated status: Stage 2 (the `common` role) in progress. |
| 2026-06-07 | Consistency/dedup pass: replaced the doc-map table with a pointer to the README TOC; condensed Current status to a pointer to [project-plan.md](project-plan.md#phases). |
| 2026-06-07 | Added a "Keep the repository current" section: assistants must record new steps, decisions, and troubleshooting into the owning docs as work proceeds. |
| 2026-06-07 | Added the "fresh chat per phase/stage" working practice (rescued from the now-deleted `overall_plan.md`). |
| 2026-06-08 | Updated status: Phase 2 Stages 0–2 complete (the `common` role is done and idempotent), Stage 3 next. |
| 2026-06-09 | Added a **Conventions** section; first entry: DB access uses `sudo mysql` (MariaDB unix-socket root), not `mysql -u root -p`. |
| 2026-06-12 | Updated the established stack: Neutron mechanism driver **Linux bridge → Open vSwitch (OVS)** (RDO 2025.1 ships no linuxbridge agent; decision #24 amended). |
| 2026-06-18 | Updated status: **Phase 2 Stages 0–4 done** (the `nova_compute`/`neutron_compute` roles are complete and idempotent); **Stage 5 next**. |
| 2026-06-18 | Added a **"How to help"** bullet: the **user authors the working files** (roles/templates/vars/playbooks) with the assistant navigating; the assistant commits **docs** directly and verifies user-pushed files. |
