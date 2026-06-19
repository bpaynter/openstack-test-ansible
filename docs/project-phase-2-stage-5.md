# Phase 2 · Stage 5 — Bootstrap the OpenStack Objects + Test

> Part of **[Phase 2](project-phase-2.md)**. **Status: in progress** — all OpenStack objects
> created; a CirrOS VM boots and is reachable on the overlay (DHCP + metadata working).
> Remaining: attach the controller NIC to `br-provider` (connectivity-sensitive) + floating-IP
> external SSH.

## Planned steps

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

## Actual work completed

### Networking parameters settled (2026-06-19)

The three open Stage-5 networking choices are decided and recorded as
[decision #39](decisions.md):

| Item | Value |
|---|---|
| Tenant network | VXLAN, subnet `10.0.0.0/24`, **MTU 1450** |
| Provider/external network | **flat** on physnet `provider`, subnet `192.168.1.0/24`, **DHCP off**, gateway `192.168.1.1` |
| Floating-IP pool | `192.168.1.160 – .191` (a `/27`-sized allocation pool on the provider `/24` — 32 usable floating IPs) |

The floating-IP pool is a *restricting* **allocation pool** on the `/24` provider subnet, not
a separate `/27` subnet: keeping the subnet `/24` leaves the home router as the gateway and
makes `.160`/`.191` ordinary host addresses (all 32 usable). Confirmed clear of the live
router's DHCP range (`.10–.49`), its static IPs (`.199–.225`), and the cluster host IPs
(`.130–.133`). The CirrOS image is already in Glance (`qcow2`, `active`, RBD-backed in the
`images` pool), so no image upload is needed.

### Bootstrap harness + provider network (2026-06-19)

Stage 5 is **API-driven** Ansible via the `openstack.cloud` collection (bundled in the uv
Ansible as `openstack.cloud 2.5.0`) — a different style from the file-driven Stages 2–4.

- **Auth:** a `clouds.yaml` at `~/.config/openstack/clouds.yaml` (outside the repo, so the
  admin password never enters git), cloud name `lab`, transcribed field-by-field from
  `~/admin-openrc` (incl. `image_api_version: 2`). Verified with
  `openstack --os-cloud lab token issue`. Every bootstrap task passes `cloud: lab`.
- **Playbook:** `ansible/bootstrap.yml` — `hosts: localhost`, `connection: local`,
  `gather_facts: false`; kept **separate from `site.yml`** (the API bootstrap is on-demand,
  not part of the idempotent config-management run). No `become`/`-K`, and no vault (the
  localhost play touches no `compute` group_vars).
- **First object — provider/external network:** `openstack.cloud.network` with
  `external: true`, `provider_network_type: flat`, `provider_physical_network: provider`
  (ties to ml2 `flat_networks = provider` and the controller's
  `bridge_mappings = provider:br-provider`). Verified: `network show provider` → `flat` /
  physnet `provider` / `router:external External` / `ACTIVE` / mtu 1500. **No host-NIC
  change yet** — `br-provider` is still empty and `.130` stays on the NIC; this is a pure
  logical object.

#### Problems hit and fixes

1. **`openstack.cloud` modules need `openstacksdk` in the *uv tool-env* interpreter.** They
   run under the interpreter Ansible discovers for `localhost` — the uv tool-env Python
   (`~/.local/share/uv/tools/ansible/bin/python`), **not** the system Python. The system had
   `openstacksdk` (the CLI uses it) but the uv env did not →
   `ModuleNotFoundError: No module named 'openstack'`. **Fix:** add it to the tool env with
   `uv tool install … --with openstacksdk` (decision #27). *Diagnostic note:* `uv run python`
   tests a different (ephemeral) env — verify against `…/tools/ansible/bin/python` directly.
2. **Unpinned `openstacksdk` (4.16.0) is too new for `openstack.cloud 2.5.0`.** Every module
   then failed with `module 'openstack' has no attribute 'version'` — 4.16.0 removed the
   deprecated `openstack.version` accessor the collection still calls. **Fix:** pin
   `openstacksdk==4.4.0` (the RDO Epoxy-matched version already proven against this cloud by
   the system CLI). See decision #27.

### Network topology — provider / tenant / router (2026-06-19)

The full self-service topology is built (all tasks in `ansible/bootstrap.yml`, all idempotent):

| Object | Type | Key attributes |
|---|---|---|
| `provider` / `provider-subnet` | flat external | `192.168.1.0/24`, **DHCP off**, gw `192.168.1.1`, allocation pool `.160–.191` (decision #39) |
| `tenant-net` / `tenant-subnet` | self-service VXLAN | auto VNI 60, **MTU 1450**, `10.0.0.0/24`, **DHCP on**, gw `10.0.0.1`, DNS `1.1.1.1`/`8.8.8.8` |
| `router1` | Neutron router | external gw on `provider` (SNAT on, gw port `192.168.1.191`), internal interface on `tenant-subnet` (`10.0.0.1`) |

`tenant-net` is created **self-service** (no `provider_*` attributes), so Neutron allocates the
VXLAN VNI from `vni_ranges = 1:1000`; the provider net pins `flat`/physnet `provider` because
it maps to real hardware (`bridge_mappings = provider:br-provider`). The router's gateway port
consumed `.191` from the floating pool (31 floating IPs remain). **No host-NIC change yet** —
`br-provider` stays empty, so the router's external port and any floating IPs are valid objects
but not yet *reachable*; the connectivity-sensitive NIC attach is still pending. Internal
routing (VM ↔ `10.0.0.1` ↔ DHCP) is live.

### First VM (`cirros1`) + the overlay debugging saga (2026-06-19)

A CirrOS instance now boots on `tenant-net` and is fully functional on the overlay:
`10.0.0.181` **leased via DHCP**, default route via the router (`10.0.0.1`), and the
**metadata service reachable** (`ec2` datasource → `instance-id i-00000003`,
`local-hostname cirros1.novalocal`). This proves the compute plane + VXLAN overlay + DHCP +
metadata end-to-end — all east-west, sealed inside the overlay, with **no host-NIC change**.

**VM prerequisites** (in `bootstrap.yml`): `m1.tiny` flavor (1 vCPU / 512 MB / 1 GB),
`lab-key` keypair, and `lab-ssh-icmp` security group (ingress SSH + ICMP; egress open by
default). Gotcha: `openstack.cloud.keypair`'s `public_key_file` does **not** expand `~` — use
an absolute path. The instance itself is booted via the **CLI**, not `openstack.cloud.server`
(problem 1).

#### Problems hit and fixes

1. **`openstack.cloud.server` (2.5.0) is incompatible with `openstacksdk 4.4.0`** — fails with
   `'Image' object has no attribute 'owner_seen'`. A version squeeze: 4.16.0 breaks every module
   (`openstack.version`), 4.4.0 fixes those but breaks the *server* module; the infra modules are
   all fine on 4.4.0. **Fix:** boot the (transient, test) VM with `openstack server create` — same
   proven SDK, different code path, and what the plan called for anyway. **Not a dealbreaker for
   Ansible-driven VM booting:** a `command:`-wrapped CLI call always works, and the declarative
   module can be revived later by finding the openstacksdk version 2.5.0 wants (a mid-4.x with
   `owner_seen` but pre-4.16) or bumping the collection. Deferred as a side quest.
2. **VM won't build — `domain configuration does not support video model 'virtio'`.** Nova's
   2025.1 default video model is `virtio`, but EL9's **modular qemu** splits display devices into
   subpackages and the computes have only std VGA (in `qemu-kvm-core`), not `virtio-gpu`. **Fix
   (immediate, per-image):** `openstack image set cirros --property hw_video_model=vga`.
   **Resolved cluster-wide (decision #41):** added `qemu-kvm-device-display-virtio-gpu` to the
   `nova_compute` role and re-applied across the computes, so nova's `virtio` default now works
   for *any* image; the per-image `vga` property is now redundant but harmless. Same modular-qemu
   family as the Stage 4 modular-libvirt socket issue.
3. **No VXLAN tunnels → DHCP never reaches the VM.** Both `br-tun` bridges had **zero** `vxlan-*`
   ports, so the VM's `DHCPDISCOVER` on compute2 had no path to the DHCP agent on the controller
   (the VM fell back to IPv4LL). **Root cause:** the agents run `l2_population = true` (they wait
   for the L2pop mechanism driver to push remote-VTEP info and build tunnels on demand), but the
   controller's `ml2_conf.ini` had `mechanism_drivers = openvswitch` — **missing the `l2population`
   driver** that does the pushing. The agent half was present everywhere; the **server half was
   never enabled**. **Fix (controller-only):** `mechanism_drivers = openvswitch,l2population`, then
   restart `neutron-server` + all OVS agents so they resync and build the mesh (verified
   `vxlan-c0a80184` controller→compute2, `vxlan-c0a80182` compute2→controller). `mechanism_drivers`
   is an ML2/`neutron-server` setting — it lives **only** on the controller (computes run only the
   OVS agent, which reads `neutron.conf`/`openvswitch_agent.ini`, never `ml2_conf.ini`). Stage 3
   config record corrected.
4. **DHCP agent can't spawn `dnsmasq` — SELinux `dac_override` denial (decision #40).** With
   tunnels up, the VM still got no lease: the agent built the `qdhcp` namespace, tap, and IPs but
   **no `dnsmasq` ran** (`cannot open or create lease file … Permission denied`). `ausearch` showed
   `avc: denied { dac_override } … comm="dnsmasq" … dnsmasq_t`: `dnsmasq` runs as root and needs
   `CAP_DAC_OVERRIDE` to write the `neutron:neutron`-owned `0644` lease file, but the `dnsmasq_t`
   domain isn't granted it (labels/ownership were all correct — not a relabel/chown issue). Same
   *capability* as #34 but a different *domain* (`dnsmasq_t`, not `neutron_t`), so the
   `os_neutron_dac_override` boolean didn't cover it. **Fix:** `openstack-selinux` ships a sibling
   boolean — `setsebool -P os_dnsmasq_dac_override on` (decision #40) — the vendor-intended fix,
   same philosophy as #34. `dnsmasq` then listens on `:67`/`:53` and the VM leases `10.0.0.181`.

_Internal overlay proven. Next: attach the controller NIC to `br-provider` (connectivity-sensitive)
+ assign a floating IP for external SSH._

---

## Changelog

| Date | Change |
|---|---|
| 2026-06-19 | Stage 5 started. Settled the three networking parameters (tenant `10.0.0.0/24` VXLAN @ MTU 1450; provider flat on `192.168.1.0/24`, no DHCP, gw `.1`; floating-IP pool `192.168.1.160–.191`) and recorded them as [decisions.md](decisions.md) #39; noted CirrOS already present in Glance. |
| 2026-06-19 | Stood up the API bootstrap harness (`clouds.yaml` cloud `lab`; `ansible/bootstrap.yml` on `localhost`) and created the **provider/external network** (flat, physnet `provider`, `router:external`, `ACTIVE`). Logged two `openstacksdk` gotchas (must live in the uv tool env; pin `==4.4.0` because 4.16.0 drops `openstack.version`) — folded into the corrected install procedure in [decisions.md](decisions.md) #27. |
| 2026-06-19 | Completed the network topology: `provider-subnet` (`.160–.191` pool, DHCP off), `tenant-net`/`tenant-subnet` (self-service VXLAN VNI 60, MTU 1450, `10.0.0.0/24`, DHCP on), and `router1` (external gw on `provider`, SNAT, internal interface on `10.0.0.1`). All idempotent; no host-NIC change yet. |
| 2026-06-19 | Added the VM prerequisites (`m1.tiny`, `lab-key`, `lab-ssh-icmp`) and booted **`cirros1`** (via CLI). Debugged the overlay end-to-end: (1) `openstack.cloud.server` 2.5.0 vs openstacksdk 4.4.0 `owner_seen` → boot via CLI; (2) `hw_video_model=virtio` unsupported on EL9 modular qemu → per-image `vga`; (3) **no VXLAN tunnels** — `l2population` missing from `mechanism_drivers` → added it (server half of l2pop); (4) **`dnsmasq` SELinux `dac_override`** → `os_dnsmasq_dac_override` boolean ([decisions.md](decisions.md) #40). VM now leases `10.0.0.181` and reaches metadata. Corrected the Stage 3 `mechanism_drivers` record. Fixed earlier Stage 5 log dates (all this session = 06-19). |
| 2026-06-19 | Resolved the video-model fix **cluster-wide** ([decisions.md](decisions.md) #41): `qemu-kvm-device-display-virtio-gpu` added to the `nova_compute` role and applied to all computes, so nova's `virtio` default works for any image (the per-image `vga` is now redundant). |
