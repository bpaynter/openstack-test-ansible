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
   differ per node** so keep `physical_interface_mappings`/`local_ip` per-host. After the
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

_Not yet started._
