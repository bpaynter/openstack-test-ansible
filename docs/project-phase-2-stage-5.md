# Phase 2 · Stage 5 — Bootstrap the OpenStack Objects + Test

> Part of **[Phase 2](project-phase-2.md)**. **Status: in progress** — the three networking
> parameters are settled ([decisions.md](decisions.md) #39); object creation is next.

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

### Networking parameters settled (2026-06-18)

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

### Bootstrap harness + provider network (2026-06-18)

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

_Provider subnet + tenant network/subnet + router not yet created._

---

## Changelog

| Date | Change |
|---|---|
| 2026-06-18 | Stage 5 started. Settled the three networking parameters (tenant `10.0.0.0/24` VXLAN @ MTU 1450; provider flat on `192.168.1.0/24`, no DHCP, gw `.1`; floating-IP pool `192.168.1.160–.191`) and recorded them as [decisions.md](decisions.md) #39; noted CirrOS already present in Glance. |
| 2026-06-18 | Stood up the API bootstrap harness (`clouds.yaml` cloud `lab`; `ansible/bootstrap.yml` on `localhost`) and created the **provider/external network** (flat, physnet `provider`, `router:external`, `ACTIVE`). Logged two `openstacksdk` gotchas (must live in the uv tool env; pin `==4.4.0` because 4.16.0 drops `openstack.version`) — folded into the corrected install procedure in [decisions.md](decisions.md) #27. |
