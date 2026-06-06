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

## Ansible approach

Run Ansible from the **controller** (it already has SSH reach to all nodes and the
`admin-openrc` needed for verification).

- Install `ansible-core` plus the `community.general` and `ansible.posix` collections.
- Confirm passwordless root SSH from the controller to compute1/2/3 for the user
  Ansible runs as (cephadm distributed its *own* key in Phase 1; Ansible needs its own
  or a shared one).
- Project layout: `inventory.ini` (a `controller` host and a `compute` group of
  compute1/2/3, by FQDN), `group_vars/all.yml` (shared passwords, hostnames, Ceph pool
  names) and `group_vars/compute.yml`, `roles/` (`nova_controller`,
  `neutron_controller`, `nova_compute`, `neutron_compute`), and `site.yml`.
- Encrypt `group_vars/all.yml` with **`ansible-vault`** (one DB user + password per
  service, plus service-account, RabbitMQ, and DB passwords).
- Make roles **idempotent and re-runnable**: `template:` for config files (not
  `lineinfile`), the `mysql_db`/`mysql_user` modules for databases, and `command:`
  with `creates=` guards for one-shot operations (`nova-manage db sync`, etc.).

## Planned steps

0. **Ansible control setup** — install Ansible on the controller, verify SSH, create
   the project layout and vaulted vars.
1. **Controller-side Nova (one-time)** — create the `nova_api`, `nova`, `nova_cell0`
   DBs + `nova` DB user; Keystone `nova` service user + `admin` role on the `service`
   project + `compute` service and endpoints at `http://controller:8774/v2.1`
   (**verify the role grant** — the Phase 1 issue #5 typo class); install
   nova-api/conductor/scheduler/novncproxy; template `/etc/nova/nova.conf`
   (`[api_database]`/`[database]`, `[DEFAULT] transport_url`, `[api] auth_strategy`,
   `[keystone_authtoken]`, `[placement]`, `[glance] api_servers`, `[oslo_concurrency]
   lock_path`, `[vnc]`); run `nova-manage api_db sync` → `cell_v2 map_cell0` →
   `cell_v2 create_cell --name=cell1` → `db sync`; start the four services; verify
   `nova-manage cell_v2 list_cells` and `openstack compute service list`.
2. **Controller-side Neutron (one-time)** — `neutron` DB + user; Keystone `neutron`
   service user + role + `network` service + endpoints at `http://controller:9696`;
   install neutron server + ml2 + linuxbridge; template `neutron.conf`, `ml2_conf.ini`
   (`type_drivers = flat,vlan,vxlan`, `tenant_network_types = vxlan`, `mechanism_drivers
   = linuxbridge`, `vni_ranges`, flat provider network for the external side),
   `linuxbridge_agent.ini` (`physical_interface_mappings = provider:<NIC>`,
   `enable_vxlan = true`, per-host `local_ip`, security-group iptables driver),
   `dhcp_agent.ini`, `metadata_agent.ini` (`nova_metadata_host` + shared secret); add
   `[neutron]` to the controller `nova.conf`; `service_plugins = router`;
   `neutron-db-manage upgrade head`; start neutron-server + the L3, linuxbridge, DHCP,
   and metadata agents on the controller (the network node).
3. **`nova_compute` role (loop on compute1/2/3)** — install `openstack-nova-compute`;
   template `nova.conf` (mostly identical to the controller's; per-node differences are
   `[vnc] server_proxyclient_address` = that node's own IP; no `[api_database]`/DB on
   compute nodes); `[libvirt] virt_type = kvm` (all four are VT-x i7s — confirm with a
   task that fails loudly if `vmx` is absent, i.e. BIOS virtualization disabled); start
   `libvirtd` + `openstack-nova-compute`. Then run **`nova-manage cell_v2 discover_hosts`
   once on the controller** (a `post_tasks`/handler step) so the scheduler can place on
   the new hosts; verify `openstack compute service list`.
4. **`neutron_compute` role (loop on compute1/2/3)** — install
   `openstack-neutron-linuxbridge`; template the compute subset of `neutron.conf` and
   `linuxbridge_agent.ini` (same `physical_interface_mappings` and per-host `local_ip` —
   **NIC names may differ per node**, so make it a per-host variable); add `[neutron]`
   to each compute `nova.conf` and restart nova-compute (handler); start the linuxbridge
   agent; verify `openstack network agent list` shows agents alive on all four nodes.
5. **Nova ephemeral disk backend (decision point — open)** — local qcow2 on each node's
   boot disk (simplest) vs. **Ceph RBD-backed** ephemeral (a `vms` pool, `client.nova`
   auth, a libvirt secret per compute node, `[libvirt] images_type = rbd`). RBD-backed
   enables live migration and makes Ceph recovery visibly affect running VMs — a good
   benchmark observable — and reuses the Phase 1 keyring-permissions lesson.
6. **Bootstrap network + flavors, then verify** — create the provider/external network
   and the VXLAN tenant network + subnet (tenant CIDR, e.g. `10.0.0.0/24`) and a router
   linking them; allocate the floating-IP pool from `192.168.1.0/24` (outside the home
   DHCP range and `.130–.133`); create small flavors (`m1.tiny`/`m1.small`), a keypair,
   and SSH/ICMP security-group rules; then launch a CirrOS VM, assign a floating IP,
   ping/SSH it, and repeat per compute host (`--host`, admin-only) to confirm all three
   nodes can launch. If RBD-backed, confirm `rbd -p vms ls`.

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
