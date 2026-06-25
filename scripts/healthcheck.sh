#!/usr/bin/env bash
#
# healthcheck.sh — read-only smoke test for the OpenStack + Ceph control plane.
#
# Run ON THE CONTROLLER (it is the only node with the services, admin-openrc, and
# the cephadm _admin keyring). Tests bottom-up everything stood up through Phase 2
# Stage 5, so each layer's check also exercises the ones beneath it:
#
#   1. systemd units      6. Glance (image)        10. Stage 5 objects
#   2. Ceph               7. Placement                 (networks / router /
#   3. Databases          8. Nova (compute)            VXLAN overlay / VM)
#   4. RabbitMQ           9. Neutron (network)
#   5. Keystone (identity)
#
# Section 11 (recent SSH auth failures) is a security-hygiene add-on, not part of
# the bottom-up control-plane stack; it WARNs on repeated failures but never FAILs.
#
# NON-DESTRUCTIVE: it only lists/reads — it never creates an image, network, etc.
#
# Usage:
#   source ~/admin-openrc          # or:  OPENRC=/path/to/openrc ./scripts/healthcheck.sh
#   ./scripts/healthcheck.sh
#
#   - Run as your normal login user (NOT root) so the `openstack` CLI uses your
#     admin creds. Root-only checks (Ceph, MariaDB, RabbitMQ, nova-manage, the
#     SSH auth log) use `sudo` and will prompt once; without sudo they are
#     skipped (WARN).
#   - The compute plane is up (Stage 4): 3 nova-compute services up, 3
#     hypervisors, all compute hosts mapped into a cell, and an Open vSwitch
#     agent on the controller + each compute. Override the count with
#     EXPECTED_COMPUTES=N.
#   - Stage 5 objects are now ASSERTED (section 10): the flat provider/external
#     network, the self-service VXLAN tenant-net (MTU 1450), router1 with an
#     external gateway, and the VXLAN tunnel mesh on br-tun (the l2population
#     fix). The CirrOS test VM is informational (transient). External floating-IP
#     reachability is added once the controller NIC is attached to br-provider.
#   - Capstone test: reboot the controller, then re-run this. It proves the
#     RabbitMQ/memcached/glance boot-ordering + SELinux fixes hold on a cold start.
#
# Exit code: 0 if no FAILs, 1 otherwise. WARNs (e.g. Ceph HEALTH_WARN) do not fail.

set -uo pipefail

CONTROLLER_FQDN="${CONTROLLER_FQDN:-controller.lab.internal}"
OPENRC="${OPENRC:-$HOME/admin-openrc}"
EXPECTED_COMPUTES="${EXPECTED_COMPUTES:-3}"   # nova-compute / hypervisor / cell-host count

# ---- pretty output ----------------------------------------------------------
if [[ -t 1 ]]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[36m'; DIM=$'\e[2m'; N=$'\e[0m'
else
  R=; G=; Y=; B=; DIM=; N=
fi
pass=0; fail=0; warn=0

hdr() { printf '\n%s== %s ==%s\n' "$B" "$1" "$N"; }
ok()  { printf '  %sPASS%s %s\n' "$G" "$N" "$1"; pass=$((pass+1)); }
no()  { printf '  %sFAIL%s %s\n' "$R" "$N" "$1"; fail=$((fail+1)); [[ -n "${2:-}" ]] && printf '       %s%s%s\n' "$DIM" "${2}" "$N"; return 0; }
wn()  { printf '  %sWARN%s %s\n' "$Y" "$N" "$1"; warn=$((warn+1)); [[ -n "${2:-}" ]] && printf '       %s%s%s\n' "$DIM" "${2}" "$N"; return 0; }
nfo() { printf '  %sINFO%s %s\n' "$B" "$N" "$1"; }

# PASS if cmd exits 0, else FAIL (showing the last few lines of output)
check() {
  local desc="$1"; shift; local out
  if out=$("$@" 2>&1); then ok "$desc"
  else no "$desc" "$(printf '%s' "$out" | tail -3 | tr '\n' '|')"; fi
}
# PASS if cmd output matches the extended regex
check_match() {
  local desc="$1" re="$2"; shift 2; local out
  if ! out=$("$@" 2>&1); then no "$desc" "command failed: $(printf '%s' "$out" | tail -2 | tr '\n' '|')"; return; fi
  if grep -Eq "$re" <<<"$out"; then ok "$desc"; else no "$desc" "expected /$re/ in output"; fi
}

# ---- preflight: sudo + OpenStack creds --------------------------------------
echo "Priming sudo (root-only checks: Ceph / MariaDB / RabbitMQ / nova-manage / SSH auth log)…"
if sudo -v 2>/dev/null; then SUDO_OK=1; else SUDO_OK=0; fi

if [[ -z "${OS_AUTH_URL:-}" && -f "$OPENRC" ]]; then
  # shellcheck disable=SC1090
  source "$OPENRC"
fi
[[ -n "${OS_AUTH_URL:-}" ]] && OSC_OK=1 || OSC_OK=0

# ---- 1. systemd units -------------------------------------------------------
hdr "1. systemd units"
units=(
  mariadb rabbitmq-server memcached httpd openvswitch
  openstack-glance-api
  openstack-nova-api openstack-nova-scheduler openstack-nova-conductor openstack-nova-novncproxy
  neutron-server neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent
  restorecond
)
for u in "${units[@]}"; do
  state=$(systemctl is-active "$u" 2>/dev/null)
  [[ "$state" == active ]] && ok "$u" || no "$u" "is-active: ${state:-not-found}"
done

# ---- 2. Ceph ----------------------------------------------------------------
hdr "2. Ceph"
if [[ $SUDO_OK -eq 1 ]]; then
  health=$(sudo ceph health 2>/dev/null)
  case "$health" in
    HEALTH_OK)    ok "ceph health: HEALTH_OK" ;;
    HEALTH_WARN*) wn "ceph health: $health" "$(sudo ceph health detail 2>/dev/null | head -4 | tr '\n' '|')" ;;
    *)            no "ceph health" "${health:-no response from ceph}" ;;
  esac
  nfo "$(sudo ceph -s 2>/dev/null | grep -E 'mon:|mgr:|osd:' | sed 's/^ *//' | tr '\n' '|')"
  check_match "osd pool 'images' exists" '(^|[[:space:]])images([[:space:]]|$)' sudo ceph osd pool ls
else
  wn "Ceph checks skipped (no sudo)"
fi

# ---- 3. Databases (MariaDB) -------------------------------------------------
hdr "3. Databases (MariaDB)"
if [[ $SUDO_OK -eq 1 ]]; then
  if dbs=$(sudo mysql -N -B -e "SHOW DATABASES;" 2>/dev/null) && [[ -n "$dbs" ]]; then
    for d in keystone glance placement nova nova_api nova_cell0 neutron; do
      grep -qx "$d" <<<"$dbs" && ok "db: $d" || no "db: $d" "missing"
    done
  else
    no "MariaDB" "could not list databases"
  fi
else
  wn "DB checks skipped (no sudo)"
fi

# ---- 4. RabbitMQ ------------------------------------------------------------
hdr "4. RabbitMQ"
if [[ $SUDO_OK -eq 1 ]]; then
  check "rabbitmq node responding" sudo rabbitmqctl status
  check_match "rabbitmq user 'openstack' exists" '(^|[[:space:]])openstack([[:space:]]|$)' sudo rabbitmqctl list_users
else
  wn "RabbitMQ checks skipped (no sudo)"
fi

# ---- 5. Keystone (identity) -------------------------------------------------
hdr "5. Keystone (identity)"
if [[ $OSC_OK -eq 1 ]]; then
  # A successful token issue proves keystone + mariadb + memcached + httpd at once.
  check "token issue (keystone + db + memcached + httpd)" openstack token issue
  for s in identity image compute network placement; do
    check_match "service catalog: $s" "(^|[[:space:]])$s([[:space:]]|\$)" openstack service list -f value -c Type
  done
  asgn=$(openstack role assignment list --names -f value 2>/dev/null)
  for usr in glance nova neutron placement; do
    if grep -Eq "(^|[[:space:]])admin[[:space:]].*${usr}@Default.*service@Default" <<<"$asgn"; then
      ok "role: ${usr} = admin on service project"
    else
      no "role: ${usr} admin-on-service" "not found in 'role assignment list --names' (the Phase 1 issue #5 check)"
    fi
  done
else
  wn "Keystone / OpenStack-CLI checks skipped" "no creds — 'source ~/admin-openrc' or set OPENRC= (tried: $OPENRC)"
fi

# ---- 6. Glance (image) ------------------------------------------------------
hdr "6. Glance (image)"
if [[ $OSC_OK -eq 1 ]]; then
  if ! imgs=$(openstack image list -f value -c ID -c Name 2>&1); then
    no "image list" "$(printf '%s' "$imgs" | tail -2 | tr '\n' '|')"
  elif [[ -z "$imgs" ]]; then
    ok "glance-api responds (image list empty)"
  else
    ok "image list ($(grep -c . <<<"$imgs") image(s))"
    id=$(head -1 <<<"$imgs" | awk '{print $1}')
    if [[ $SUDO_OK -eq 1 ]]; then
      if sudo rbd -p images ls 2>/dev/null | grep -q "$id"; then
        ok "image is RBD-backed ($id found in Ceph 'images' pool)"
      else
        wn "could not confirm image $id in the rbd 'images' pool"
      fi
    fi
  fi
else
  nfo "skipped (no OpenStack creds)"
fi

# ---- 7. Placement -----------------------------------------------------------
hdr "7. Placement"
tmp=$(mktemp)
code=$(curl -s -o "$tmp" -w '%{http_code}' "http://${CONTROLLER_FQDN}:8778/" 2>/dev/null)
if [[ "$code" == "200" ]] && grep -q '"versions"' "$tmp"; then
  ok "placement answers its version document (HTTP 200)"
else
  no "placement endpoint" "HTTP ${code:-none} (a 403 = the Apache vhost 'Require all granted' gap — Stage 3 problem 2)"
fi
rm -f "$tmp"

# ---- 8. Nova (compute) ------------------------------------------------------
hdr "8. Nova (compute)"
if [[ $SUDO_OK -eq 1 ]]; then
  check "nova-status upgrade check" sudo -u nova nova-status upgrade check
  cells=$(sudo -u nova nova-manage cell_v2 list_cells 2>/dev/null)
  { grep -q cell0 <<<"$cells" && grep -q cell1 <<<"$cells"; } \
    && ok "cells: cell0 + cell1 present" || no "cells" "expected cell0 and cell1 in list_cells"
  # every compute host should be mapped into a cell (the discover_hosts step)
  mapped=$(sudo -u nova nova-manage cell_v2 list_hosts 2>/dev/null | grep -Ec 'compute[0-9]')
  [[ "$mapped" -ge "$EXPECTED_COMPUTES" ]] \
    && ok "cell host mappings: $mapped compute host(s) in a cell" \
    || no "cell host mappings" "$mapped mapped (expected >= $EXPECTED_COMPUTES; run 'nova-manage cell_v2 discover_hosts')"
else
  wn "nova-manage checks skipped (no sudo)"
fi
if [[ $OSC_OK -eq 1 ]]; then
  svc=$(openstack compute service list -f value -c Binary -c State 2>/dev/null)
  for b in nova-scheduler nova-conductor; do
    grep -Eq "${b}.*\bup\b" <<<"$svc" && ok "compute service: ${b} up" \
      || no "compute service: ${b}" "$(grep "$b" <<<"$svc" || echo 'absent / not up')"
  done
  nc_up=$(grep -Ec "nova-compute.*\bup\b" <<<"$svc")
  nc_tot=$(grep -c "nova-compute" <<<"$svc")
  [[ "$nc_up" -ge "$EXPECTED_COMPUTES" ]] \
    && ok "compute service: nova-compute ($nc_up up)" \
    || no "compute service: nova-compute" "$nc_up/$nc_tot up (expected >= $EXPECTED_COMPUTES up)"
  hv_n=$(openstack hypervisor list -f value 2>/dev/null | grep -c .)
  [[ "$hv_n" -ge "$EXPECTED_COMPUTES" ]] \
    && ok "hypervisors registered: $hv_n" \
    || no "hypervisors" "$hv_n registered (expected >= $EXPECTED_COMPUTES)"
fi

# ---- 9. Neutron (network) ---------------------------------------------------
hdr "9. Neutron (network)"
if [[ $OSC_OK -eq 1 ]]; then
  agents=$(openstack network agent list -f value -c "Agent Type" -c Alive 2>/dev/null)
  # L3 + DHCP agents live only on the controller (the network node)
  for a in "L3 agent" "DHCP agent"; do
    line=$(grep -F "$a" <<<"$agents")
    if [[ -z "$line" ]]; then no "agent: $a" "not registered"
    elif grep -qE ':-\)|True' <<<"$line"; then ok "agent: $a (alive)"
    else wn "agent: $a present but not alive" "$line"; fi
  done
  # Open vSwitch agents: one VTEP per node — controller + each compute
  ovs_tot=$(grep -Fc "Open vSwitch agent" <<<"$agents")
  ovs_up=$(grep -F "Open vSwitch agent" <<<"$agents" | grep -Ec ':-\)|True')
  ovs_exp=$((EXPECTED_COMPUTES + 1))
  [[ "$ovs_up" -ge "$ovs_exp" ]] \
    && ok "agent: Open vSwitch ($ovs_up/$ovs_tot alive — controller + computes)" \
    || no "agent: Open vSwitch" "$ovs_up/$ovs_tot alive (expected >= $ovs_exp: controller + $EXPECTED_COMPUTES computes)"
  check_match "ml2 'router' extension loaded (self-service L3)" '(^|[[:space:]])router([[:space:]]|$)' \
    openstack extension list --network -f value -c Alias
  nets=$(openstack network list -f value -c Name 2>/dev/null)
  nfo "networks: $(grep -c . <<<"$nets") defined (asserted individually in section 10)"
else
  wn "Neutron checks skipped (no creds)"
fi

# ---- 10. Stage 5 objects (networks / router / VXLAN overlay / VM) -----------
hdr "10. Stage 5 objects (networks / router / overlay)"
if [[ $OSC_OK -eq 1 ]]; then
  # provider/external network — flat, external
  if ptype=$(openstack network show provider -f value -c provider:network_type 2>/dev/null); then
    [[ "$ptype" == flat ]] && ok "provider network (flat)" \
      || no "provider network type" "got '$ptype' (expected flat)"
    pext=$(openstack network show provider -f value -c router:external 2>/dev/null)
    grep -qiE 'external|true' <<<"$pext" && ok "provider network is external" \
      || no "provider network not external" "router:external=$pext"
  else
    no "provider network" "not found — has bootstrap.yml been applied?"
  fi
  # tenant self-service VXLAN network — MTU 1450
  if ttype=$(openstack network show tenant-net -f value -c provider:network_type 2>/dev/null); then
    [[ "$ttype" == vxlan ]] && ok "tenant-net (vxlan)" \
      || no "tenant-net type" "got '$ttype' (expected vxlan)"
    tmtu=$(openstack network show tenant-net -f value -c mtu 2>/dev/null)
    [[ "$tmtu" == 1450 ]] && ok "tenant-net MTU 1450" \
      || wn "tenant-net MTU" "got '$tmtu' (expected 1450)"
  else
    no "tenant-net" "not found"
  fi
  # router with an external gateway onto the provider net
  gw=$(openstack router show router1 -f value -c external_gateway_info 2>/dev/null)
  if [[ -n "$gw" && "$gw" != None ]]; then ok "router1 present with external gateway"
  else no "router1 external gateway" "router1 missing or no external gateway set"; fi
  # CirrOS test VM — transient, informational only
  vms=$(openstack server list -f value -c Name -c Status 2>/dev/null)
  [[ -z "$vms" ]] && nfo "no instances (the CirrOS test VM is optional/transient)" \
                  || nfo "instances: $(printf '%s' "$vms" | tr '\n' '|')"
else
  wn "Stage 5 object checks skipped (no creds)"
fi
# VXLAN overlay data-plane (the l2population fix): br-tun must carry tunnel ports
if [[ $SUDO_OK -eq 1 ]]; then
  tun=$(sudo ovs-vsctl list-ports br-tun 2>/dev/null | grep -c '^vxlan-')
  [[ "$tun" -ge 1 ]] \
    && ok "overlay: $tun VXLAN tunnel port(s) on br-tun" \
    || no "overlay tunnels" "no vxlan-* ports on br-tun — l2population missing from ml2 mechanism_drivers?"
  if sudo grep -qE '^[[:space:]]*mechanism_drivers[[:space:]]*=.*l2population' \
       /etc/neutron/plugins/ml2/ml2_conf.ini 2>/dev/null; then
    ok "ml2 mechanism_drivers includes l2population"
  else
    no "ml2 l2population" "not in mechanism_drivers (agents' l2_population=true builds no tunnels)"
  fi
else
  wn "overlay (br-tun) checks skipped (no sudo)"
fi

# ---- 11. Recent auth failures (SSH) -----------------------------------------
# Security hygiene, not control-plane health: surfaces repeated failed SSH logins
# (brute-force probes). Read with sudo so it sees attempts against EVERY account
# (root, invalid users, etc.) — a non-root journal read only exposes the calling
# user's own records. On this OpenSSH the per-connection process is 'sshd-session',
# not 'sshd', so both are matched or the count reads as zero. WARN-only (never
# FAIL): a noisy security signal shouldn't break the control-plane health gate.
hdr "11. Recent auth failures (SSH)"
AUTH_WINDOW="${AUTH_WINDOW:-24 hours ago}"   # journalctl --since window
AUTH_WARN="${AUTH_WARN:-10}"                 # >= this many failures -> WARN ("repeated")
if [[ $SUDO_OK -eq 1 ]]; then
  fre='Failed password|Invalid user|authentication failure|maximum authentication attempts|(Connection (closed|reset)|Disconnected) (from|by) (authenticating|invalid) user'
  jlog=$(sudo journalctl -t sshd -t sshd-session --since "$AUTH_WINDOW" --no-pager 2>/dev/null)
  nfail=$(grep -Ec "$fre" <<<"$jlog")
  if [[ "$nfail" -eq 0 ]]; then
    ok "no failed SSH logins since '$AUTH_WINDOW'"
  elif [[ "$nfail" -lt "$AUTH_WARN" ]]; then
    nfo "$nfail failed SSH login attempt(s) since '$AUTH_WINDOW' (below WARN threshold $AUTH_WARN)"
  else
    # surface the top offending source IPs to aid triage
    top=$(grep -E "$fre" <<<"$jlog" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
          | sort | uniq -c | sort -rn | head -3 | awk '{printf "%s(%s) ", $2, $1}')
    wn "$nfail failed SSH login attempts since '$AUTH_WINDOW' (>= $AUTH_WARN — possible brute force)" \
       "top source IPs: ${top:-n/a}"
  fi
else
  wn "auth-failure check skipped (no sudo)"
fi

# ---- summary ----------------------------------------------------------------
hdr "Summary"
printf '  %sPASS %d%s    %sWARN %d%s    %sFAIL %d%s\n' "$G" "$pass" "$N" "$Y" "$warn" "$N" "$R" "$fail" "$N"
if [[ $fail -gt 0 ]]; then
  printf '  %sControl plane has FAILures — see above.%s\n' "$R" "$N"; exit 1
fi
printf '  %sControl plane healthy%s (warnings are non-fatal).\n' "$G" "$N"
exit 0
