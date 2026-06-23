"""Tor relay family status for Tidbyt.

Polls Tor Project's Onionoo `/details` endpoint for all relays in a configured
family and renders a status tile + per-relay indicators.

See ./design-notes.md for layout choices and data-source notes.
"""

load("render.star", "render")
load("http.star", "http")
load("encoding/json.star", "json")
load("schema.star", "schema")

ONIONOO_BASE = "https://onionoo.torproject.org"
# Onionoo refreshes its data at most once per hour, after each new Tor
# consensus is published. Polling more often than that returns identical
# results, so we cache aggressively.
FETCH_TTL_S = 3600

# AQI-style traffic-light palette, deliberately matching what's used in the
# Longmont AQ Tidbyt app for cross-device consistency. See ./design-notes.md.
GREEN_BG  = "#00E400"
YELLOW_BG = "#FFFF00"
ORANGE_BG = "#FF7E00"
DARK_RED_BG = "#7E0023"
GREEN_DOT = "#00C800"
YELLOW_DOT = "#FFEE00"
RED_DOT = "#FF0000"
FG_BLACK = "#000000"
FG_WHITE = "#FFFFFF"

# Family-label color. We want a hue that's *maximally different* from the
# tile background palette (green / yellow / orange / red — all warm, all
# heavy on R and/or G channels) so the label stays distinct on any health
# state. Pure blue has zero R, zero G — no channel overlap with any warm
# background. A half-brightness navy renders as readable "dark text" on
# the bright tiles (yellow/orange/green) where dim-against-bright is the
# right contrast story. On the dark-red all-down tile both colors are dim
# and contrast is poor — acceptable because the red tile is itself the
# alarm and the label is secondary.
FAMILY_LABEL_COLOR = "#000080"

def fetch_family(fingerprint):
    """Fetch the trimmed detail set for every relay in the family.
    Returns None on transport / parse error, a (possibly empty) list of
    relay dicts otherwise."""
    if not fingerprint:
        print("[fetch] Onionoo SKIP (no fingerprint)")
        return None
    fields = "nickname,running,advertised_bandwidth,consensus_weight_fraction,version_status"
    url = "%s/details?family=%s&fields=%s" % (ONIONOO_BASE, fingerprint, fields)
    # Redact the family fingerprint in the logged URL — the user has
    # asked that the fingerprint not appear outside config.yaml.
    safe_url = url.replace(fingerprint, "<FP_REDACTED>")
    print("[fetch] GET %s ttl=%d" % (safe_url, FETCH_TTL_S))
    r = http.get(url, ttl_seconds = FETCH_TTL_S)
    print("[fetch] Onionoo HTTP=%d bytes=%d" % (r.status_code, len(r.body())))
    if r.status_code != 200:
        return None
    body = r.json() or {}
    relays = body.get("relays", [])
    print("[fetch] Onionoo relays=%d" % len(relays))
    return relays

def _is_outdated(r):
    """`version_status` is a string: 'recommended', 'experimental', 'obsolete',
    'new in series', 'unrecommended', etc. Anything that isn't 'recommended'
    flags the relay yellow."""
    vs = r.get("version_status")
    if vs == None:
        return False
    return vs != "recommended"

def _aggregate(relays):
    running = 0
    total_bw = 0
    total_cwf = 0.0
    any_outdated = False
    for r in relays:
        if r.get("running"):
            running += 1
            total_bw += r.get("advertised_bandwidth") or 0
            total_cwf += r.get("consensus_weight_fraction") or 0.0
            if _is_outdated(r):
                any_outdated = True
    return running, len(relays), total_bw, total_cwf, any_outdated

def _tile_colors(running, total, any_outdated):
    """Background + foreground for the big running-count tile.
    All-down → dark red. Partial → orange. All-up-but-stale-version → yellow.
    All-healthy → green."""
    if total == 0 or running == 0:
        return DARK_RED_BG, FG_WHITE
    if running < total:
        return ORANGE_BG, FG_BLACK
    if any_outdated:
        return YELLOW_BG, FG_BLACK
    return GREEN_BG, FG_BLACK

def _relay_dot_color(r):
    if not r.get("running"):
        return RED_DOT
    if _is_outdated(r):
        return YELLOW_DOT
    return GREEN_DOT

def _format_bw(bps):
    """Format Onionoo advertised_bandwidth (bytes/sec) compactly.
    8390000 → '8M'. Bytes/sec is what Onionoo reports; we keep that unit
    (Tor operators read in MB/s, not Mbit/s)."""
    if bps == None or bps <= 0:
        return "0"
    if bps >= 1000000000:
        return str(int(bps / 1000000000 + 0.5)) + "G"
    if bps >= 1000000:
        return str(int(bps / 1000000 + 0.5)) + "M"
    if bps >= 1000:
        return str(int(bps / 1000 + 0.5)) + "k"
    return str(int(bps + 0.5))

def _format_cw_frac(frac):
    """consensus_weight_fraction is the relay's share of the total network
    weight (0..1). Summed across a family gives the family's network share.
    Display as percent with magnitude-appropriate precision."""
    if frac == None or frac <= 0:
        return "0%"
    pct = frac * 100.0
    if pct >= 10.0:
        # XX.X
        scaled = int(pct * 10 + 0.5)
        whole = scaled // 10
        return str(whole) + "." + str(scaled - whole * 10) + "%"
    if pct >= 1.0:
        # X.XX
        scaled = int(pct * 100 + 0.5)
        whole = scaled // 100
        frac2 = scaled - whole * 100
        return str(whole) + "." + _truncate_or_pad(str(frac2), 2) + "%"
    if pct >= 0.01:
        # 0.XX
        scaled = int(pct * 100 + 0.5)
        whole = scaled // 100
        frac2 = scaled - whole * 100
        return str(whole) + "." + _truncate_or_pad(str(frac2), 2) + "%"
    return "<.01%"

def _truncate_or_pad(s, n):
    if len(s) > n:
        return s[:n]
    return s + ("0" * (n - len(s)))

def _kv_row(label, value):
    return render.Row(
        expanded = True,
        main_align = "space_between",
        cross_align = "center",
        children = [
            render.Text(label, color = FG_WHITE, font = "tom-thumb"),
            render.Text(value, color = FG_WHITE, font = "tom-thumb"),
        ],
    )

def _dots_row(relays):
    """One 4×4 colored square per relay, 1 px gap between. 7 dots fit in
    36 px; if a family grows past ~10 relays the row will overflow — that's
    a design question for v2."""
    children = []
    for r in relays:
        children.append(render.Padding(
            pad = (0, 0, 1, 0),
            child = render.Box(width = 4, height = 4, color = _relay_dot_color(r)),
        ))
    return render.Row(cross_align = "center", children = children)

def _big_tile(family_label, running, total, bg, fg):
    """Big tile: family identifier (first 4 hex chars of the fingerprint)
    on top in dark navy, big running/total count below in the category
    foreground. Vertical spacing via space_evenly distributes the ~11 px
    slack (32 - 8 tb-8 - 13 6x13) between the two children as top / between
    / bottom gaps."""
    count = str(running) + "/" + str(total)
    return render.Box(
        width = 28,
        height = 32,
        color = bg,
        child = render.Column(
            expanded = True,
            main_align = "space_evenly",
            cross_align = "center",
            children = [
                render.Text(family_label, color = FAMILY_LABEL_COLOR, font = "tb-8"),
                render.Text(count, color = fg, font = "6x13"),
            ],
        ),
    )

def _error_view(msg):
    return render.Root(
        child = render.Box(
            color = "#222222",
            child = render.Column(
                expanded = True,
                main_align = "center",
                cross_align = "center",
                children = [
                    render.Text(msg, color = FG_WHITE, font = "tom-thumb"),
                ],
            ),
        ),
    )

def _family_label(fp):
    """First 4 hex chars of the fingerprint, normalized. Strips a leading '$'
    (Tor's nickname-prefix convention) and upper-cases the result so the
    label is consistent regardless of how the fingerprint was pasted."""
    if fp == None:
        return "????"
    s = fp.lstrip("$")
    if len(s) < 4:
        return "?" * 4
    return s[:4].upper()

def main(config):
    fp = config.get("family_fingerprint", "")
    if not fp:
        return _error_view("NO FAMILY")

    relays = fetch_family(fp)
    if relays == None:
        return _error_view("TOR API ERR")
    if len(relays) == 0:
        return _error_view("NO RELAYS")

    running, total, total_bw, total_cwf, any_outdated = _aggregate(relays)
    bg, fg = _tile_colors(running, total, any_outdated)

    print("[compute] family=%s running=%d/%d bw=%s cw=%s any_outdated=%s" % (
        _family_label(fp), running, total,
        _format_bw(total_bw), _format_cw_frac(total_cwf), any_outdated,
    ))
    for r in relays:
        print("[compute] relay nickname=%s running=%s ver=%s bw=%s cwf=%s" % (
            r.get("nickname", "?"), r.get("running"), r.get("version_status"),
            r.get("advertised_bandwidth"), r.get("consensus_weight_fraction"),
        ))
    print("[render] tile_bg=%s family=%s" % (bg, _family_label(fp)))

    right_col = render.Padding(
        pad = (2, 0, 0, 0),
        child = render.Column(
            expanded = True,
            main_align = "space_evenly",
            children = [
                _kv_row("BW", _format_bw(total_bw)),
                _kv_row("CW", _format_cw_frac(total_cwf)),
                _dots_row(relays),
            ],
        ),
    )

    return render.Root(
        child = render.Box(
            color = "#000000",
            child = render.Row(
                expanded = True,
                children = [
                    _big_tile(_family_label(fp), running, total, bg, fg),
                    right_col,
                ],
            ),
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "family_fingerprint",
                name = "Tor relay family fingerprint",
                desc = "The 40-character SHA1 fingerprint of one relay in the family. Onionoo expands it to all family members.",
                icon = "fingerprint",
            ),
        ],
    )
