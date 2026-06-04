# openstack-test-ansible

Ansible playbooks for a temporary 4-node OpenStack + Ceph learning cluster
built on retired Dell OptiPlex desktops. The goal is learning: stand it up,
run benchmarks, tear it down after a few days.

The cluster is built in two phases. **Phase 1** (manual install of Ceph,
Keystone, Glance, and Placement on the controller) is complete. **Phase 2**
— hand-rolled Ansible playbooks adding Nova and Neutron to the compute nodes
— is the active work, and is what this repo holds.

**Stack:** AlmaLinux 9, OpenStack 2025.1, Ceph Squid 19.2.x via `cephadm`,
Linux bridge mechanism driver, VXLAN self-service tenant networking.

**Hosts:** one controller + three compute/OSD nodes on a flat 1G underlay
(`192.168.1.130–133`).

## Documentation

- [`docs/overall_plan.md`](docs/overall_plan.md) — project outline, the 2-phase
  progression, current status, and decision log.
- [`docs/inventory.md`](docs/inventory.md) — hardware, RAM, disk layout, and
  networking details.
