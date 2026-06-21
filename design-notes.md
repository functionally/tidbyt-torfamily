# Tor Relay Status Tidbyt — design notes

Compact design rationale. The layout/flake/scripts mirror the sibling Tidbyt projects (Longmont AQ, Crypto Prices); this doc covers what's specific to Tor.

## Data source: Onionoo

[Onionoo](https://onionoo.torproject.org/) is the Tor Project's public REST API for relay metadata. Free, no auth, refreshes **at most once per hour** — after each new Tor consensus is published by the directory authorities.

Endpoint:
```
GET https://onionoo.torproject.org/details
    ?family=<40-hex-fingerprint>
    &fields=nickname,running,advertised_bandwidth,consensus_weight_fraction,version_status
```

Response shape (truncated, one entry per relay):
```json
{
  "version": "8.0",
  "relays_published": "2026-06-21 21:00:00",
  "relays": [
    {
      "nickname": "<relay-nickname>",
      "running": true,
      "advertised_bandwidth": 5728000,
      "consensus_weight_fraction": 0.00018,
      "version_status": "unrecommended"
    },
    ...
  ]
}
```

Why these five fields (and not the dozen+ available):

- `nickname` — useful in `check.sh`; the on-display rendering doesn't show names (no room), but listing them in the verification script makes it obvious which dot is which.
- `running` — Onionoo's flag for "directory authorities saw this relay in the last consensus." That's the primary green/red test.
- `advertised_bandwidth` — bytes per second the relay declares it can carry, in line with what the operator configured. Sum across the family is the family's *declared* capacity (not necessarily what the network is currently routing through it).
- `consensus_weight_fraction` — the relay's share of the total Tor consensus weight (0..1). Summed across a family it's the family's network share. More meaningful for a small operator than the raw `consensus_weight` integer, which is unit-less until you know the network total.
- `version_status` — a string from the directory authorities. Values include `recommended`, `experimental`, `new in series`, `obsolete`, `unrecommended`. The app treats anything that isn't `recommended` as "version warning" (yellow).

Onionoo has many more fields (`flags`, `country`, `as_name`, `uptime`, `first_seen`, `bandwidth_history`, `guard_probability`, `middle_probability`, `exit_probability`…) — the app skips them on display to keep the frame uncluttered. The check script pulls a richer set (flags, country, g/m/e probabilities, version_status) for context.

### `family=` semantics

Onionoo's `family=` query is symmetric: pass any one fingerprint and you get back all relays in that family, including the relay you queried. The family is defined by the directory consensus (via the `family` line in each relay's descriptor) — an operator declares their relays as family members so the directory can keep them from being used together on the same circuit. So whatever fingerprint you put in `config.yaml`, you get the whole family.

## Display layout

64 × 32 RGB pixels. Same two-tile structure as the Longmont AQ app — big colored tile on the left for the at-a-glance health, packed right column for operational detail.

```
┌────────────┬─────────────────────────────────┐
│            │ BW          51M                 │
│   7/7      │ CW          48k                 │
│ (color bg) │ ●●●●●●●                         │
│            │                                 │
└────────────┴─────────────────────────────────┘
  28×32 left      34×32 right (incl. 2 px pad)
```

### Big tile

- Width 28 × height 32 (full display height).
- **Top:** first 4 hex characters of the family fingerprint, `tb-8` font (Pixlet's default 8-tall variable-width font), **dark navy** (`#000080` — half-brightness pure blue). Acts as a "which family is this?" identifier without dominating the tile. The hue is maximally distinct from every health-state background (green/yellow/orange/red all share R and/or G channels; pure blue uses only the B channel) and the half-brightness reads as "dark text" against the bright Moderate/USG/Good tiles. Using `tb-8` instead of the smaller `tom-thumb` puts more colored pixels on the screen, which further amplifies the hue contrast against the bright background.
- **Bottom:** "`<running>/<total>`" in `6x13` font. 7/7 fits comfortably; the format supports any 1-digit / 1-digit count up through 2-digit / 2-digit (`12/12` = 18 px in `6x13`, fits in the 28 px tile).
- Vertical layout is `Column(main_align="space_evenly")` — the 11 px of slack (32 px tile − 8 px label − 13 px count) distributes as ~3–4 px top, ~3–4 px between, ~3–4 px bottom.
- Background color encodes the aggregate health:

| Condition | Background | Foreground | Color name |
| --- | --- | --- | --- |
| All relays running, all on recommended version | `#00E400` | black | "all-green" |
| All running, ≥1 on non-recommended version | `#FFFF00` | black | "version warning" |
| Some down (but ≥1 still up) | `#FF7E00` | black | "partial down" |
| All down | `#7E0023` | white | "all-down" (matches EPA Hazardous) |

The palette deliberately mirrors the [Longmont AQ project's EPA AQI colors](../../Reference/Air%20Quality/research-notes.md) for cross-device color-language consistency.

### Right column

Three rows in `tom-thumb`:

1. `BW` ⋯ aggregate advertised bandwidth (sum over running relays), formatted with k/M/G suffix (`51M`, `980k`, `2G`).
2. `CW` ⋯ aggregate consensus weight fraction, displayed as a percentage of the Tor network (`0.96%`, `12.3%`). Sub-0.01% renders as `<.01%` rather than scientific notation.
3. Per-relay dots — one 4×4 `Box` per relay, 1 px gap, color-coded:
   - **Green** (`#00C800`) — running, version OK.
   - **Yellow** (`#FFEE00`) — running, version flagged non-recommended.
   - **Red** (`#FF0000`) — not running.

7 dots at 4 px + 1 px gap each = 35 px in a 36 px right column. The layout accommodates up to ~10 relays before overflow — fine for the typical small-operator family, not for large fleets. Larger families would need a different visualization (stacked rows of dots, or aggregate-only).

### Why a 4-character fingerprint label, not the nickname

Tor relay nicknames are 1–19 characters, often sharing a prefix across the family (e.g., `<NICK>1` through `<NICK>7`). At tom-thumb widths a typical nickname-derived label would consume most of the right column or overflow the big tile. The fingerprint's first 4 hex characters are always exactly 4 characters wide, unambiguous against any other family the operator might monitor at the same time, and easy to spot at a glance.

The label color (`#000080`, navy / half-brightness pure blue) doesn't change with the health-state background — it's a constant "this is which family" cue, distinct from the warm green/yellow/orange/red palette that encodes health. The "warm vs. cool" hue split means the label reads as visually different content even when the background is also at high luminance.

An earlier iteration used a bright Tor-brand purple (`#BB80FF`); that worked OK on green and dark red but had low contrast against the yellow Moderate tile because purple shares the red channel with yellow. Switching to a pure-blue hue removes any channel overlap with the warm-palette backgrounds.

## Caching and cadence

The Tor consensus publishes at **HH:00 UTC** each hour. Onionoo propagates the new data into its cache shortly after. The daemon's entrypoint:

- Sleeps until the next **HH:10 UTC** wall-clock mark, then renders + pushes.
- Repeats every hour aligned to the same wall-clock minute (no drift — it re-aligns each cycle from `date -u +%M`).
- Sub-second drift between cycles since render+push takes a few seconds; the re-alignment absorbs it.

Why HH:10 UTC and not just `sleep 3600`:

- With a fixed-interval sleep, the push time drifts away from the consensus publish time as the daemon runs (each iteration starts a couple of seconds after the previous push completes). Over weeks, the push could end up at any minute past the hour, sometimes falling right before Onionoo's refresh and showing an entire hour's-stale data on the display.
- Wall-clock alignment means every push catches the latest possible consensus.

Why minute 10 specifically:

- Onionoo documents that data refreshes after each consensus, but doesn't pin the propagation time. Empirically the new consensus is queryable within a few minutes; HH:10 leaves comfortable headroom while still showing the new state inside the same hour it became valid.

Override:

- `PUSH_AT_MINUTE_UTC` env var (passed to the container) controls the minute. Set to `30` to push at HH:30, etc.
- Pixlet's `http.get(ttl_seconds=3600)` backstops the schedule: even if you re-trigger a render in between hourly pushes (e.g., `./scripts/render.sh`), the Onionoo response is cached for the rest of the hour.

## Color palette reference

| Use | Hex | Notes |
| --- | --- | --- |
| All-green tile bg | `#00E400` | EPA AQI Good |
| Version-warning tile bg | `#FFFF00` | EPA AQI Moderate |
| Partial-down tile bg | `#FF7E00` | EPA AQI USG |
| All-down tile bg | `#7E0023` | EPA AQI Hazardous |
| Dark fg on bright bg | `#000000` | |
| White fg on dark bg | `#FFFFFF` | |
| Per-relay dot — green | `#00C800` | Tidbyt-friendly green, less saturated than EPA |
| Per-relay dot — yellow | `#FFEE00` | "almost EPA yellow", with red tinge for contrast |
| Per-relay dot — red | `#FF0000` | EPA AQI Unhealthy |
| Family label — navy | `#000080` | Pure blue at 50% brightness. Only B channel — zero overlap with green/yellow/orange/red backgrounds; reads as "dark text" on bright tiles |

## Starlark gotchas (carried from sibling projects)

- `%` operator has no precision specifier — no `%.4f`. Format manually with integer arithmetic.
- No `while` loop. Use `for x in range(n)` or string multiplication for padding.
- Standard `+=`-style augmented assignment is supported (`x += 1` works) but be careful with mutability; Starlark lists are mutable, dicts are mutable, strings are immutable.

## Open questions / stretch ideas

- **Larger families.** A 20-relay family won't fit 20 dots in 36 px. Options: smaller dots (2×2 px), two rows of dots, or aggregate-only mode that drops the per-relay row.
- **Bandwidth history sparkline.** Onionoo's `/bandwidth?fingerprint=…` returns a time series — a 32-px mini chart under the BW row would show whether the relay is currently above or below its rolling capacity.
- **Multiple families.** Animation between two or three families (similar to the original crypto rotating layout). Skip for v1.
- **Exit-relay specifics.** If the family includes exit relays, the dots could distinguish guard / middle / exit with shape rather than color. Not needed when the family is guards-only; revisit if exit relays join.
- **Country flags or icons.** Tidbyt is small but a 4×4 emoji-style flag per relay could give geo-distribution at a glance. Stretch.
- **Alert escalation.** Beyond visual state, a hook into Pushover/ntfy for "any relay just went down" would catch outages between glances. That's daemon-level, not display-level.
