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

_Object creation not yet started._

---

## Changelog

| Date | Change |
|---|---|
| 2026-06-18 | Stage 5 started. Settled the three networking parameters (tenant `10.0.0.0/24` VXLAN @ MTU 1450; provider flat on `192.168.1.0/24`, no DHCP, gw `.1`; floating-IP pool `192.168.1.160–.191`) and recorded them as [decisions.md](decisions.md) #39; noted CirrOS already present in Glance. |
