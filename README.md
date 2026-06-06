# OpenStack + Ceph Learning Cluster

A **temporary** 4-node OpenStack + Ceph cluster built from retired Dell OptiPlex
desktops. The goal is **learning**: stand the cluster up, run some benchmarks, and
tear it down again after a few days. A secondary goal is to learn **Ansible**, so
the build deliberately follows a 3-phase progression (manual → hand-rolled Ansible
→ Kolla-Ansible) where each phase is motivated by the friction of the previous one.

This repository contains the planning documents, decision records, and (eventually)
the configuration and Ansible code used to build the cluster.

## Documentation

| Document | Description |
|---|---|
| [docs/project-instructions.md](docs/project-instructions.md) | How to help on this project — working guidance, the doc map, and current status. |
| [docs/project-principles.md](docs/project-principles.md) | The guiding principles behind the project (the *why* under the decisions). |
| [docs/project-plan.md](docs/project-plan.md) | Project goals, rules/guidelines, and the major phases of the build plan. |
| [docs/inventory.md](docs/inventory.md) | Hardware inventory (machines, CPUs, RAM, disks) and a hardware changelog. |
| [docs/decisions.md](docs/decisions.md) | Decisions made during planning and execution, with the reasoning behind each. |
| [docs/project-phase-0.md](docs/project-phase-0.md) | Phase 0 — hardware prep and OS installation: planned steps and execution log. |
| [docs/project-phase-1.md](docs/project-phase-1.md) | Phase 1 — Ceph + the controller node by hand: planned steps, config notes, and execution log. |
| [docs/project-phase-2.md](docs/project-phase-2.md) | Phase 2 — compute nodes via hand-rolled Ansible: networking model, Ansible approach, and step plan. |

> This documentation is being reconstructed from a series of planning and
> implementation chats, one chunk at a time. The table of contents above will grow
> as more documents are added.
