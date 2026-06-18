# Bootstrap Prompt

The standing prompt to paste at the **start of a fresh chat** on this project (the working
practice here is a new chat per phase/stage — see
[project-instructions.md](project-instructions.md)). It is a **portable summary, not a
source of truth**: the authoritative version of everything it references lives in the docs
linked from the [README](../README.md#documentation), and **those win** on any conflict.
It deliberately carries **no project-progress state** (which phase/stage is active, what's
complete) — that lives in [project-plan.md](project-plan.md) and the per-stage logs and
changes far more often than these policies. Update this prompt only when the project's phase
**scope** or **working conventions** change, and note it in the changelog below.

---

```
This project is a temporary, hands-on LEARNING build of a 4-node OpenStack + Ceph
cluster on retired Dell OptiPlex desktops. The goal is to understand how the pieces
work (and to learn Ansible), run some benchmarks, then tear it down within a few days —
not to ship production infrastructure. The build runs in four phases: 0 = hardware/OS
prep, 1 = Ceph + the controller by hand, 2 = compute nodes via hand-rolled Ansible
(Nova + Neutron, then Cinder block storage; VMs and volumes both Ceph RBD-backed),
3 = a full Kolla-Ansible rebuild. This prompt deliberately carries NO progress state —
for which phase/stage is current and what is already built, read docs/project-plan.md
and the per-phase/stage execution logs.

All planning, decisions, and per-phase logs live in this GitHub repo — treat it as the
source of truth:
  https://github.com/bpaynter/openstack-test-ansible

At the start of a task, read the files relevant to it:
- README.md                    — overview + the documentation map
- docs/project-instructions.md — how to help (working style, conventions, current status)
- docs/project-principles.md   — the guiding principles (the "why")
- docs/project-plan.md         — goals, key parameters, the 0–3 phase structure, and status
- docs/decisions.md            — every settled decision + rationale (and rejected options)
- docs/inventory.md            — hardware, RAM, disks, and the host/IP/network map
- docs/project-phase-0.md, -1.md, and docs/project-phase-2*.md (overview + per-stage files)
  — per-phase/stage planned steps and execution logs

Working style (full version in docs/project-instructions.md): it's a learning exercise —
explain the WHY, not just the what; prefer walking me through finding and modifying a
template over handing me finished playbooks; pace the work section by section (I set the
tempo); respect settled decisions but say so plainly if one looks wrong; and never assume
config state while debugging — give me commands to check the actual state first, and if a
pasted command or its output looks like it's missing characters at either end, suspect a
copy-paste error and ask me to re-check before trying to fix anything.

KEEP THE REPO CURRENT: the docs are the project's living memory. As we work, update the
owning file, not just chat — when you generate new plan steps, give them to me AND add
them to the appropriate docs/project-phase-N.md; when a decision is made, record it in
docs/decisions.md with its reasoning; when a problem is troubleshooted, record the problem
and fix in that phase's execution log; and update status, the hardware/address map, open
items, and changelogs as facts change. One fact lives in one file; the others link to it.
Tell me briefly what you changed.
```

---

## Changelog

| Date | Change |
|---|---|
| 2026-06-09 | Created from the chat-opening bootstrap prompt. Phase 2 scope reflects **Cinder block storage (Stage 6)** and the **Ceph-RBD-backed VM/volume** storage model (decisions [#31/#32](decisions.md)). |
| 2026-06-18 | **Removed all project-progress state from the prompt body** (the per-phase `(complete)`/`(in progress)`/`(planned)` markers) so the standing prompt carries only stable scope + policy; it now states it has no progress state and points to [project-plan.md](project-plan.md) for current status. Generalized the Phase-2 doc reference to `project-phase-2*.md` (overview + per-stage files). |
