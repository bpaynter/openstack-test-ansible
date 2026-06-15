# Phase 2 — Compute Nodes via Hand-Rolled Ansible

Add the **compute plane** to the cluster Phase 1 left running: **Nova**
(controller-side API/scheduler/conductor/novncproxy plus a compute agent on every
node) and **Neutron** (controller-side server plus the network-node and per-compute
agents). The work is the *same steps three times* across compute1/2/3 — exactly the
repetition that hand-rolled Ansible exists to absorb. There is **no teardown**: the
controller keeps its Phase 1 services and Phase 2 adds to it.

> **Status:** **In progress.** Design is complete (scope, VXLAN networking model,
> staged Ansible approach). **Stages 0–3 are executed and verified** — the Ansible control
> node + inventory, the throwaway `common` role, and the controller-side Nova & Neutron
> bring-up (Cells v2; server + L3/DHCP/metadata + the **OVS** agent all `up`). **Stage 4
> (the compute roles) is next**; Stages 5–6 (bootstrap + Cinder) follow. Each stage's
> detailed step plan and execution log lives in its own `project-phase-2-stage-N.md`
> file — see the [Stages](#stages) table.

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

Phase 2 therefore uses **VXLAN self-service networking** with the **Open vSwitch (OVS)**
mechanism driver (originally Linux bridge — RDO 2025.1 ships no linuxbridge agent, so
decision #24 was amended to OVS; the model below is unchanged):

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
  the OVS agent sets `tunnel_types = vxlan` and a **per-host `local_ip`** (each node's own
  `192.168.1.x` tunnel endpoint) — another per-node inventory variable. The flat external
  net rides an **OVS provider bridge** (`bridge_mappings`), which on a single-NIC node
  takes over the host's `192.168.1.x` interface — a connectivity-sensitive step handled at
  Stage 5, not bring-up.
- The floating-IP pool is carved from `192.168.1.0/24` and must sit **outside** the
  home router's DHCP range and outside the static host IPs (`.130–.133`).
- **MTU:** VXLAN adds ~50 bytes of header — raise the underlay MTU or set the tenant
  network MTU to 1450, or hit the classic "SSH connects then hangs" fragmentation
  symptom.

## Learning approach

Phase 2 follows the project's learning-first principles — *find a template and modify it
for this cluster* rather than copy-pasting playbooks, and build understanding on
low-stakes exercises before real services. See
[project-principles.md](project-principles.md) (principles 1–4). The staged plan (now
split across the per-stage files) applies them: generate the standard skeletons
(`ansible-galaxy role init`, `ansible-config init --disabled`) and walk each file line by
line, deciding what is constant versus what varies per host.

> Implementation caveat: 2025.1 service config keys can shift between minor versions, and
> linuxbridge-vs-OVS guidance changes release to release — cross-check the official
> RDO/AlmaLinux 2025.1 install guide (the same discipline that caught the Ubuntu-specific
> Apache symlink in Phase 1).

## Ansible approach

Run Ansible from the **controller** as the control node (it already has SSH reach and
`admin-openrc`, and sits inside `lab.internal` so name resolution already works).
Ansible installs nothing on managed nodes — it pushes Python over SSH and runs modules.
The Ansible project lives in the repo's **`ansible/`** directory; the file paths in the
per-stage files are relative to it.

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

## Stages

Phase 2 is built in stages 0–6 (staged for learning — generate the standard skeletons and
walk each file line by line, deciding what is constant versus what varies per host). Each
stage has its own file with the detailed step plan and its execution log:

| Stage | Scope | Status | File |
|---|---|---|---|
| 0–1 | Ansible control node + cluster inventory | ✅ complete | [project-phase-2-stage-0-1.md](project-phase-2-stage-0-1.md) |
| 2 | Throwaway `common` role (learn the mechanics) | ✅ complete | [project-phase-2-stage-2.md](project-phase-2-stage-2.md) |
| 3 | Controller-side Nova & Neutron (manual, one-time) | ✅ complete | [project-phase-2-stage-3.md](project-phase-2-stage-3.md) |
| 4 | `nova_compute` / `neutron_compute` roles (the loop on compute1/2/3) | ⬜ planned | [project-phase-2-stage-4.md](project-phase-2-stage-4.md) |
| 5 | Bootstrap the OpenStack objects + test | ⬜ planned | [project-phase-2-stage-5.md](project-phase-2-stage-5.md) |
| 6 | Cinder (block storage), RBD-backed | ⬜ planned | [project-phase-2-stage-6.md](project-phase-2-stage-6.md) |

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
  models just as disk letters did; **never hardcode the interface** in the OVS
  `bridge_mappings`/provider-bridge port or `local_ip` — make them per-host inventory
  variables. This is the single most likely thing to bite Phase 2.
- **SELinux** — keep it `enforcing`; check `ausearch -m avc` before reaching for
  permissive.
- **FQDN consistency** — keep using FQDNs everywhere in the inventory.

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
| 2026-06-12 | **Stage 3 — Nova controller-side complete and verified.** Recorded the full Nova bring-up (DBs/service account/endpoints, FQDN catalog cleanup, `nova.conf` section-by-section, Cells v2 bootstrap) with `nova-scheduler` and `nova-conductor` both `up`. Logged three troubleshooting episodes: the **placement** Apache vhost missing its `Require all granted` block (EL packaging gap; the "no supported versions" error was really a 403 routing problem), and the two-part **RabbitMQ** failure — a boot-ordering race (`epmd` before network-online; fixed with a drop-in) and rabbit 3.9 on an unsupported Erlang 26 that **EPEL had shadowed over the SIG's Erlang 24**, fixed by reinstalling with EPEL excluded and pinning `excludepkgs=erlang*` (decision #33). Neutron controller-side is the remaining Stage 3 work. |
| 2026-06-12 | Added **`scripts/healthcheck.sh`** — a read-only, bottom-up control-plane smoke test (systemd units, Ceph, MariaDB, RabbitMQ, Keystone, Glance, Placement, Nova, Neutron) that exits non-zero on real failures and flags expected-empty results (no hypervisors/networks pre-Stage-4/5) as INFO. Serves as the known-good baseline before Stage 4. |
| 2026-06-12 | **Stage 3 complete** (controller-side Nova **and** Neutron): recorded the full OVS-based Neutron bring-up (packages, `neutron.conf`/`ml2_conf.ini`/`openvswitch_agent.ini`/agent configs, `nova.conf [neutron]` fill, empty `br-provider`, DB migration, services) with the L3/DHCP/OVS agents `up`; logged the `plugin.ini`-vs-`ovn.ini` symlink, the `os_neutron_dac_override` SELinux boolean (decision #34), a benign one-shot `cache_home_t` denial, the recurring glance/`ceph.conf` relabel fixed durably with `restorecond` (decision #35, root-caused to Ceph #9530), and a **memcached `network-online` boot-ordering fix** (same class as the RabbitMQ `epmd` race). Stages table + status updated; Stage 4 is next. |
| 2026-06-12 | **Neutron L2 backend Linux bridge → Open vSwitch (OVS)** (decision #24 amended, R12 added): RDO 2025.1 Epoxy ships no linuxbridge agent, so the networking-model section now names OVS — `tunnel_types = vxlan` + per-host `local_ip`, with the flat external net on an OVS provider bridge (`bridge_mappings`). The VXLAN self-service model (#14) and the Stage 3–6 structure are unchanged; updated the consequences bullet and the NIC-mapping "problems anticipated" note. |
| 2026-06-12 | **Split this file into per-stage files.** `project-phase-2.md` is now the overview/index — it keeps the cross-cutting design (networking model, learning/Ansible approach), the Phase-2-wide open items and "problems anticipated," and this changelog, plus a new [Stages](#stages) table. Each stage's detailed step plan and execution log moved to `project-phase-2-stage-N.md` (stages 0 and 1 share one file, as they were executed and logged as a unit). No content was dropped; the staged "Planned steps" list and the "Actual work completed" logs were re-homed verbatim into the stage files. |
