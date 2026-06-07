# Project Principles

The guiding principles behind this cluster — the *why* that sits underneath the
concrete decisions in [decisions.md](decisions.md) and the parameters in
[project-plan.md](project-plan.md). When a choice is unclear, these are the tie-breakers.

## 1. Learning is the goal, not speed

The cluster exists to understand how OpenStack, Ceph, and Ansible actually work. Doing
things by hand even when it is slower is the point — the friction *is* the curriculum.
This is deliberately not the fastest path to a running cluster.

## 2. Each phase is motivated by the friction of the previous one

The build progresses manual → hand-rolled Ansible → Kolla-Ansible (Phases 1 → 2 → 3).
You only automate work you have already done by hand, so each phase is *recognition* of
the previous one rather than learning two new things at once.

## 3. Learn by finding and modifying, not by copy-pasting

Rather than pasting finished playbooks/configs, start from the standard skeleton or the
official template and modify it for this cluster — walking each file line by line,
deciding what is constant versus what varies per host. That pass *is* the learning,
because it forces understanding of every setting. Build understanding on low-stakes
exercises first (e.g. a throwaway `common` Ansible role before touching Nova).

## 4. Automate the repetition; do one-offs by hand

Ansible earns its place on the "same steps three times" across the compute nodes, so
that is what becomes roles. One-time work (the controller-side bring-up) stays manual —
forcing it into a role adds complexity without the payoff. Anything automated should be
**idempotent**: safe to re-run, a second run reporting `ok` not `changed`.

## 5. Temporary and disposable

The cluster is built to be benchmarked and torn down within a few days. Decisions favor
"interesting and representative for a benchmark" over long-term durability or
operational robustness. Effort spent hardening something that will be deleted is effort
not spent learning.

## 6. Keep the benchmark honest

Prefer homogeneous, standard configurations so results are clean and comparable: all
OSDs on matched 250GB SATA SSDs (no heterogeneous pool), defaults left in place unless
there is a real reason to change them, and *real* Ceph behavior (3 OSD hosts so default
3× replication with a `host` failure domain is genuine). Variables that affect
interpretation are recorded rather than hidden (e.g. hyperthreading left enabled).

## 7. Pragmatic "good enough" for an isolated lab

Where production-grade practice adds friction without learning value, take the simpler
option **deliberately**: firewalld disabled, a single Ceph MON (accepted SPOF), a flat
1G underlay shared by everything. The bar for improvising hardware (e.g. dangling
110V→SATA power for an extra drive) is high and generally not met for a test cluster.

## 8. Don't disturb the home network

The cluster shares a home LAN, and must not interfere with it. Hosts use static IPs and
run no DHCP server of their own; VM DHCP is sealed inside a VXLAN overlay so it cannot
race the household's DHCP server. Anything that reaches onto the home segment (the
floating-IP range) is chosen to sit outside the router's DHCP pool and the static host
IPs.

## 9. Decide deliberately, and record the why

Every non-obvious choice — including *accepting a risk* — is logged as a conscious
choice with its rationale, never left as an accident. The single-MON SPOF, the
Squid-vs-Reef version skew, and the VXLAN-over-VLAN call are all on the record in
[decisions.md](decisions.md) precisely so a later reader (or a later chat) does not
re-litigate or trip over them.

## 10. Verify; don't assume

Cross-check against the authoritative source (the official 2025.1 / RDO / Ceph docs)
rather than trusting generic instructions — the Apache symlink step turned out to be
Ubuntu-specific. Confirm that an action actually took effect and that its prerequisites
exist (a `role add --project service` silently no-ops when the `service` project was
never created — that caused the Glance 401, and `role assignment list` would have
revealed it). Read the log before changing things blindly.

## 11. Be consistent

One convention, applied everywhere. FQDNs throughout (Ceph *and* OpenStack), identical
`/etc/hosts` on every node, and a fixed hostname ↔ IP ↔ machine mapping. Consistency
removes a whole class of reconciliation bugs (mismatched short/FQDN names, drifting
configs).

## 12. Constraints become observables

The limitations are part of the lesson rather than problems to engineer away. The single
1G link will saturate during Ceph recovery and VXLAN adds encapsulation overhead on the
same wire — that is something to *watch and learn from*, not to fix.

## 13. Diagnose from observed state, not assumed state

While working through an issue, **never assume the state of any configuration** — mistakes
happen, and a wrong assumption sends the diagnosis down the wrong path. First give the user
commands that *read the actual state* of the pertinent configs and services, then diagnose
from what they show. (In this project: `ansible-config dump --only-changed` settled whether
`become` was really on; `cat -A`/`python3 -c 'yaml.safe_load(...)'` found the real inventory
parse fault; `ip -d link show type vxlan` confirms what is actually running.) This is the
debugging companion to principle 10.

A specific corollary on the user's pasted text: **if a command or its output looks like it
is missing characters at the beginning or end, assume first that it is a copy-paste/
transcription error and ask the user to re-check it before trying to fix anything.** A
truncated paste looks exactly like a real bug but isn't — chasing it wastes effort and can
"fix" something that was never broken. (The Phase 1 Glance 401 was first blamed on an
`admi` typo that turned out to be a copy-paste slip; the real cause was the missing
`service` project — exactly the failure mode this guards against.)

---

## Changelog

| Date | Change |
|---|---|
| 2026-06-06 | Initial principles document collated from chunks 01–06 (learning-first approach, phase-friction progression, find-and-modify learning, automate-the-repetition, disposable cluster, honest benchmarking, pragmatic lab trade-offs, home-network isolation, deliberate decision-logging, verify-don't-assume, consistency, constraints-as-observables). |
| 2026-06-06 | Corrected the principle #10 example: the Glance 401 was caused by the missing `service` project, not an `admi` typo. |
| 2026-06-07 | Added principle 13 (diagnose from observed state, not assumed state — including the copy-paste-error-first corollary for truncated commands/output). |
