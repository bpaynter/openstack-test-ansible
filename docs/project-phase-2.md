# Phase 2 — Compute Nodes via Hand-Rolled Ansible

Add the **compute plane** to the cluster Phase 1 left running: **Nova**
(controller-side API/scheduler/conductor/novncproxy plus a compute agent on every
node) and **Neutron** (controller-side server plus the network-node and per-compute
agents). The work is the *same steps three times* across compute1/2/3 — exactly the
repetition that hand-rolled Ansible exists to absorb. There is **no teardown**: the
controller keeps its Phase 1 services and Phase 2 adds to it.

> **Status:** **Planned.** This chunk produced the Phase 2 design (scope, networking
> model, Ansible structure, step outline). The detailed, config-level steps —
> especially the VXLAN Neutron rewrite — are produced in a later implementation chat;
> no Phase 2 execution is reported yet.

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

The human's explicit goal here is to **learn how Ansible works**, so the phase is taught
by *finding a template and modifying it for this cluster*, not by copy-pasting finished
playbooks. The pedagogy: generate the standard skeletons (`ansible-galaxy role init`,
`ansible-config init --disabled`), then walk each file line by line deciding **what is
constant vs. what varies per host** — that pass is the learning, because it forces
understanding of every setting. The phase is staged from low-stakes to real.

> Caveat carried into implementation: 2025.1 service config keys can shift between minor
> versions, and linuxbridge-vs-OVS guidance changes release to release — cross-check the
> official RDO/AlmaLinux 2025.1 install guide (the same discipline that caught the
> Ubuntu-specific Apache symlink in Phase 1).

## Ansible approach

Run Ansible from the **controller** as the control node (it already has SSH reach and
`admin-openrc`, and sits inside `lab.internal` so name resolution already works).
Ansible installs nothing on managed nodes — it pushes Python over SSH and runs modules.

- Install **`ansible-core`** (the engine + built-in modules). The Nova/Neutron *install*
  work uses only built-in modules (`dnf`, `template`, `service`, `command`) — good for
  learning. Add the **`openstack.cloud`** collection (`ansible-galaxy collection install
  openstack.cloud`) only for the final network-bootstrap stage (API-driven, not file
  edits).
- Set up passwordless SSH **and** passwordless `sudo` from the controller to itself and
  compute1/2/3 (test with `sudo -n true`).
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

0. **Stage 0 — Ansible control setup** — install `ansible-core` on the controller, set
   up passwordless SSH + sudo.
1. **Stage 1 — Inventory + prove connectivity** — build the YAML inventory (groups +
   per-host `local_ip`), then `ansible all -m ping` and an ad-hoc `command` to confirm
   targeting. ("A playbook is just ad-hoc commands made repeatable.")
2. **Stage 2 — A throwaway `common` role to learn the mechanics** — `ansible-galaxy role
   init common`, then a low-stakes, genuinely useful task: render `/etc/hosts` identically
   on all four nodes via the `template` module (`templates/hosts.j2` → `/etc/hosts`).
   Run it twice; the second run must report `ok` not `changed`. This teaches the role
   skeleton (`tasks`/`templates`/`defaults`/`vars`/`handlers`/`meta`), the single most
   important module (`template`), and idempotence — before touching Nova.
3. **Stage 3 — Controller-side Nova & Neutron (MANUAL, one-time)** — *not* a role, because
   the Ansible seam is repetition and this isn't repeated. Done by hand following the
   2025.1 guide, reusing the Phase 1 service-account pattern (user create → role add
   `--project service` → `[keystone_authtoken]`; **verify each grant** with `role
   assignment list` — the Phase 1 issue #5 typo class).
   - **Nova:** `nova`/`nova_api`/`nova_cell0` DBs + `nova` service user; install
     nova-api/conductor/scheduler/novncproxy; configure `nova.conf`; the `nova-manage
     cell_v2` cell setup is the one unfamiliar part vs. Phase 1 — read the guide's cell
     section. (novncproxy gives VM console access later.)
   - **Neutron:** `neutron` DB + service user; install neutron server +
     linuxbridge/l3/dhcp/metadata agents; configure `neutron.conf`
     (`service_plugins = router`), `ml2_conf.ini` (`type_drivers` incl. `flat`+`vxlan`,
     `tenant_network_types = vxlan`, `mechanism_drivers = linuxbridge`, `vni_ranges`),
     `linuxbridge_agent.ini` (`enable_vxlan = true`, `local_ip = 192.168.1.130` on the
     controller), and the l3/dhcp/metadata agent configs. **Keep these hand-written
     `.conf` files** — the compute-side configs are nearly identical, which sets up
     Stage 4.
4. **Stage 4 — `nova_compute` and `neutron_compute` roles (the loop on compute1/2/3)** —
   the payoff. Convert a Stage-3 `.conf` into `templates/nova.conf.j2`, then go line by
   line replacing host/environment-specific values with Jinja2 vars (`local_ip =
   192.168.1.130` → `local_ip = {{ local_ip }}`; controller hostname, RabbitMQ string,
   passwords → `group_vars` refs; genuinely-identical lines stay literal). `tasks/main.yml`
   is then short: `dnf` install → `template` render → `service` start, with restarts via
   handlers. Per-node specifics: `[vnc] server_proxyclient_address` = that node's own IP;
   `[libvirt] virt_type = kvm` (VT-x i7s — fail loudly if `vmx` absent); **NIC names may
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
   SSH in from the home LAN. When that works, Phase 2 is done.

> **Nova ephemeral disk backend (still open):** local qcow2 on each node's boot disk
> (simplest) vs. **Ceph RBD-backed** ephemeral (a `vms` pool, `client.nova` auth, a
> libvirt secret per compute node, `[libvirt] images_type = rbd`). RBD-backed enables
> live migration and makes Ceph recovery visibly affect running VMs — and reuses the
> Phase 1 keyring-permissions lesson. Decide before Stage 4's libvirt config.

## Open items for Phase 2 implementation

- **Tenant subnet CIDR** (e.g. `10.0.0.0/24`).
- **Floating-IP allocation pool** carved from `192.168.1.0/24`, confirmed against the
  home router's actual DHCP range and the static host IPs.
- **MTU handling** for VXLAN (raise underlay MTU vs. tenant network MTU 1450).
- **Nova ephemeral disk backend** — local qcow2 vs. Ceph RBD `vms` pool.
- **`kvm` vs `qemu`** — `kvm` expected (VT-x i7s), but BIOS virtualization must be
  confirmed enabled on each node.
- The Ansible project layout, inventory, and `ansible-vault` secret handling.

## Problems anticipated (Phase 1 lessons carried forward)

- **Role-grant typos (Phase 1 issue #5)** — every `openstack role add` is a 401 waiting
  to happen; add an explicit `role assignment list` verification after each grant.
- **Ceph file permissions (issue #3)** — if Nova goes RBD-backed, the `nova`/`qemu` user
  must read `/etc/ceph/` files: `chown root:<group>` + `chmod 640` + `restorecon`.
- **Per-node device/NIC names (issue #2)** — NIC names differ across these OptiPlex
  models just as disk letters did; **never hardcode the interface** in
  `physical_interface_mappings` or `local_ip` — make them per-host inventory variables.
  This is the single most likely thing to bite Phase 2.
- **SELinux** — keep it `enforcing`; check `ausearch -m avc` before reaching for
  permissive.
- **FQDN consistency** — keep using FQDNs everywhere in the inventory.

## Actual work completed

None yet — this chunk is Phase 2 *planning*. To be filled in as later chunks execute
the playbooks.

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-23 | Phase 2 designed: scope (Nova + Neutron via hand-rolled Ansible, no teardown), **VXLAN self-service networking** chosen over flat-provider (dual-DHCP race) and VLAN (needs a managed switch), controller promoted to network node, Ansible role/layout outline, and the step plan. Open items recorded (tenant CIDR, floating-IP pool, MTU, Nova disk backend). |
| 2026-05-23 | Reworked to a learning-oriented, staged method (find-and-modify templates, not copy-paste): added Stages 0–5, a throwaway `common` role to learn `template`/idempotence first, and `ansible-core` + `openstack.cloud`-only-for-bootstrap. **Changed the approach for controller-side Nova/Neutron to MANUAL one-time work** (no `nova_controller`/`neutron_controller` roles); only `nova_compute`/`neutron_compute` (plus the learning `common` role) are roles. |
