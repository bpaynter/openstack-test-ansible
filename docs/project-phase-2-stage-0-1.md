# Phase 2 · Stages 0–1 — Ansible Control Node + Cluster Inventory

> Part of **[Phase 2](project-phase-2.md)**. **Status: complete** (verified 2026-05-24).
> Stages 0 and 1 were executed and logged as a single unit, so they share one file.

## Planned steps

0. **Stage 0 — Ansible control setup** — Ansible (via `uv`) on the controller, SSH +
   escalation model settled, project `ansible.cfg` + git repo.
1. **Stage 1 — Inventory + prove connectivity** — YAML inventory (groups + per-host
   `local_ip`), verified with `ansible-inventory --graph` and `ansible all -m ping`.
   ("A playbook is just ad-hoc commands made repeatable.")

## Actual work completed

**Stage 0 — Ansible control node:**

- **Control node:** the controller (7071), inside `lab.internal` so `/etc/hosts` already
  resolves every managed node.
- **Ansible install:** via **`uv`**, not the AlmaLinux `dnf` package (its `ansible-core`
  2.14/2.15 line is end-of-life and too old to match the live docs). Final:
  `uv python install 3.12` then `uv tool install ansible --python 3.12` →
  community **13.7** / `ansible-core` **2.20** on **Python 3.12**. Match all Ansible doc
  references to **version 13**.
- **Escalation model:** Ansible runs as the normal login user — never as root, never
  `sudo ansible-playbook`. `sudo` is left **password-protected** (a deliberate security
  choice, not passwordless); escalation is per-play/per-task `become` with `-K` /
  `--ask-become-pass` at run time. `become` is default-**off** in `ansible.cfg`.
- **`ansible.cfg`** (project-local): `inventory` path, `result_format = yaml`,
  `callbacks_enabled = profile_tasks`, `interpreter_python = auto_silent`. (`become` not
  set; `become_ask_pass` was tried then removed — see problem 5. `remote_user` is not
  set: the same account is used locally and remotely, so Ansible's default of connecting
  as the current user is correct. `result_format = yaml` replaced an earlier
  `stdout_callback = yaml` — see the [Stage 2 problem log](project-phase-2-stage-2.md).)
- **Project directory:** the Ansible project lives in the repo's **`ansible/`** directory
  (`~/git/openstack-test-ansible/ansible/` on the controller), laid out as `ansible.cfg`,
  `inventory.yml`, `group_vars/`, `host_vars/`, `roles/`, `site.yml`. The repo has been
  version-controlled from the start; the Ansible file paths in this doc are relative to
  `ansible/`.

**Stage 1 — Cluster inventory:**

- A single YAML `inventory.yml`. YAML inventories require the top-level `all` group with
  groups nested under `all: → children:` (unlike INI, which infers it).
- Groups: `controller` (one host, `controller.lab.internal`) and `compute`
  (`compute1/2/3.lab.internal`). Group names are singular and must match `group_vars/`
  filenames exactly.
- Host range syntax is **colon**-delimited: `compute[1:3].lab.internal` (not `[1-3]`,
  which is treated as a literal hostname).
- Variable placement: `host_vars/` for per-host values (so far just `local_ip` — each
  node's own underlay IP / VXLAN tunnel-endpoint address, a value a range cannot
  express); `group_vars/all.yml` for non-secret cluster facts (controller hostname,
  Keystone auth URL, OpenStack release, RabbitMQ/memcached hosts). Service passwords are
  deferred to an `ansible-vault` file in Stage 4 — not placed in plaintext `group_vars`.
  Note: `local_ip` is defined on **all four** hosts (controller `.130` plus computes
  `.131`/`.132`/`.133`), not the three computes only — the controller is also a VTEP (it
  runs the L3/DHCP agents, which sit on tenant networks). See the decision in the
  [Stage 2 log](project-phase-2-stage-2.md).

## Problems hit and fixes

1. **`uv` kept installing `ansible` 8.7.0.** Not a bug — its resolver walked back to the
   newest release whose `ansible-core` the interpreter could satisfy; AlmaLinux's system
   Python 3.9 was the hidden cap. Fix: pin Python 3.12 (`uv tool install ansible
   --python 3.12`); `'ansible>=11'` turns the silent fallback into a loud resolver error.
2. **`uv tool install ansible` only exposed `ansible-community`.** `uv tool` links the
   requested package's own entry points; the real `ansible`/`ansible-playbook` commands
   belong to the `ansible-core` dependency and had to be exposed explicitly.
3. **Two Ansibles on the box** (the `uv` one + the leftover distro `ansible-core`) —
   `ansible` could resolve to either by `PATH` order; `which -a ansible` is the diagnostic.
4. **`ansible-inventory` rejected the YAML inventory — two causes:** (a) after moving the
   project into the git-repo folder, `ansible.cfg`'s `inventory` path no longer resolved
   (re-check with `ansible --version` / `ansible-config dump` after any move); (b) the
   host range was written with a hyphen `[1-3]` instead of the colon `[1:3]`.
5. **A bare `ansible … -m command -a hostname` prompted for a BECOME password.** Not a
   misconfiguration — `become` was correctly off, but `become_ask_pass = True` makes
   Ansible pre-collect a become password at the start of *every* run. Fix/decision:
   removed `become_ask_pass` from `ansible.cfg` and pass `-K` per invocation, so the
   prompt appears only for runs that actually escalate.

**Verification (all passing at handoff):** `ansible --version` (core 2.20 / community 13.7
/ Python 3.12), `which -a ansible` (resolves into the `uv` tool dir),
`ansible-config dump --only-changed` (confirms cfg; `become` not set),
`ansible-inventory --graph` (`all` → `controller` 1 host, `compute` 3 hosts),
`ansible-inventory --host compute2.lab.internal` (`local_ip = 192.168.1.132`),
`ansible all -m ping` (pong from all four).
