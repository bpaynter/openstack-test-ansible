# Project Plan

This document describes the project outline: goals, the 2-phase progression,
current status, and the decision log.

For hardware, RAM, disk, and networking details, see
[`inventory.md`](inventory.md).

---

## 1. Project context

A **temporary** 4-node OpenStack + Ceph cluster built from retired Dell
OptiPlex desktops. Goal is **learning**: stand it up, run benchmarks, tear it
down after a few days. The build follows a 2-phase progression (manual →
hand-rolled Ansible) so each phase is motivated by the friction of the
previous one. Complexity is introduced deliberately, not optimized for speed.

**Stack:**
- OS: AlmaLinux 9 on all four nodes
- OpenStack release: 2025.1
- Ceph: Squid 19.2.x via `cephadm`
- Neutron mechanism driver: Linux bridge
- Tenant networking: VXLAN self-service, with a Neutron router NATing to a
  flat provider/external network and floating IPs for external reach.

## 2. The 2-phase plan

The cluster is built **twice**, the second phase motivated by the friction of
the first. This is the explicit learning goal — it is not the fastest path to
a running cluster, and that is intentional.

### Phase 1 — Manual, controller only *(COMPLETE)*

Built the storage and control plane by hand to learn what the services *are*.

- Ceph stood up with **`cephadm`**: bootstrapped on the controller, OSD hosts
  and OSDs added afterwards. Containerized Ceph managed by the orchestrator,
  still a hands-on step-by-step build.
- On the controller, a minimal **OpenStack 2025.1** control plane installed
  manually: **Keystone** (Fernet tokens), **Glance** (Ceph RBD backend),
  **Placement** — following the OpenStack 2025.1 install guide step by step.
- Outcome: understand Keystone tokens, Glance→Ceph RBD integration, why
  Placement exists.

Final Phase 1 state at handoff:
- Ceph: 5 OSDs across 3 hosts, HEALTH_OK, `images` RBD pool initialized.
- OpenStack: Keystone, Glance (Ceph RBD-backed), and Placement up on the
  controller; `openstack token issue`, `openstack image list`, and
  `rbd -p images ls` all verified.

### Phase 2 — Compute plane via hand-rolled Ansible *(active)*

Add the compute plane — Nova and Neutron — to the existing cluster using
**hand-rolled Ansible playbooks**. There is **no teardown** and **no
Kolla-Ansible**. The controller keeps its Phase 1 services; Phase 2 adds to
it.

Adding Nova-compute + Neutron agents to the three compute nodes is the *same
steps three times*. That repetition is the natural seam for Ansible — and
since the manual steps are already known from Phase 1, Phase 2 is
"translate known work into idempotent playbooks," i.e. learning Ansible
without simultaneously learning OpenStack.

Phase 2 scope:
- Controller-side **Nova** (API, scheduler, conductor, novncproxy) —
  one-time, manual.
- Controller-side **Neutron** server + ml2/linuxbridge, plus the
  **network node** agents (L3, DHCP, metadata) — one-time, on the controller.
- A `nova_compute` Ansible role applied across the `compute` group.
- A `neutron_compute` Ansible role applied across the `compute` group.
- VXLAN self-service networking: tenant networks over VXLAN, a Neutron
  router NATing to a flat provider/external network, floating IPs.
- Bootstrap of the provider network, tenant network, router, flavors,
  keypair, security groups; then an end-to-end VM launch test.

## 3. Phase 2 staging

Phase 2 is being done in stages so that **Ansible itself is learned before it
is pointed at Nova/Neutron**:

- **Stage 0** — establish the Ansible control node. *(complete)*
- **Stage 1** — build and verify the cluster inventory. *(complete)*
- **Stage 2** — build a trivial throwaway role to learn role structure.
  *(next)*
- **Stage 3** — controller-side Nova + Neutron, done manually (one-time work).
- **Stage 4** — the `nova_compute` and `neutron_compute` roles across the
  compute group.
- **Stage 5** — bootstrap the OpenStack network objects (provider network,
  tenant network, router, floating-IP pool) and an end-to-end VM launch test.

### What's in the repo today (Stages 0–1)

- **Control node:** the controller (7071). Ansible installed via `uv` against
  Python 3.12, giving `ansible` community 13.7 / `ansible-core` 2.20 (all
  docs references should match version 13). The full `ansible` community
  package is used so `openstack.cloud` is available in Stage 5.
- **Escalation:** Ansible runs as the normal login user. `sudo` is left
  password-protected (deliberate); escalation uses `-K` per invocation rather
  than `become_ask_pass = True` in the config, so the prompt appears only on
  runs that actually escalate.
- **`ansible.cfg`:** project-local. Sets `inventory`, `remote_user`,
  `stdout_callback = yaml`, `callbacks_enabled = profile_tasks`,
  `interpreter_python = auto_silent`. `become` is **default-OFF** so that any
  task with no `become:` line runs unprivileged.
- **`inventory.yml`:** YAML inventory with `controller` and `compute` groups.
  Host range syntax is colon-delimited (`compute[1:3].lab.internal`).
- **`group_vars/all.yml`:** non-secret cluster-wide facts.
- **`host_vars/`:** per-host values. So far just `local_ip`, each compute
  node's own `192.168.1.x` VXLAN tunnel endpoint — varies per host and so
  cannot come from a group var.
- Service passwords are deferred to an `ansible-vault`-encrypted file in
  Stage 4; nothing sensitive is in plaintext `group_vars`.

## 4. Open items for later stages

- **Stage 4 ml2/VXLAN config:** `type_drivers`,
  `tenant_network_types = vxlan`, `vni_ranges`, and the per-host `local_ip`
  tunnel endpoint variable.
- **MTU:** VXLAN adds ~50 bytes of header. Either raise the underlay MTU or
  set the tenant network MTU to 1450 to avoid the classic "SSH connects then
  hangs" fragmentation symptom.
- **Floating-IP pool:** to be carved from `192.168.1.0/24`, outside the home
  router's DHCP range and outside the four static host IPs (`.130–.133`).
  Settle the exact range against the router's actual DHCP pool early in
  Stage 5.
- **Tenant subnet CIDR** (e.g. `10.0.0.0/24`).
- **Nova ephemeral disk backend:** local qcow2 vs. Ceph RBD `vms` pool.
- **`kvm` vs `qemu`:** all four boxes are VT-x i7s, so `kvm`, but BIOS
  virtualization must be confirmed enabled on each.

## 5. Guiding principles

- **Learning-first sequencing.** Complexity is introduced deliberately and
  motivated by the friction of the previous phase, not optimized for speed.
- **Hand-rolled before automated.** Phase 2 uses hand-rolled Ansible rather
  than Kolla so the work builds genuine understanding of what each service
  requires before abstractions are layered on.
- **Document as you go.** A canonical build plan tracks hardware decisions,
  rationale, the decision log, and the implementation log including problems
  hit and their fixes.
- **Clean chat per phase / stage.** Start a new chat for each implementation
  stage rather than carrying forward long context.

## 6. Decision log

| Decision | Choice | Reason |
|---|---|---|
| Number of machines | 4 | Matches 4 available 1G ports; restores 3-host Ceph |
| Machine retired | 5080 (dead PSU) | PSU failed, no compatible replacement; becomes donor |
| 5080's replacement | 7050 (i7-7700) | Only remaining machine; weakest CPU but viable as OSD host |
| Controller | 7071 | 8 cores, tower chassis, 32GB + NVMe boot; also network node |
| OS | AlmaLinux 9 | All four nodes |
| OpenStack release | 2025.1 | Target release for both phases |
| Ceph deployment (Phase 1) | `cephadm` | Containerized, orchestrator-managed, still hands-on |
| Ceph release | Squid 19.2.x | Minor skew from RDO 2025.1's validated Reef — accepted for a short-lived cluster |
| RAM split | 32 / 16 / 16 / 16 | Controller is most service-dense; uses all 10 sticks |
| SATA capacity (7060/7050) | 3 SSDs total each | Inclusive of boot disk → 2 OSDs each |
| Ceph OSDs | 5 across 3 hosts (2+1+2) | Minimum for 3× replication, `host` failure domain |
| Harvested NVMe | 7071 boot disk | Controller benefits most from low root-disk latency |
| OSD pool | All matched 250GB SATA | Uniform pool = clean benchmark numbers |
| 2nd SSD via 110V→SATA adapters | No | Frankenstein power risk not justified for a test cluster |
| Hyperthreading | Enabled on compute nodes | More logical CPUs for a RAM-constrained cluster; accept variance for CPU benchmarks |
| Network speed | 1G flat underlay, static host IPs | 10/100 too slow for Ceph |
| Tenant networking | VXLAN self-service | Isolates VM DHCP from home DHCP with no managed switch |
| Flat provider networking for VMs | No | Dual-DHCP race with the home router |
| VLAN-based isolation | No | Would solve dual-DHCP but needs a managed switch not in play |
| Mechanism driver | Linux bridge | Fewer moving parts to debug than OVS |
| Phases | 2 (manual → hand-rolled Ansible) | Kolla-Ansible phase dropped |
| Phase 2 scope | Add compute nodes via hand-rolled Ansible | No teardown; add Nova/Neutron to the existing cluster |
| Cluster lifespan | Temporary (days) | Build, benchmark, tear down |

## 7. Where to start

If you're picking up this project fresh, the active work is **Phase 2,
Stage 2**: building a trivial throwaway Ansible role (a `common` role that
renders an identical `/etc/hosts` to all four nodes) to learn role structure —
the `ansible-galaxy role init` skeleton, the `template` module and Jinja2
`.j2` files, the `handlers`/`notify` pattern, wiring into `site.yml`, and
proving idempotence. Nova and Neutron are not touched until Stages 3–4.
