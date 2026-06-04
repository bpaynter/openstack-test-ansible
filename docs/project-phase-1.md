# Phase 1 — Ceph and the Controller Node, by Hand

Stand up the storage and control plane by hand: bootstrap Ceph with `cephadm`, then
manually install a minimal **OpenStack 2025.1** control plane (Keystone, Glance,
Placement) on the controller (7071), with Glance backed by Ceph RBD. Nova and Neutron
are deliberately left out — adding them to the compute nodes is the repetitive work
that motivates the hand-rolled Ansible of Phase 2.

> **Status:** **Completed** (2026-05-23). At handoff the full control plane was
> verified: Ceph `HEALTH_OK` with 5 OSDs, Keystone issuing Fernet tokens, Glance
> storing images in the Ceph `images` RBD pool, and Placement ready. See "Actual work
> completed" below.

All hardware, RAM, disk layout, and IP assignment are assumed done per
[inventory.md](inventory.md) and [project-phase-0.md](project-phase-0.md).

## Open items settled at the start of Phase 1

These were the remaining open items from earlier planning; all were settled here:

- **Name resolution** — identical `/etc/hosts` on all four nodes, no real DNS:
  `192.168.1.130 controller.lab.internal controller`, `.131 compute1…`, `.132
  compute2…`, `.133 compute3…`.
- **Gateway** — all nodes point at the normal LAN gateway for outbound (needed to pull
  packages and container images).
- **SELinux** — left **enforcing** (`setenforce 0` is the fast escape hatch; inspect
  with `ausearch -m avc -ts recent`).
- **Firewall** — **firewalld disabled** (`systemctl disable --now firewalld`), the
  pragmatic choice for a short-lived isolated lab; keeping it on would mean opening a
  long per-service port list with little learning value in Phase 1.
- **Ceph release** — **Squid 19.2.x** (what `cephadm` pulls by default via
  `--release squid`). RDO Epoxy 2025.1 was validated against **Reef 18.2.0**; Squid
  works fine with it, but the skew is recorded since Phase 3's Kolla has its own Ceph
  version handling.
- **FQDN hostnames** — keep the `*.lab.internal` FQDNs and bootstrap with
  `cephadm bootstrap --allow-fqdn-hostname`; then use FQDNs consistently in every
  `ceph orch host add`. The risk the bootstrap check guards against is *inconsistency*
  (mixing short and FQDN names), not FQDNs themselves. Verify `hostname` and
  `hostname -f` agree on each node first.

## Planned steps

1. **Base OS prep (all four nodes)** — set the FQDN hostname, `dnf update` + reboot,
   install/enable chrony (time sync is critical for both Ceph and Keystone tokens),
   disable automatic updates (`dnf-makecache.timer`), and set up passwordless root SSH
   from the controller to all four hosts (cephadm needs it).
2. **Ceph bootstrap with `cephadm` (controller = 7071)** — install cephadm from the
   Squid repo, `cephadm bootstrap --mon-ip 192.168.1.130 --allow-fqdn-hostname`,
   install `ceph-common`, add the three OSD hosts by FQDN, create the **5 OSDs
   (2 + 1 + 2)** explicitly by device (not `--all-available-devices`), create the
   `images` RBD pool (32 PGs) and the `client.glance` auth user.
3. **Enable the OpenStack 2025.1 repos (controller)** —
   `centos-release-openstack-epoxy`; disable EPEL or use the versionlock plugin;
   install `python3-openstackclient` and `openstack-selinux`.
4. **SQL / message queue / cache (controller)** — MariaDB (bind to 192.168.1.130),
   RabbitMQ (create the `openstack` user), memcached (listen on the controller IP).
5. **Keystone (identity)** — DB + `db_sync`, `fernet_setup`/`credential_setup`,
   `keystone-manage bootstrap`, Apache/WSGI, `admin-openrc`, confirm with
   `openstack token issue`.
6. **Glance (image service), Ceph RBD backend** — DB, Keystone identity + endpoints,
   wire to Ceph, upload CirrOS, confirm the image UUID appears in `rbd -p images ls`.
7. **Placement (resource inventory)** — DB, Keystone identity + endpoints, runs under
   Apache; confirm with `placement-status upgrade check`.
8. **Verify the whole control plane** — `openstack token issue`, `image list`,
   `endpoint list`, `ceph -s`.

## Configuration notes (gotchas carried forward)

- **`keystone.conf` is minimal** — only `[database] connection` and
  `[token] provider = fernet` need setting; everything else stays at package
  defaults. Use `crudini` rather than hand-editing. `provider = fernet` *declares* the
  provider; `keystone-manage fernet_setup` *creates* the keys it depends on — both are
  required. Keep service passwords free of `@ : / #` (URL-structural characters) to
  avoid breaking the DB connection string; `openssl rand -hex 16` gives a clean value.
- **No Apache symlink on RDO/AlmaLinux** — the `openstack-keystone` RPM drops its conf
  straight into `/etc/httpd/conf.d/` (RHEL-family Apache has no
  `sites-available`/`sites-enabled`). The upstream "symlink `wsgi-keystone.conf`" step
  is Ubuntu-specific. Set `ServerName controller` in `httpd.conf`; confirm
  `python3-mod_wsgi` is installed; `curl http://controller:5000/v3` should return JSON.
- **`admin-openrc`** is a plain shell script of `export OS_*` statements (username,
  password, project `admin`, domain `Default`, `OS_AUTH_URL=http://controller:5000/v3`,
  identity API v3, image API v2). `chmod 600` it; variables only live in the shell that
  `source`s it.
- **Glance multi-store (2025.1)** — use `enabled_backends = ceph:rbd` in `[DEFAULT]`,
  `default_backend = ceph` in `[glance_store]`, and a `[ceph]` per-backend section with
  `rbd_store_pool = images`, `rbd_store_user = glance`,
  `rbd_store_ceph_conf = /etc/ceph/ceph.conf`. The older `[glance_store] stores /
  default_store` keys are **deprecated** — do not set them. The three names
  (`enabled_backends` label, `default_backend`, and the per-backend section header)
  must match exactly. `rbd_store_user = glance` (no `client.` prefix). `rbd_store_chunk_size`
  stays at the default **8** (256 KB) — drop the line.
- **`[keystone_authtoken]`** is near-identical across services; only `username`/
  `password` change. `www_authenticate_uri` and `auth_url` both = `http://controller:5000`
  (no `/v3`), `memcached_servers = controller:11211`, `auth_type = password`,
  `project_name = service`, domains `Default`. It is a matched set with two CLI steps:
  `openstack user create … <svc>` and `openstack role add --project service --user <svc> admin`.
- **Ceph keyring** (`/etc/ceph/ceph.client.glance.keyring`) is an INI file:
  `[client.glance]` header + `key` + three `caps` lines (`mon`/`osd`/`mgr` =
  `profile rbd[ pool=images]`). Regenerate cleanly with
  `ceph auth get client.glance -o <file>` rather than editing by hand. The filename
  pattern `ceph.client.glance.keyring` is how the client locates it (no keyring-path
  option in the Glance config).

## Actual work completed

Phase 1 was carried out on the controller and the three OSD hosts and finished with a
fully verified control plane. Notable events and the five problems hit:

1. **FQDN bootstrap warning** — `cephadm bootstrap` complained the hostname was an
   FQDN. Resolved by keeping the FQDNs and re-running with `--allow-fqdn-hostname`
   (rather than renaming all four hosts).
2. **Stale `/dev/md127` on compute3 (7050)** — its two OSD SSDs were part of an old
   mdadm RAID array. After tearing the array down, `ceph orch device ls` still showed
   `md127` (cephadm caches host inventory and refreshes on a ~15–30 min interval).
   Fixed with `ceph orch device ls --refresh`, then clearing leftover RAID metadata
   (`mdadm --zero-superblock` + `wipefs -a`, and checking `mdadm.conf` for a stale
   `ARRAY` line) and `ceph orch device zap`. Also: compute3's free disks were `sda`/`sdb`,
   not the `sdb`/`sdc` the plan assumed — device letters are not guaranteed across hosts.
3. **Glance `RADOS object not found (error calling conf_read_file)`** — the
   `openstack-glance-api` service (running as the `glance` user) could not read
   `/etc/ceph/ceph.conf` and the keyring, which `cephadm`/`ceph auth get` had created
   `root:root` mode `600`. Fixed with `chown root:glance` + `chmod 640` on both files
   (and `restorecon -Rv /etc/ceph/` if SELinux denies).
4. **Glance image create → `401 Unauthorized`** — service started but the first real
   request failed authentication.
5. **Root cause of the 401: a typo** — the role grant had been run as
   `openstack role add --project service --user glance admi` (missing the `n` in
   `admin`), so the `glance` user never got the `admin` role in the `service` project.
   Re-running with the correct `admin` fixed it, after which the CirrOS upload
   succeeded and the image UUID appeared in `rbd -p images ls`.

**Final verified state at handoff:** containerized 5-OSD Ceph (`HEALTH_OK`, 2+1+2
across the three hosts), Keystone issuing Fernet tokens (`openstack token issue`),
Glance storing images in the Ceph `images` RBD pool, Placement ready, and all three
services registered in `openstack endpoint list`.

## Handoff to Phase 2

Nova and Neutron were intentionally not installed. Adding `nova-compute` + Neutron
agents to compute1/compute2/compute3 is the "same steps three times" repetition that
becomes the **hand-rolled Ansible** work of Phase 2 (under the 0–3 convention; the
Kolla-Ansible rebuild is Phase 3).

> Note: the source build-plan handoff loosely described "Phase 2" as the Kolla-Ansible
> rebuild, but its own reasoning (Nova/Neutron left out to become the Ansible
> transition) and the project's phase numbering put the **hand-rolled Ansible compute
> nodes** next, as Phase 2.

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-23 | Phase 1 executed and completed: cephadm Ceph bootstrap (Squid, `--allow-fqdn-hostname`), 5 OSDs (2+1+2), `images` pool + `client.glance`, OpenStack 2025.1 Keystone/Glance(Ceph RBD)/Placement on the controller. Open items (name resolution, gateway, SELinux, firewall, Ceph release, FQDN hostnames) settled. Five problems documented with fixes. |
