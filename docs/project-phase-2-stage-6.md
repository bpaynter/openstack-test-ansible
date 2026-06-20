# Phase 2 · Stage 6 — Cinder (block storage), RBD-backed

> Part of **[Phase 2](project-phase-2.md)**. **Status: in progress** (started 2026-06-20).

## Auth model — reuse `client.nova` (decision #38), *not* a separate `client.cinder`

This stage's original prose called for a separate `client.cinder` cephx user with
`rbd_user = cinder`. That predates **decision #38** (settled in Stage 4), which commits to a
**single shared libvirt secret** on the computes (holding the `client.nova` key) that
*"is reused unchanged by Stage 6 Cinder; only its Ceph caps get extended to the `volumes`
pool."* The two conflicted; resolved **2026-06-20** in favour of decision #38 (honour the
later, more-specific commitment; zero compute-side change on a throwaway cluster).

Concretely this means:

- **No new cephx user and no compute-side change.** Extend `client.nova`'s caps to the
  `volumes` pool (it already has `rbd` on `vms` + `rbd-read-only` on `images`); Cinder
  attaches ride the libvirt secret already placed on every compute in Stage 4.
- `cinder.conf` `[rbd]` backend uses **`rbd_user = nova`** (the username must match the key
  in the compute libvirt secret) and **`rbd_secret_uuid` = the existing shared UUID** in
  `group_vars/all.yml`.
- `cinder-volume` on the controller reaches Ceph with a `ceph.client.nova.keyring`
  (`root:cinder`, `0640` — the Phase 1 issue #3 permissions lesson).

The textbook separate-`client.cinder` pattern (cleaner identity separation, what Phase 3
Kolla deploys) was the alternative; deferred to Phase 3.

## Planned steps

6. **Stage 6 — Cinder (block storage), RBD-backed** — add persistent volumes once a VM
   boots. Controller-side and largely a repeat of the Phase 1 Glance pattern, so done
   **by hand** (not a role):
   1. **Ceph** — create the `volumes` pool (`ceph osd pool create` → `application enable rbd`
      → `rbd pool init`); **extend `client.nova`'s caps** to add `profile rbd pool=volumes`
      (osd + mgr); place `ceph.client.nova.keyring` on the controller (`root:cinder`, `0640`).
   2. **Database** — create the `cinder` DB + user grants (`sudo mysql`).
   3. **Keystone service account** — ensure the `service` project exists → `user create cinder`
      → `role add --project service --user cinder admin` → **verify with `role assignment
      list --user cinder --names`** (the Phase 1 issue #5 lesson) → register the
      **block-storage v3** service + endpoints (`volumev3`, `http://controller:8776/v3/%(project_id)s`).
   4. **Install + configure** — `openstack-cinder` on the controller (`cinder-api` +
      `cinder-scheduler` + `cinder-volume`); `cinder.conf` with `[database]`,
      `[keystone_authtoken]`, `[DEFAULT] transport_url`/`auth_strategy`/`enabled_backends = ceph`,
      and a `[ceph]` `[rbd]` backend (`volume_driver = cinder.volume.drivers.rbd.RBDDriver`,
      `rbd_pool = volumes`, `rbd_user = nova`, `rbd_ceph_conf = /etc/ceph/ceph.conf`,
      `rbd_secret_uuid` = the shared libvirt secret UUID). Wire Cinder into the catalog for
      Nova (`nova.conf [cinder]`) so the controller's nova-api can talk to it.
   5. **Migrate + start** — `cinder-manage db sync`; enable/start the three services; verify
      `openstack volume service list` shows `cinder-scheduler` + `cinder-volume@ceph` `up`.
   6. **Test** — `openstack volume create`, confirm the UUID appears in `rbd -p volumes ls`,
      then `openstack server add volume` to attach it to the Stage 5 instance and verify the
      block device appears inside the guest. When that works, **Phase 2 is done.**

   (Cinder is optional on a throwaway cluster — included here for block-storage learning and
   volume-I/O benchmarking; see [decisions.md](decisions.md) #32.)

## Actual work completed

_In progress — started 2026-06-20. Auth-model contradiction (separate `client.cinder` vs.
reuse `client.nova`) resolved in favour of decision #38; see the Auth model note above._
