# Phase 2 · Stage 6 — Cinder (block storage), RBD-backed

> Part of **[Phase 2](project-phase-2.md)**. **Status: planned** (not yet started).

## Planned steps

6. **Stage 6 — Cinder (block storage), RBD-backed** — add persistent volumes once a VM
   boots. Controller-side and largely a repeat of the Phase 1 Glance pattern, so done
   **by hand** (not a role): create the `volumes` Ceph pool + `client.cinder` auth/keyring;
   the `cinder` DB; the service account (ensure the `service` project exists → user create
   → `role add --project service` → **verify with `role assignment list`** — the Phase 1
   issue #5 lesson); install `cinder-api`/`cinder-scheduler`/`cinder-volume` on the
   controller; configure `cinder.conf` with an `[rbd]` backend (`rbd_pool = volumes`,
   `rbd_user = cinder`, `rbd_ceph_conf`, and `rbd_secret_uuid` = the libvirt secret) and
   register the **block-storage v3** endpoints. The compute side needs only the libvirt
   Ceph secret already placed in Stage 4 (decision #31). Test: `openstack volume create`,
   confirm the UUID in `rbd -p volumes ls`, then `openstack server add volume` to attach
   it to the Stage 5 instance and verify the block device appears inside the guest. When
   that works, **Phase 2 is done.** (Cinder is optional on a throwaway cluster — included
   here for block-storage learning and volume-I/O benchmarking; see [decisions.md](decisions.md) #32.)

## Actual work completed

_Not yet started._
