# Tor Relay Status Tidbyt app

A Pixlet app for the Tidbyt that displays the live status of every relay in a configured Tor relay family. Data comes from the [Tor Project's Onionoo API](https://onionoo.torproject.org/).

See [design-notes.md](./design-notes.md) for layout choices and the Onionoo schema. Licensed under [MIT](./LICENSE) — © 2026 Brian W Bush.

## What it shows

```
┌────────────┬──────────────────┐
│            │ BW         48M   │   total advertised bandwidth (bytes/sec, formatted)
│   7/7      │ CW       0.96%   │   family's share of Tor network consensus weight
│  (color)   │ ●●●●●●●          │   one colored 4×4 dot per relay
│            │                  │
└────────────┴──────────────────┘
   running / total                  per-relay color:
                                      green  = running, version OK
   tile color:                        yellow = running, non-recommended version
     green   all healthy              red    = not running
     yellow  all up, version stale
     orange  some down
     dark red  all down
```

The big tile's color is the at-a-glance health answer: green = all green, yellow = version-only warning, orange = some down, dark red = all down. The right column gives the operational details.

## Data source: Onionoo

The Onionoo API at `onionoo.torproject.org` is public, free, and refreshed **at most once per hour** — after each new Tor network consensus is published. Polling faster gives you nothing. The endpoint we hit:

```
GET /details?family=<40-hex-fingerprint>&fields=nickname,running,advertised_bandwidth,consensus_weight_fraction,version_status
```

Pass any one relay's fingerprint as `family=`; Onionoo expands it to all family members. The container schedules its push at **HH:10 UTC every hour** (Tor consensus publishes at HH:00 UTC, leaving 10 minutes for Onionoo to propagate the new data). The Pixlet HTTP cache (`ttl_seconds=3600`) backstops that schedule so even ad-hoc re-renders don't double up on requests.

## Setup

1. **Enter the dev shell** to get pixlet on PATH:
   ```
   nix develop
   ```

2. **Create config.yaml** from the template and fill in your Tidbyt creds + family fingerprint:
   ```
   cp config-example.yaml config.yaml
   ${EDITOR:-vi} config.yaml
   ```

3. **Sanity-check** before deploying:
   ```
   ./scripts/check.sh
   ```
   Confirms Onionoo responds, prints each relay's status (nickname, running, version OK, observed bandwidth in MB/s, consensus weight, country), and the aggregate the app will display.

4. **Preview locally:**
   ```
   ./scripts/preview.sh
   ```

5. **One-shot push:**
   ```
   ./scripts/deploy.sh
   ```

6. **Daemon (container):**
   ```
   ./scripts/build-container.sh
   podman kube play --replace torrelay.yaml
   podman logs -f torrelay-tidbyt
   ```

## Files

| | |
| --- | --- |
| `main.star` | The Pixlet app (Starlark). |
| `flake.nix` | Nix dev shell + pixlet derivation + container image. |
| `config-example.yaml` | Template. Copy to `config.yaml` (gitignored). |
| `scripts/check.sh` | Pre-deploy sanity check. |
| `scripts/preview.sh` | `pixlet serve` for browser preview. |
| `scripts/render.sh` | Render one frame to `out.webp`. |
| `scripts/deploy.sh` | Render and `pixlet push` once. |
| `scripts/build-container.sh` | Build the OCI image with creds baked in. |
| `scripts/run-container.sh` | Run the push-daemon container with `podman run`. |
| `torrelay.yaml` | Podman kube spec for the daemon pod. |
| `design-notes.md` | Layout rationale, Onionoo schema notes, open questions. |

## Notes and caveats

- **Family scope:** the dots row fits up to ~10 relays in 36 px. Larger families will overflow.
- **Version recommendation:** `recommended_version` is what the Tor directory authorities say at consensus time — it can lag a fresh release by hours.
- **Onionoo cache:** Onionoo serves data refreshed at most once per hour (after each Tor consensus is published); ground-truth events like a relay dropping offline take up to that long to appear in the display.
- **Push timing:** the daemon aligns to HH:10 UTC. If you reboot the host at HH:43 UTC, the daemon will wait ~27 minutes for the next HH:10 before its first push. To force an immediate push, run `./scripts/deploy.sh` (or `./scripts/run-container.sh --once`).
