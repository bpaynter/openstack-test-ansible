# Phase 2 · Stage 3 — Controller-side Nova & Neutron (manual, one-time)

> Part of **[Phase 2](project-phase-2.md)**. **Status: in progress** — Nova
> controller-side complete and verified (2026-06-12); **Neutron controller-side under way**
> — prerequisites (DB, service account, endpoints) done; packages + configs next. The
> Neutron half fills the `[neutron]` placeholder left in `nova.conf`.

This stage is *not* a role, because the Ansible seam is repetition and this isn't
repeated. Done by hand following the 2025.1 guide, reusing the Phase 1 service-account
pattern (ensure the `service` project exists → user create → role add `--project service`
→ `[keystone_authtoken]`; **verify each grant** with `role assignment list` — the Phase 1
issue #5 lesson).

## Planned steps

- **Nova:** `nova`/`nova_api`/`nova_cell0` DBs + `nova` service user; install
  nova-api/conductor/scheduler/novncproxy; configure `nova.conf`; the `nova-manage
  cell_v2` cell setup is the one unfamiliar part vs. Phase 1 — read the guide's cell
  section. (novncproxy gives VM console access later.)
- **Neutron:** `neutron` DB + service user; install neutron server +
  OVS/l3/dhcp/metadata agents; configure `neutron.conf`
  (`service_plugins = router`), `ml2_conf.ini` (`type_drivers` incl. `flat`+`vxlan`,
  `tenant_network_types = vxlan`, `mechanism_drivers = openvswitch`, `vni_ranges`),
  `openvswitch_agent.ini` (`[ovs] local_ip = 192.168.1.130` + `bridge_mappings`,
  `[agent] tunnel_types = vxlan`, `l2_population = true`), and the l3/dhcp/metadata agent
  configs (`interface_driver = openvswitch`). **Keep these hand-written `.conf` files** —
  the compute-side configs are nearly identical, which sets up Stage 4. (OVS, not
  linuxbridge — see the discovery note below and decision #24.)

## Actual work completed

**Nova controller-side — complete.** Created the `nova`, `nova_api`, and `nova_cell0`
databases and the `nova` service account (`admin` on the `service` project), plus the
three Compute API endpoints (public/internal/admin) at
`http://controller.lab.internal:8774/v2.1`. Standardized the Keystone catalog and every
`auth_url` onto the FQDN (`controller` → `controller.lab.internal`) and confirmed
`openstack endpoint set --url` edits an endpoint in place — no delete/recreate — which
fixed an `:8884` port typo. Installed
`openstack-nova-api`/`-conductor`/`-novncproxy`/`-scheduler` and wrote `nova.conf`
section by section against the live 2025.1 RDO guide (`[DEFAULT]`
`transport_url`/`my_ip = 192.168.1.130`, `[api_database]`/`[database]`,
`[keystone_authtoken]` + `[service_user]`, `[placement]`, `[glance] api_servers =
http://controller.lab.internal:9292`, `[oslo_concurrency] lock_path =
/var/lib/nova/tmp`, `[vnc]`; the `[neutron]` section is a placeholder until the Neutron
half lands). Four distinct passwords are in play and were kept straight: `NOVA_DBPASS`,
the `nova` Keystone password, `RABBIT_PASS`, and `PLACEMENT_PASS`. Bootstrapped Cells v2
as `sudo -u nova` (never root — avoids root-owned files under the service dirs):
`nova-manage api_db sync` → `map_cell0` → `create_cell --name=cell1` → `nova-manage db
sync`, verified with `list_cells` (cell0 on `none:/` → `nova_cell0`; cell1 on the
RabbitMQ transport → `nova`). After the three fixes below, `sudo -u nova nova-status
upgrade check` passes and `openstack compute service list` shows **nova-scheduler** and
**nova-conductor** both `up`. Remaining Stage 3 work is the Neutron controller side
(which fills the `[neutron]` placeholder).

**Neutron controller-side — in progress.** Prerequisites done and verified (2026-06-12),
mirroring the Nova/Phase 1 pattern: created the `neutron` database with grants for
`'neutron'@'localhost'` and `'neutron'@'%'` (the `%` grant matters — neutron connects over
TCP to `controller.lab.internal`, not the unix socket); created the `neutron` service user
and granted it `admin` on the `service` project, **verified with `openstack role
assignment list`** (`admin | neutron@Default | service@Default`, not inherited — the issue
#5 check); registered the `neutron` **network** service and its three endpoints
(public/internal/admin), all at `http://controller.lab.internal:9696`. Remaining: install
the server + OVS/l3/dhcp/metadata agents (see the discovery below), write `neutron.conf`
(`core_plugin = ml2`, `service_plugins = router`, `transport_url`, `[keystone_authtoken]`,
the `[nova]` notify-back credentials, `[oslo_concurrency] lock_path` — all backend-agnostic)
plus `ml2_conf.ini` / `openvswitch_agent.ini` / the agent configs, fill `nova.conf
[neutron]`, `neutron-db-manage upgrade`, and start the services.

**Discovery — RDO 2025.1 ships no linuxbridge agent; switched to OVS (decision #24
amended).** The planned `dnf install … openstack-neutron-linuxbridge` failed with `Unable
to find a match`. `dnf list available 'openstack-neutron*'` showed the Epoxy set ships only
OVS (`openstack-neutron-openvswitch`), OVN (`-ovn-agent`/`-ovn-metadata-agent`), `macvtap`,
and `sriov` agents — **no linuxbridge**; `dnf provides '*/neutron-linuxbridge-agent'`
matched only a path *inside the `openstack-kolla` container-image package*, not an
installable RPM. Linuxbridge has been deprecated for years and RDO has dropped the packaged
agent. Chose **OVS** over OVN as the minimal pivot that preserves the VXLAN self-service
model (#14) and the agent-based plan — only the L2 agent and its config change
(`openvswitch_agent.ini` instead of `linuxbridge_agent.ini`, plus an OVS provider bridge
for the flat external net). OVN rejected for Phase 2 as too large a by-hand rewrite (R12);
it is the Phase 3 Kolla backend. **Lesson:** verify a deprecated driver is still *packaged*
in the target release before planning a manual install around it. (`ebtables`/`ipset` were
already satisfied — on EL9 `ebtables` is provided by the installed `iptables-nft`.)

## Problems hit and fixes

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

2. **nova-scheduler/nova-conductor crashed with "placement service ... does not have any
   supported versions" — the placement Apache vhost was missing its access grant.** First
   real use of Placement (another Phase-1-installed-but-never-exercised service): both
   services logged that the Placement endpoint existed but exposed no supported
   microversions. `curl http://controller.lab.internal:8778/` returned the **AlmaLinux
   default Apache test page with a 403**, not a placement JSON payload — so Apache wasn't
   routing `/` to the placement app at all. Cause: `/etc/httpd/conf.d/00-placement-api.conf`
   shipped *without* the `<Directory>` / `<Files placement-api>` `Require all granted`
   access block — a known placement-on-EL packaging gap. **Fix:** added the grant block,
   `httpd -t`, `systemctl reload httpd`; placement then answered with its version document
   and the Nova services cleared the check. **Lesson:** a placement "no supported versions"
   error is usually an Apache routing/permission problem, not a placement-service one —
   `curl` the endpoint and look at *what* actually answers.

3. **RabbitMQ down, then crashing nova on connect — two stacked faults: a boot-ordering
   race, and an unsupported RabbitMQ/Erlang pairing that EPEL had silently introduced.**
   RabbitMQ was the third Phase-1 service exercised for the first time by Nova. Three
   parts:
   - **(a) Dead after every reboot — `epmd` bound before the LAN was up.** `rabbitmq-server`
     failed at boot with `epmd error for host controller: address` (EADDRNOTAVAIL): the
     Erlang port mapper tries to bind `rabbit@controller` to `192.168.1.130` before
     NetworkManager has finished bringing the interface up. **Fix:** `systemctl enable
     NetworkManager-wait-online.service` plus a `systemctl edit rabbitmq-server` drop-in
     adding `After=network-online.target` / `Wants=network-online.target`. The drop-in
     lives in `/etc/systemd/system/`, so it survived the package reinstall in (c).
   - **(b) Service up, but nova connections were accepted, authenticated, then killed.**
     The client saw `Server unexpectedly closed connection` / `Connection reset by peer`;
     the rabbit log showed the reader crashing with
     `{unexpected_message,{'EXIT',#Port,einval}}`. A minimal Python `amqp` loopback test
     failed identically on **both** `127.0.0.1` and `.130`, ruling out the network path.
     **Root cause:** RabbitMQ **3.9.21** was running on **Erlang/OTP 26.2.5**, an
     unsupported pairing — rabbit 3.9 tops out at Erlang 24, and Erlang 26 needs rabbit
     ≥ 3.12 (per the official compatibility matrix).
   - **(c) Why Erlang 26 was present, and the fix.** RDO pulls RabbitMQ from the CentOS
     Messaging SIG repo (`centos-rabbitmq-38`), which *ships a matched Erlang 24*
     (`24.1.7`, `24.3.4.2`) — but **EPEL also ships Erlang `26.2.5`, and dnf picked it on
     version number alone**, quietly installing an incompatible Erlang under rabbit 3.9.
     Two escape routes were ruled out first: removing `centos-release-rabbitmq-38` to take
     the rabbit-4 track **cascades to remove `centos-release-openstack-epoxy`** (the whole
     RDO 2025.1 repo set) and was aborted; installing `centos-release-rabbitmq-4`
     *alongside* `-38` fails on a file conflict (both own
     `/etc/yum.repos.d/CentOS-Messaging-rabbitmq.repo`). **Fix (clean, RDO-native —
     decision #33):** reinstall with EPEL out of the transaction so the SIG's Erlang 24
     wins — `sudo dnf install --disablerepo=epel rabbitmq-server` (pulled
     `rabbitmq-server 3.9.21` + `erlang 24.3.4.2`, both from `centos-rabbitmq-38`) — then
     **pin it durably** with `sudo dnf config-manager --setopt=epel.excludepkgs=erlang*
     --save` so a future `dnf update` can't drag Erlang 26 back in. Recreated the
     `openstack` vhost user (`add_user` + `set_permissions -p / openstack '.*' '.*' '.*'`);
     the loopback `amqp` test then printed `OK`, and restarting nova-scheduler/-conductor
     brought both `up`. **Lesson:** on EL, **EPEL can outrank a CentOS SIG package by
     version number** and quietly install something the SIG stack can't use — when an RDO
     component depends on a SIG-pinned version, exclude the conflicting package from EPEL
     (`excludepkgs=`). Same EPEL-vs-SIG hazard RDO's own guidance warns about.
