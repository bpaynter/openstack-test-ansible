# Phase 2 · Stage 2 — Throwaway `common` Role (`/etc/hosts`)

> Part of **[Phase 2](project-phase-2.md)**. **Status: complete** (verified 2026-06-08).

## Planned steps

2. **Stage 2 — A throwaway `common` role to learn the mechanics** — `ansible-galaxy role
   init common`, then a low-stakes, genuinely useful task: render `/etc/hosts` identically
   on all four nodes via the `template` module (`templates/hosts.j2` → `/etc/hosts`). Run
   it twice; the second run must report `ok` not `changed`. This teaches the role skeleton
   (`tasks`/`templates`/`defaults`/`vars`/`handlers`/`meta`), the single most important
   module (`template`), and idempotence — before touching Nova.

## Actual work completed

A low-stakes role to learn role structure before Nova/Neutron: render an identical,
inventory-driven `/etc/hosts` to all four nodes.

- **Skeleton:** `ansible-galaxy role init --init-path roles common` → `roles/common/`
  with `tasks/`, `templates/`, `files/`, `handlers/`, `defaults/`, `vars/`, `meta/`,
  `tests/`. `tasks/main.yml` is the entry point; `templates/` holds Jinja2 (`.j2`) files
  the `template` module finds by relative path; `files/` is for static `copy` content;
  `defaults/` is lowest-precedence vars, `vars/` highest.
- **Template** `templates/hosts.j2`: the loopback lines plus
  `{% for host in groups['all'] | sort %}` emitting
  `{{ hostvars[host].local_ip }}  {{ host }}  {{ host.split('.')[0] }}` (FQDN canonical,
  short name as alias). Headed with `{{ ansible_managed }}`. Ansible's `template` module
  enables `trim_blocks`/`lstrip_blocks` by default, so the loop renders without
  blank-line artifacts. The `| sort` keeps the output byte-stable run-to-run, which is
  what makes the idempotence check pass.
- **Task** `tasks/main.yml`: `ansible.builtin.template` (FQCN best practice) with
  `src: hosts.j2`, `dest: /etc/hosts`, `owner/group: root`, `mode: '0644'` (quoted to
  avoid the octal YAML gotcha), `backup: true` (a timestamped backup the first time it
  overwrites a live `/etc/hosts`), and `become: true` (per-task escalation; `-K` collects
  the sudo password once).
- **`local_ip` vs `underlay_ip` decision (Option A):** reuse the existing per-host
  `local_ip` for `/etc/hosts` rendering rather than introduce a separate `underlay_ip`.
  On this single-NIC cluster the underlay IP and the VXLAN tunnel endpoint are always the
  same value, so a second variable isn't worth the redundancy. (Discovered that
  `local_ip` was already defined on all four hosts, including the controller — which is
  fine, since the controller is also a VTEP.) Recorded as decision #29.
- **`site.yml`:** a top-level play (`hosts: all`, `roles: [common]`), with **no
  play-level `become`** — escalation stays per-task (decision #28). This is also the
  project's first real playbook entry point.
- **Applied and verified (2026-06-08):** previewed with `--check --diff -K`, applied with
  `--diff -K`, then re-run to prove idempotence — the second run reported **all `ok`, no
  diff** (the Stage 2 acceptance test). The `--check` diff also showed the render
  correcting the live hand-written files, whose host columns were ordered
  `IP  short  FQDN`; the template's FQDN-canonical order (`IP  FQDN  short`) matches the
  form recorded in [project-phase-1.md](project-phase-1.md) and is the right canonical
  order for a cluster whose services speak FQDNs. Loopback lines were already
  localhost-only on every node (Phase 0 done correctly — no FQDN parked on `127.0.0.1`).
- **No handler in `common`:** rendering `/etc/hosts` has no service to bounce, so forcing
  a handler here would be busywork. The `notify` → validate-and-reload pattern was instead
  exercised for real in the throwaway cephadm-fix playbook (see Problems below).

## Problems hit and fixes

1. **`community.general.yaml` stdout callback removed.** The first `ansible-playbook`
   run failed: `ansible.cfg` set `stdout_callback = yaml`, but that callback lived in
   `community.general`, and **12.0.0 removed it** (the full `ansible` 13.7 package bundles
   community.general 12.x). Its job moved to an option on the built-in default callback.
   Fix: replace `stdout_callback = yaml` with `result_format = yaml` (supported by
   `ansible.builtin.default` since ansible-core 2.13). `callbacks_enabled = profile_tasks`
   is a separate plugin and was unaffected. A small instance of the documented
   version-skew caveat — config keys shift between versions, so match the v13 docs.
2. **compute3 (7050) dropped off mid-stage, then broke cephadm's SSH.** The box went
   unreachable (no ping, no Ansible SSH); since it carries 2 of the 5 OSDs *and* — as this
   episode revealed — a MON, Ceph went `HEALTH_WARN` with degraded/undersized PGs. After
   it returned, `ceph health detail` showed **cephadm SSH auth failures for `root`** ("3
   hosts fail cephadm check"). Root cause: root's `authorized_keys` had been pruned earlier
   on the assumption that Ansible's `become` model made root SSH unnecessary — true for
   Ansible, but **cephadm is a separate management plane that SSHes to every host as
   `root`** with its own cluster key. Fix: restored the cephadm public key
   (`ceph cephadm get-pub-key`) to root's `authorized_keys` on all four nodes via a
   throwaway Ansible playbook (`authorized_key` + an sshd `PermitRootLogin` drop-in,
   reloaded through a validate-then-reload handler), **hardened** with
   `PermitRootLogin prohibit-password` and a `from="192.168.1.128/29"` source restriction
   scoped to the cluster nodes (so the key is only usable from a node that could run the
   active mgr). Recorded as **decision #30**. The same `ceph -s` also revealed the cluster
   runs **4 MONs**, not the single MON **decision #15** had recorded — cephadm's default
   MON placement had spread them across the added hosts; #15 corrected accordingly.

**VXLAN/VTEP reference (clarified here, used in Stage 4):** a VTEP is the host IP that
sends/receives VXLAN-encapsulated UDP (port **4789**); each node's `local_ip` *is* its
VTEP address once Stage 4 templates the linuxbridge config. The `neutron_compute` (and
controller) ml2/linuxbridge config will set `enable_vxlan = true`, `local_ip`, and
typically `l2_population = true` (proactive forwarding from Neutron's DB rather than
multicast, which home underlays carry poorly), with controller-side
`type_drivers = flat,vxlan`, `tenant_network_types = vxlan`, and a `vni_ranges` pool
(e.g. `1:1000`). Today nothing reads `local_ip` — confirm the pre-Stage-4 state with
`ip -d link show type vxlan` and `ss -lun | grep 4789` (both empty).
