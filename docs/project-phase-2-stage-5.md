# Phase 2 · Stage 5 — Bootstrap the OpenStack Objects + Test

> Part of **[Phase 2](project-phase-2.md)**. **Status: planned** (not yet started).

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

_Not yet started._
