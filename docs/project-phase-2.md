# Phase 2 — Compute Nodes via Hand-Rolled Ansible

Add the **compute plane** to the cluster Phase 1 left running: **Nova**
(controller-side API/scheduler/conductor/novncproxy plus a compute agent on every
node) and **Neutron** (controller-side server plus the network-node and per-compute
agents). The work is the *same steps three times* across compute1/2/3 — exactly the
repetition that hand-rolled Ansible exists to absorb. There is **no teardown**: the
controller keeps its Phase 1 services and Phase 2 adds to it.

> **Status:** **In progress.** Design is complete (scope, VXLAN networking model,
> staged Ansible approach). **Stages 0–2 (Ansible control node, cluster inventory, and
> the throwaway `common` role) are executed and verified** — see "Actual work completed"
> below. Stages 3–6 (the controller-side bring-up, the compute roles, and Cinder block
> storage) are still ahead; the detailed VXLAN Neutron config is produced in a later
> implementation chat.

> **Phase-numbering note:** while scoping this phase, the source build-plan was briefly
> rewritten to call the project a "2-phase plan" with "Kolla-Ansible dropped." That was
> a momentary confusion. Per the project convention, **Phase 3 (a full teardown and
> rebuild with Kolla-Ansible) remains planned**; Phase 2 here is only the hand-rolled
> Ansible compute build. The overall plan and its phases are unchanged — see
> [project-plan.md](project-plan.md).

## Networking model — VXLAN self-service

The first draft of this phase used **flat provider networking** (VMs directly on
`192.168.1.0/24`). It was rejected because it puts VM DHCP on the same L2 broadcast
domain as the **home network's DHCP server**, producing a **dual-DHCP race**: both
servers hear every `DHCPDISCOVER`, both can answer, and a VM (or a real LAN client)
can get a lease from the wrong server. Disjoint allocation pools prevent duplicate
IPs but not the cross-answering.

Phase 2 therefore uses **VXLAN self-service networking** with the **Linux bridge**
mechanism driver:

- VMs live on **tenant networks**, each its own isolated L2 domain, tunneled
  VM-to-VM and VM-to-network-node inside VXLAN-encapsulated UDP that rides over the
  physical `192.168.1.0/24` underlay.
- A VM's DHCP broadcast stays **inside** the overlay — the home router never sees it,
  and Neutron's DHCP agent is the only DHCP server the VM can reach. The dual-DHCP
  race is removed *by construction*, with **no managed switch required** (unlike a
  VLAN-based fix, which was rejected for needing hardware not in play).
- VMs get private tenant IPs (e.g. `10.0.0.0/24`). External reachability is via a
  **Neutron router** doing NAT to a **flat provider/external network** on
  `192.168.1.0/24`, plus **floating IPs** 1:1-NATed onto individual VMs.
- The controller (7071) is also the **network node**: it runs the L3, DHCP, and
  metadata agents.

Consequences carried into the steps below:

- `service_plugins = router` is required (the flat-only draft had it empty).
- ml2: `type_drivers` gains `vxlan`, `tenant_network_types = vxlan`, a `vni_ranges`;
  the linuxbridge agent sets `enable_vxlan = true` and a **per-host `local_ip`** (each
  node's own `192.168.1.x` tunnel endpoint) — another per-node inventory variable.
- The floating-IP pool is carved from `192.168.1.0/24` and must sit **outside** the
  home router's DHCP range and outside the static host IPs (`.130–.133`).
- **MTU:** VXLAN adds ~50 bytes of header — raise the underlay MTU or set the tenant
  network MTU to 1450, or hit the classic "SSH connects then hangs" fragmentation
  symptom.

## Learning approach

Phase 2 follows the project's learning-first principles — *find a template and modify it
for this cluster* rather than copy-pasting playbooks, and build understanding on
low-stakes exercises before real services. See
[project-principles.md](project-principles.md) (principles 1–4). The staged plan below
applies them: generate the standard skeletons (`ansible-galaxy role init`,
`ansible-config init --disabled`) and walk each file line by line, deciding what is
constant versus what varies per host.

> Implementation caveat: 2025.1 service config keys can shift between minor versions, and
> linuxbridge-vs-OVS guidance changes release to release — cross-check the official
> RDO/AlmaLinux 2025.1 install guide (the same discipline that caught the Ubuntu-specific
> Apache symlink in Phase 1).

## Ansible approach

Run Ansible from the **controller** as the control node (it already has SSH reach and
`admin-openrc`, and sits inside `lab.internal` so name resolution already works).
Ansible installs nothing on managed nodes — it pushes Python over SSH and runs modules.
The Ansible project lives in the repo's **`ansible/`** directory; the file paths in this
section and the steps below are relative to it.

- Install Ansible via **`uv`** (`uv tool install ansible --python 3.12`) — the full
  community package (community **13.7** / `ansible-core` **2.20**), which bundles
  `openstack.cloud` for the Stage 5 bootstrap. *Not* the AlmaLinux `dnf` package (its
  `ansible-core` is end-of-life and too old to match the live docs). The Nova/Neutron
  install work still uses only built-in modules (`dnf`, `template`, `service`,
  `command`); `openstack.cloud` is only needed at Stage 5. See [decisions.md](decisions.md).
- Set up passwordless SSH from the controller to itself and compute1/2/3, but keep
  `sudo` **password-protected** (a deliberate security choice — *not* passwordless);
  escalate with `-K` / `--ask-become-pass` at run time (see the escalation model in
  [decisions.md](decisions.md)).
- **`ansible.cfg`** (project-local, in `ansible/`) keeps a short, deliberate set of
  settings: the `inventory` path, `result_format = yaml` and
  `callbacks_enabled = profile_tasks` (legible, educational output),
  `interpreter_python = auto_silent`. `become` is left **default-off** so escalation is
  per-play/per-task and a missing `become:` fails loudly rather than silently running as
  root.
- **Inventory** (YAML preferred): a `controller` group (one host) and a `compute` group
  (compute1/2/3) by FQDN. Per-host variables live with the host — critically the
  **`local_ip`** (each compute node's own `192.168.1.x` VXLAN tunnel endpoint); group
  vars (controller IP, RabbitMQ/DB passwords, OpenStack release) live in
  `group_vars/`. Prove it before writing anything: `ansible all -m ping` (an SSH/Python
  check, not ICMP) → all four `pong`; then an ad-hoc `command` against the `compute`
  group.
- Encrypt secrets with **`ansible-vault`** (e.g. `group_vars/all/vault.yml`, run with
  `--ask-vault-pass`).
- **Roles are only for the repeated work.** The repetitive compute-node setup becomes
  roles; the one-time controller-side setup is done **manually** (see Stage 3). Make
  roles **idempotent**: `template:` for config files (not `lineinfile`), **handlers**
  for restarts (so a service bounces only when its config actually changed), and
  `command:` with `creates=`/`run_once:` guards for one-shot operations. A second run
  reporting `ok` (not `changed`) is the idempotence check.

## Planned steps (staged for learning)

0. **Stage 0 — Ansible control setup** ✅ *complete* — Ansible (via `uv`) on the
   controller, SSH + escalation model settled, project `ansible.cfg` + git repo.
1. **Stage 1 — Inventory + prove connectivity** ✅ *complete* — YAML inventory (groups +
   per-host `local_ip`), verified with `ansible-inventory --graph` and `ansible all -m
   ping`. ("A playbook is just ad-hoc commands made repeatable.")
2. **Stage 2 — A throwaway `common` role to learn the mechanics** ✅ *complete* —
   `ansible-galaxy role init common`, then a low-stakes, genuinely useful task: render
   `/etc/hosts` identically on all four nodes via the `template` module
   (`templates/hosts.j2` → `/etc/hosts`). Run it twice; the second run must report `ok`
   not `changed`. This teaches the role skeleton
   (`tasks`/`templates`/`defaults`/`vars`/`handlers`/`meta`), the single most important
   module (`template`), and idempotence — before touching Nova.
3. **Stage 3 — Controller-side Nova & Neutron (MANUAL, one-time)** — *not* a role, because
   the Ansible seam is repetition and this isn't repeated. Done by hand following the
   2025.1 guide, reusing the Phase 1 service-account pattern (ensure the `service`
   project exists → user create → role add `--project service` → `[keystone_authtoken]`;
   **verify each grant** with `role assignment list` — the Phase 1 issue #5 lesson).
   - **Nova:** `nova`/`nova_api`/`nova_cell0` DBs + `nova` service user; install
     nova-api/conductor/scheduler/novncproxy; configure `nova.conf`; the `nova-manage
     cell_v2` cell setup is the one unfamiliar part vs. Phase 1 — read the guide's cell
     section. (novncproxy gives VM console access later.)
   - **Neutron:** `neutron` DB + service user; install neutron server +
     linuxbridge/l3/dhcp/metadata agents; configure `neutron.conf`
     (`service_plugins = router`), `ml2_conf.ini` (`type_drivers` incl. `flat`+`vxlan`,
     `tenant_network_types = vxlan`, `mechanism_drivers = linuxbridge`, `vni_ranges`),
     `linuxbridge_agent.ini` (`enable_vxlan = true`, `local_ip = 192.168.1.130` on the
     controller, `l2_population = true`), and the l3/dhcp/metadata agent configs. **Keep these hand-written
     `.conf` files** — the compute-side configs are nearly identical, which sets up
     Stage 4.
4. **Stage 4 — `nova_compute` and `neutron_compute` roles (the loop on compute1/2/3)** —
   the payoff. Convert a Stage-3 `.conf` into `templates/nova.conf.j2`, then go line by
   line replacing host/environment-specific values with Jinja2 vars (`local_ip =
   192.168.1.130` → `local_ip = {{ local_ip }}`; controller hostname, RabbitMQ string,
   passwords → `group_vars` refs; genuinely-identical lines stay literal). `tasks/main.yml`
   is then short: `dnf` install → `template` render → `service` start, with restarts via
   handlers. Per-node specifics: `[vnc] server_proxyclient_address` = that node's own IP;
   `[libvirt] virt_type = kvm` (VT-x i7s — fail loudly if `vmx` absent) and
   **`[libvirt] images_type = rbd`** backed by the `vms` pool with a per-node libvirt
   secret holding the `client.nova` key (decision #31 — RBD-backed ephemeral; reuses the
   Phase 1 `/etc/ceph` permissions lesson); **NIC names may
   differ per node** so keep `physical_interface_mappings`/`local_ip` per-host. After the
   role runs, `nova-manage cell_v2 discover_hosts` **once** on the controller (a
   `command` task with `run_once: true` — teaches that not every task runs on every host);
   verify `openstack compute service list` / `network agent list`.
5. **Stage 5 — Bootstrap the OpenStack objects + test** — API-driven Ansible using the
   `openstack.cloud` collection (`network`/`subnet`/`router` modules), a different style
   from the file-driven Stages 2–4. Create, in dependency order: the flat
   provider/external network on `192.168.1.0/24` with its floating-IP pool (outside the
   home DHCP range and `.130–.133`); the VXLAN tenant network + `10.0.0.0/24` subnet
   (**set tenant MTU 1450**); a Neutron router (provider net as external gateway, tenant
   subnet as internal interface). Then a small flavor, a keypair, an SSH/ICMP security
   group, and `openstack server create` for a CirrOS instance; assign a floating IP and
   SSH in from the home LAN. When that works, the core compute plane is up — Stage 6
   adds persistent block storage.
6. **Stage 6 — Cinder (block storage), RBD-backed** — add persistent volumes once a VM
   boots. Controller-side and largely a repeat of the Phase 1 Glance pattern, so done
   **by hand** (not a role): create the `volumes` Ceph pool + `client.cinder` auth/keyring;
   the `cinder` DB; the service account (ensure the `service` project exists → user create
   → `role add --project service` → **verify with `role assignment list`** — the Phase 1
   issue #5 lesson); install `cinder-api`/`cinder-scheduler`/`cinder-volume` on the
   controller; configure `cinder.conf` with an `[rbd]` backend (`rbd_pool = volumes`,
   `rbd_user = cinder`, `rbd_ceph_conf`, and `rbd_secret_uuid` = the libvirt secret) and
   register the **block-storage v3** endpoints. The compute side needs only the libvirt
   Ceph secret already placed in Stage 4 (decision #31). Test: `openstack volume create`,
   confirm the UUID in `rbd -p volumes ls`, then `openstack server add volume` to attach
   it to the Stage 5 instance and verify the block device appears inside the guest. When
   that works, **Phase 2 is done.** (Cinder is optional on a throwaway cluster — included
   here for block-storage learning and volume-I/O benchmarking; see [decisions.md](decisions.md) #32.)

> **Nova ephemeral disk backend — decided: Ceph RBD-backed** (decision #31): a `vms`
> pool, `client.nova` auth, a per-compute libvirt secret, `[libvirt] images_type = rbd`.
> Chosen over local qcow2 because it enables live migration, makes Ceph recovery visibly
> affect running VMs (a benchmark observable), reuses the Phase 1 keyring-permissions
> lesson, and shares the libvirt Ceph secret that Stage 6 Cinder also needs. Configured
> in Stage 4's libvirt step.

## Open items for Phase 2 implementation

- **Tenant subnet CIDR** (e.g. `10.0.0.0/24`).
- **Floating-IP allocation pool** carved from `192.168.1.0/24`, confirmed against the
  home router's actual DHCP range and the static host IPs.
- **MTU handling** for VXLAN (raise underlay MTU vs. tenant network MTU 1450).
- **`kvm` vs `qemu`** — `kvm` expected (VT-x i7s), but BIOS virtualization must be
  confirmed enabled on each node.
- **`ansible-vault` secret handling** — deferred to Stage 4 (the Ansible project layout
  and inventory were settled in Stages 0–1).

## Problems anticipated (Phase 1 lessons carried forward)

- **Missing `service` project / unverified role grants (Phase 1 issue #5)** — a
  `role add --project service` silently no-ops if the `service` project doesn't exist,
  which surfaces only as a later 401. Ensure the `service` project exists, and add an
  explicit `role assignment list` verification after each grant.
- **Ceph file permissions (issue #3)** — Nova is now RBD-backed (#31) and Cinder (Stage 6)
  is too, so the `nova`/`qemu`/`cinder` users must read `/etc/ceph/` files:
  `chown root:<group>` + `chmod 640` + `restorecon`.
- **Per-node device/NIC names (issue #2)** — NIC names differ across these OptiPlex
  models just as disk letters did; **never hardcode the interface** in
  `physical_interface_mappings` or `local_ip` — make them per-host inventory variables.
  This is the single most likely thing to bite Phase 2.
- **SELinux** — keep it `enforcing`; check `ausearch -m avc` before reaching for
  permissive.
- **FQDN consistency** — keep using FQDNs everywhere in the inventory.

## Actual work completed

### Stages 0–1 — Ansible control node + inventory (complete, verified 2026-05-24)

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
  `stdout_callback = yaml` — see the Stage 2 problem log.)
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
  `.131`/`.132`/`.133`), not the three computes only — the controller is also a VTEP
  (it runs the L3/DHCP agents, which sit on tenant networks). See decision in the Stage 2
  log below.

**Problems hit and fixes:**

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

### Stage 2 — throwaway `common` role for `/etc/hosts` (complete, verified 2026-06-08)

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

**Problems hit and fixes (Stage 2):**

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

### Stage 3 — controller-side Nova & Neutron (in progress)

Controller-side prerequisites are underway (Nova `nova`/`nova_api`/`nova_cell0` DBs and
the `nova` service account; Keystone catalog/`auth_url` FQDN cleanup). Full Stage 3
detail will be recorded as the section lands; logged so far is one troubleshooting
episode.

**Problems hit and fixes (Stage 3):**

1. **glance-api failed to start — real cause was a mislabeled `/etc/ceph/ceph.conf`, not
   the config edit that preceded it.** While standardizing the Keystone catalog and the
   `glance-api.conf` `[keystone_authtoken]` `auth_url`/`www_authenticate_uri` onto the
   FQDN (`controller` → `controller.lab.internal`), the next `openstack-glance-api`
   restart died with `ERROR: [errno 2] RADOS object not found (error calling
   conf_read_file)`. The message looks auth-related but is the **RBD store** failing to
   read its Ceph config — and the edit was a red herring: the `auth_url` change was
   correct, and the `[ceph]` store section (`rbd_store_ceph_conf = /etc/ceph/ceph.conf`)
   was intact. The restart was simply the first glance-api start since
   `/etc/ceph/ceph.conf` was last rewritten (Jun 6), and that file carried the wrong
   SELinux label — `unconfined_u:object_r:user_tmp_t:s0` (the type a file picks up when
   created in a user/temp context and moved into place). glance-api runs **confined** as
   `glance_api_t`, which is not allowed to read `user_tmp_t`; a `sudo -u glance cat` test
   "passed" only because it ran **unconfined**, making it a false negative. The original
   read denial never appeared in `ausearch` (almost certainly `dontaudit`-suppressed),
   which is why the first check looked empty even though the label was the cause.
   **Fix:** `sudo restorecon -Rv /etc/ceph/` relabeled `ceph.conf` to its policy-correct
   type; glance-api then started and `openstack image list` worked. Same class as
   **Phase 1 issue #3** (Ceph access for service users) — but SELinux *labels*, not just
   owner/mode. **Lesson:** when a Ceph-backed service fails on `conf_read_file`, check
   `ls -lZ /etc/ceph` first, and test readability from the *confined service domain*, not
   an unconfined `sudo -u` shell.
   - **Benign residual denial (left as-is):** after the fix, `ausearch` shows one
     `glance_api_t` → `mysqld_exec_t` `getattr` denial on `/usr/bin/mariadbd-safe-helper`
     during DB init. glance is fully functional (image list works ⇒ DB access is fine), so
     this stat is off the needed path — likely the MariaDB client library probing for
     local-server artifacts. Left unaddressed on this throwaway cluster (no `permissive`,
     no blind `audit2allow`).

_Stages 4–6 to be filled in as later chunks execute them._

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-23 | Phase 2 designed: scope (Nova + Neutron via hand-rolled Ansible, no teardown), **VXLAN self-service networking** chosen over flat-provider (dual-DHCP race) and VLAN (needs a managed switch), controller promoted to network node, Ansible role/layout outline, and the step plan. Open items recorded (tenant CIDR, floating-IP pool, MTU, Nova disk backend). |
| 2026-05-23 | Reworked to a learning-oriented, staged method (find-and-modify templates, not copy-paste): added Stages 0–5, a throwaway `common` role to learn `template`/idempotence first, and `ansible-core` + `openstack.cloud`-only-for-bootstrap. **Changed the approach for controller-side Nova/Neutron to MANUAL one-time work** (no `nova_controller`/`neutron_controller` roles); only `nova_compute`/`neutron_compute` (plus the learning `common` role) are roles. |
| 2026-06-06 | Moved the general learning-approach rationale to [project-principles.md](project-principles.md), leaving a reference plus the Phase-2-specific application and the 2025.1 caveat. |
| 2026-06-06 | Corrected the Phase 1 issue #5 references: the lesson is "ensure the `service` project exists + verify role grants," not "role-grant typos." |
| 2026-05-24 | **Stages 0–1 executed and verified.** Status moved Planned → In progress. Recorded the Ansible-via-`uv` install (community 13.7 / core 2.20 / Python 3.12), the escalation model (login user, `become` default-off, password-protected sudo, `-K`), the inventory layout, and the five problems hit. Updated the Ansible-approach bullets (was "install `ansible-core` via dnf, passwordless sudo") and closed the "Ansible layout/inventory" open item (vault still deferred to Stage 4). |
| 2026-06-07 | Updated the Ansible project location: the playbooks now live in the repo's `ansible/` directory (moved from the repo root); doc paths are relative to it. |
| 2026-06-04 | **Stage 2 in progress** (`common` role rendering `/etc/hosts`). Corrected the Stage 1 `local_ip` record: it is defined on **all four** hosts (controller `.130` included — the controller is also a VTEP), not the three computes only. Recorded the Option-A decision to reuse `local_ip` for `/etc/hosts` (no separate `underlay_ip`), the role skeleton/template/task, and added `l2_population = true` to the linuxbridge config notes. |
| 2026-06-08 | **Stage 2 complete and verified.** The `common` role renders an inventory-driven `/etc/hosts` to all four nodes (FQDN-canonical column order, `\| sort`ed for idempotence), wired into `site.yml`; idempotence proven (second run all `ok`, no diff). Corrected the earlier (2026-06-04) record that described the template/task as already written — they were actually authored and verified in this session. Fixed `ansible.cfg`: `stdout_callback = yaml` → `result_format = yaml` (the `community.general.yaml` callback was removed in community.general 12.x, bundled in community 13.7). Logged the compute3 outage + cephadm root-SSH episode (restored hardened root key; new decision #30) and the discovery that the cluster runs **4 MONs**, not 1 (decision #15 corrected). |
| 2026-06-09 | **Closed the Nova ephemeral-disk-backend open item → Ceph RBD-backed** (decision #31): added the RBD libvirt config (`images_type = rbd`, `vms` pool, `client.nova` libvirt secret) to the Stage 4 step and rewrote the backend note from "still open" to "decided." **Added Stage 6 — Cinder (block storage), RBD-backed** (decision #32; gives the deferred Phase 1 `volumes` pool a home): controller-side by-hand install reusing the Glance service-account + RBD-keyring pattern, with the compute side reusing the #31 libvirt secret. Staged plan is now **0–6**; updated the status block, removed the Nova-backend open item, and extended the carried-forward Ceph-permissions note to `cinder`. |
| 2026-06-09 | **Stage 3 started** (controller-side Nova/Neutron prerequisites underway). Logged a troubleshooting episode: while standardizing the catalog/`auth_url` onto FQDNs, `openstack-glance-api` failed to restart with a `conf_read_file` RADOS error whose real cause was a mislabeled `/etc/ceph/ceph.conf` (`user_tmp_t`), fixed with `restorecon -Rv /etc/ceph/` — same class as Phase 1 issue #3 (SELinux labels). Noted a benign residual `glance_api_t`→`mysqld_exec_t` getattr denial on `mariadbd-safe-helper`, left as-is. |
