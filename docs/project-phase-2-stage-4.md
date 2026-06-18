# Phase 2 · Stage 4 — `nova_compute` and `neutron_compute` Roles

> Part of **[Phase 2](project-phase-2.md)**. **Status: planned** (not yet started).

## Planned steps

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
   differ per node** so keep the OVS `bridge_mappings`/provider-bridge port and `local_ip`
   per-host. After the
   role runs, `nova-manage cell_v2 discover_hosts` **once** on the controller (a
   `command` task with `run_once: true` — teaches that not every task runs on every host);
   verify `openstack compute service list` / `network agent list`.

> **Nova ephemeral disk backend — decided: Ceph RBD-backed** (decision #31): a `vms`
> pool, `client.nova` auth, a per-compute libvirt secret, `[libvirt] images_type = rbd`.
> Chosen over local qcow2 because it enables live migration, makes Ceph recovery visibly
> affect running VMs (a benchmark observable), reuses the Phase 1 keyring-permissions
> lesson, and shares the libvirt Ceph secret that Stage 6 Cinder also needs. Configured
> in this stage's libvirt step.

## Actual work completed

### `nova_compute` role — complete and verified (2026-06-18)

All three `nova-compute` services are `up` (`openstack compute service list`) and mapped
into `cell1` (`nova-manage cell_v2 list_hosts` shows compute1/2/3), with RBD-backed
ephemeral via the `vms` pool. A full `ansible-playbook site.yml` re-run reports the compute
hosts all `ok`/`changed=0` (idempotence proven). SELinux stayed enforcing throughout
(`ausearch -m avc` clean — the `template` module labels the keyring/`ceph.conf` correctly,
see decision #38).

**Pre-flight (read-only) findings.**
- **KVM:** `vmx` present on all three (24/32/16 logical CPUs) → `virt_type = kvm`
  (decision #36).
- **NICs differ** (issue #2): compute1 `eno1`, compute2/3 `enp0s31f6`. *Not* turned into
  Ansible vars — the compute OVS agents are **tunnel-only** (no `bridge_mappings`; the
  provider bridge lives only on the network node, decision #25), so the differing names are
  documentation, not a per-host knob.
- **Ceph prereqs were missing** → created the `vms` pool + `client.nova` auth by hand
  (one-time, controller-side): `ceph osd pool create vms` / `application enable rbd` /
  `rbd pool init vms`, then `ceph auth get-or-create client.nova mon 'profile rbd'
  osd 'profile rbd pool=vms, profile rbd-read-only pool=images' mgr 'profile rbd pool=vms'`
  (read-only on `images` is enough for COW-cloning Glance images into `vms`).
- **Compute repo state was empty** → mirrored the controller: the role installs
  `centos-release-openstack-epoxy` + `centos-release-ceph-reef` + `epel-release`, enables
  **CRB**, then installs `openstack-nova-compute` + `qemu-kvm-block-rbd` + `ceph-common` +
  `python3-rbd`. Note the host **Ceph client is Reef 18.2.8** (`.el9s`, matching the
  controller) even though the cluster is Squid-era — Ceph clients interoperate across an
  adjacent major, and the controller's Glance already proves this client works.

**Template derivation (`nova.conf.j2`).** Built by trimming the controller's hand-written
`nova.conf`: the per-host bits (`my_ip`, `[vnc] server_proxyclient_address`) became
`{{ local_ip }}`, FQDNs `{{ controller_fqdn }}`, and the rabbit string + four passwords
vault-backed. **Dropped** `[api_database]`/`[database]` (compute is DB-less — reaches the
DB only via conductor; this also keeps `NOVA_DBPASS` off the computes), the cruft
`[keystone]` group, `enabled_apis` (a nova-api setting), and the `[neutron]` metadata-proxy
lines (network-node-only). **Added** the `[libvirt]` RBD block (`virt_type = kvm`,
`images_type = rbd`, `images_rbd_pool = {{ ceph_vms_pool }}`, `rbd_user = nova`,
`rbd_secret_uuid`, `inject_* = false`, `disk_cachemodes="network=writeback"`) and the two
**compute-only** `[DEFAULT]` keys that the controller never needed (see problems 3–4 below).

**Ceph plumbing (decision #38).** `ceph.conf.j2` (minimal: `fsid` + `mon_host` from
`group_vars/all.yml`), `ceph.client.nova.keyring.j2` (`root:nova` `0640`, `no_log`), and
`ceph-nova-secret.xml.j2` (one shared `rbd_secret_uuid`). The `virsh secret` step is made
idempotent with a `secret-get-value` guard (`rc != 0` → define + set), so a re-run skips it.

**Cell discovery.** `nova-manage cell_v2 discover_hosts --verbose` as a dedicated
`hosts: controller` play, `become_user: nova`, with
`changed_when: "'Creating host mapping' in …stdout"` for idempotence.

#### Problems hit and fixes

1. **Template style / typos.** The `.j2` was built by editing the full annotated default
   `nova.conf` (kept, per the chosen convention), which introduced two `rbd`↔`rdb`
   transpositions (`images_type = rdb`, `images_rdb_pool`) — both silent RBD-killers
   (`rdb` is not a valid `images_type`; `images_rdb_pool` is an ignored unknown key). Caught
   in review (the file renders fine — verified 18 `{{ }}`, no stray Jinja delimiters) and
   fixed to `rbd`.
2. **No monolithic `libvirtd` on EL9 (modular libvirt).** `service: name=libvirtd` failed
   with `Could not find the requested service libvirtd`. RDO installs **modular** libvirt
   11.10 (`virtqemud`, `virtsecretd`, …), all socket-activated. **Fix:** ensure the
   `*.socket` units that actually exist (`virtqemud`/`virtsecretd`/`virtnodedevd`/
   `virtstoraged`) — *not* `virtproxyd` (not installed) and *not* `libvirtd` (absent).
   Verifying the unit list first (principle 13) avoided prescribing a non-existent socket.
3. **`compute_driver` required but unset.** First nova-compute start died with
   `Compute driver option required, but not specified`. It has no default; **fix:** add
   `compute_driver = libvirt.LibvirtDriver` to `[DEFAULT]`. Invisible on the controller
   (only nova-compute needs it).
4. **`state_path` defaulted to a read-only dir.** Next start:
   `Unable to write uuid to /usr/lib/python3.9/site-packages/compute_id: Permission denied`.
   nova-compute persists its node UUID under `state_path`, whose default is `$pybasedir`
   (the package install dir). **Fix:** `state_path = /var/lib/nova` in `[DEFAULT]`
   (nova-writable; also the parent of the existing `lock_path`). Again controller-invisible
   — only nova-compute writes `compute_id`.
5. **`discover_hosts` task errored on `changed_when`, and first pass mapped only one host.**
   As a `run_once` + `delegate_to` + `register` `post_task`, the `changed_when` conditional
   failed with `'cell_discover' is undefined` (the registered var didn't survive the
   delegate/run-once machinery) — even though the command itself succeeded (`rc=0`). And it
   reported only **1** unmapped compute: compute2/3 had been built seconds earlier in the
   same run and hadn't written their `compute_nodes` records yet (the `services` heartbeat
   shows them `up`, but `discover_hosts` reads `compute_nodes`). **Fix:** moved discovery to
   a dedicated `hosts: controller` play (reliable `register`/`changed_when`, the natural home
   for a controller one-shot) and re-ran once compute2/3 had reported — all three then mapped
   into `cell1`.

_Neutron compute side (the `neutron_compute` role) — pending._
