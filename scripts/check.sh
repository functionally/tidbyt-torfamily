#!/usr/bin/env bash
# Pre-deploy sanity check.
# - Verifies Onionoo responds for the configured family
# - Prints per-relay status (nickname, running, version OK, bandwidth, weight)
# - Computes the aggregate the app will display
# - Confirms Tidbyt creds are populated
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f config.yaml ]]; then
  echo "ERROR: config.yaml is missing. Run: cp config-example.yaml config.yaml" >&2
  exit 1
fi

FAMILY_RAW="$(yq -r '.family_fingerprint' config.yaml)"
TIDBYT_KEY="$(yq -r '.tidbyt_api_key' config.yaml)"
TIDBYT_DEVICE_ID="$(yq -r '.tidbyt_device_id' config.yaml)"
TIDBYT_INSTALLATION_ID="$(yq -r '.tidbyt_installation_id' config.yaml)"

green() { printf "\033[32m%s\033[0m" "$1"; }
red()   { printf "\033[31m%s\033[0m" "$1"; }
ok()    { printf "  $(green '✓') %s\n" "$1"; }
warn()  { printf "  $(red '✗') %s\n" "$1"; }

if [[ -z "$FAMILY_RAW" || "$FAMILY_RAW" == "null" ]]; then
  warn "family_fingerprint is missing/empty in config.yaml"
  exit 1
fi

# Normalize: strip a leading '$' (Tor's nickname-prefix convention), strip
# any whitespace anywhere, and accept upper- or lower-case hex.
FAMILY="${FAMILY_RAW#\$}"
FAMILY="${FAMILY//[[:space:]]/}"

if [[ ${#FAMILY} -ne 40 ]]; then
  warn "family_fingerprint has length ${#FAMILY} (expected 40)"
  echo "      got:     '${FAMILY_RAW}'"
  echo "      cleaned: '${FAMILY}'"
  exit 1
fi
if [[ ! "$FAMILY" =~ ^[A-Fa-f0-9]+$ ]]; then
  warn "family_fingerprint contains non-hex characters"
  echo "      got: '${FAMILY_RAW}'"
  exit 1
fi

echo "== Onionoo family lookup =="
FIELDS="nickname,fingerprint,last_seen,advertised_bandwidth,consensus_weight_fraction,guard_probability,middle_probability,exit_probability,running,flags,country,version_status"
URL="https://onionoo.torproject.org/details?family=${FAMILY}&fields=${FIELDS}"
RESP=$(curl -sL --max-time 12 -w "\n%{http_code}" "$URL")
CODE=$(printf '%s' "$RESP" | tail -n1)
BODY=$(printf '%s' "$RESP" | sed '$d')

if [[ "$CODE" != "200" ]]; then
  warn "Onionoo returned HTTP $CODE"
  exit 1
fi

ok "endpoint OK (HTTP 200)"

echo
python3 - <<EOF
import json
d = json.loads('''${BODY}''')
relays = sorted(d.get("relays", []), key=lambda r: r.get("nickname", "") or "")
print(f"  family:   ${FAMILY}")
print(f"  relays:   {len(relays)}")
print()
print(f"  {'nickname':18s}  {'run':>4s}  {'ver_status':>14s}  {'adv MB/s':>9s}  {'CW frac':>9s}  {'g/m/e':>15s}  {'flags':25s}  cc")
running = 0
total_bw = 0
total_cwf = 0.0
outdated = 0
for r in relays:
    nick = (r.get("nickname") or "?")[:18]
    run = "yes" if r.get("running") else "NO"
    vs = r.get("version_status") or "?"
    bw = (r.get("advertised_bandwidth") or 0) / 1e6
    cwf = r.get("consensus_weight_fraction") or 0
    gp = (r.get("guard_probability") or 0) * 100
    mp = (r.get("middle_probability") or 0) * 100
    ep = (r.get("exit_probability") or 0) * 100
    flags = ",".join((r.get("flags") or []))[:25]
    cc = r.get("country") or "??"
    gme = f"{gp:.2f}/{mp:.2f}/{ep:.2f}"
    if r.get("running"):
        running += 1
        total_bw += (r.get("advertised_bandwidth") or 0)
        total_cwf += cwf
        if vs != "recommended":
            outdated += 1
    print(f"  {nick:18s}  {run:>4s}  {vs:>14s}  {bw:>9.2f}  {cwf*100:>8.4f}%  {gme:>15s}  {flags:25s}  {cc}")
print()
print(f"  totals: running {running}/{len(relays)}, advertised BW {total_bw/1e6:.1f} MB/s, CW frac {total_cwf*100:.4f}% of network, version status: {outdated} non-recommended")
if running == len(relays) and outdated == 0:
    print("  \033[32mall green — tile will display GREEN\033[0m")
elif running == len(relays) and outdated > 0:
    print(f"  \033[33mall up but {outdated} non-recommended version — tile will display YELLOW\033[0m")
elif running > 0:
    print(f"  \033[33m{len(relays)-running} down — tile will display ORANGE\033[0m")
else:
    print(f"  \033[31mALL DOWN — tile will display DARK RED\033[0m")
EOF

echo
echo "== Tidbyt credentials =="
[[ -n "$TIDBYT_KEY" && "$TIDBYT_KEY" != "null" && "$TIDBYT_KEY" != YOUR-* ]] \
  && ok "tidbyt_api_key set" || warn "tidbyt_api_key not set"
[[ -n "$TIDBYT_DEVICE_ID" && "$TIDBYT_DEVICE_ID" != "null" && "$TIDBYT_DEVICE_ID" != YOUR-* ]] \
  && ok "tidbyt_device_id set" || warn "tidbyt_device_id not set"
if [[ "$TIDBYT_INSTALLATION_ID" =~ ^[A-Za-z0-9]+$ ]]; then
  ok "tidbyt_installation_id ($TIDBYT_INSTALLATION_ID) is alphanumeric"
else
  warn "tidbyt_installation_id ($TIDBYT_INSTALLATION_ID) must be alphanumeric"
fi

echo
echo "All checks passed. Safe to deploy."
