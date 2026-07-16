#!/usr/bin/env python3
"""Render selected signals from a VCD file as a clean SVG timing diagram.

Usage:
  python3 vcd2svg.py dump.vcd out.svg SIG1 SIG2 ... [--from T0] [--to T1] [--title "..."]

Signals are matched by the short name shown in the VCD ($var ... name).
1-bit signals draw as digital high/low; multi-bit signals draw as a bus with
hex values. Pure-stdlib; no dependencies.
"""
import sys, re

def parse_vcd(path):
    id2name, name2id, widths = {}, {}, {}
    tscale = "1ns"
    ts, changes = [], {}   # id -> list of (time, value)
    cur_t = 0
    with open(path) as f:
        in_dumps = False
        for line in f:
            line = line.strip()
            if not line: continue
            if line.startswith("$timescale"):
                m = re.search(r"\$timescale\s+(.*?)\s+\$end", line)
                if m: tscale = m.group(1).replace(" ", "")
            elif line.startswith("$var"):
                p = line.split()
                width, vid, name = int(p[2]), p[3], p[4]
                id2name.setdefault(vid, name); name2id[name] = vid
                widths[vid] = width; changes.setdefault(vid, [])
            elif line.startswith("#"):
                cur_t = int(line[1:]); ts.append(cur_t)
            elif line and (line[0] in "01xz"):
                val, vid = line[0], line[1:]
                if vid in changes: changes[vid].append((cur_t, val))
            elif line and line[0] in "bB":
                m = re.match(r"[bB]([01xz]+)\s+(\S+)", line)
                if m:
                    val, vid = m.group(1), m.group(2)
                    if vid in changes: changes[vid].append((cur_t, val))
    return name2id, widths, changes, ts, tscale

def val_at(seq, t):
    v = "x"
    for (tt, vv) in seq:
        if tt <= t: v = vv
        else: break
    return v

def bin2hex(b):
    if any(c in "xz" for c in b): return "x"
    return format(int(b, 2), "x")

def main():
    args = sys.argv[1:]
    vcd, out = args[0], args[1]
    sigs, t0, t1, title = [], None, None, "Waveform"
    i = 2
    while i < len(args):
        a = args[i]
        if a == "--from": t0 = int(args[i+1]); i += 2
        elif a == "--to": t1 = int(args[i+1]); i += 2
        elif a == "--title": title = args[i+1]; i += 2
        else: sigs.append(a); i += 1

    name2id, widths, changes, ts, tscale = parse_vcd(vcd)
    all_t = sorted(set(ts))
    if t0 is None: t0 = all_t[0]
    if t1 is None: t1 = all_t[-1]
    # sample points: only where a SELECTED signal changes (keeps the diagram
    # readable instead of drawing an edge at every clock tick), plus endpoints.
    sel_edges = set([t0, t1])
    for name in sigs:
        vid = name2id.get(name)
        if vid is None: continue
        for (tt, _vv) in changes[vid]:
            if t0 <= tt <= t1: sel_edges.add(tt)
    pts = sorted(sel_edges)

    # layout
    LABEL_W, ROW_H, ROW_GAP, TOP = 150, 34, 16, 44
    W = LABEL_W + 60 + (len(pts)-1) * 46
    W = max(W, LABEL_W + 400)
    span = (t1 - t0) or 1
    def x_of(t): return LABEL_W + 20 + (t - t0) / span * (W - LABEL_W - 40)
    H = TOP + len(sigs) * (ROW_H + ROW_GAP) + 20

    S = []
    S.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
             f'font-family="monospace" font-size="13">')
    S.append(f'<rect width="{W}" height="{H}" fill="#0d1117"/>')
    S.append(f'<text x="16" y="26" fill="#e6edf3" font-size="15" font-weight="bold">{title}</text>')

    for row, name in enumerate(sigs):
        y = TOP + row * (ROW_H + ROW_GAP)
        yb, yt = y + ROW_H, y            # bottom / top of the wave band
        vid = name2id.get(name)
        S.append(f'<text x="12" y="{y+ROW_H*0.65:.0f}" fill="#58a6ff">{name}</text>')
        if vid is None:
            S.append(f'<text x="{LABEL_W}" y="{y+ROW_H*0.65:.0f}" fill="#f85149">(not found)</text>')
            continue
        seq = changes[vid]; w = widths[vid]
        if w == 1:
            # digital line
            path = []
            prev = None
            for k, t in enumerate(pts):
                v = val_at(seq, t)
                yy = yt if v == "1" else yb
                x = x_of(t)
                if k == 0:
                    path.append(f"M {x:.1f} {yy:.1f}")
                else:
                    path.append(f"L {x:.1f} {prev_y:.1f} L {x:.1f} {yy:.1f}")
                prev_y = yy
            # extend to end
            path.append(f"L {x_of(t1):.1f} {prev_y:.1f}")
            S.append(f'<path d="{" ".join(path)}" fill="none" stroke="#3fb950" stroke-width="2"/>')
        else:
            # bus: draw hex value segments
            k = 0
            segs = []
            cur_start = pts[0]; cur_val = val_at(seq, pts[0])
            for t in pts[1:] + [t1]:
                v = val_at(seq, t)
                if v != cur_val or t == t1:
                    segs.append((cur_start, t, cur_val)); cur_start = t; cur_val = v
            for (a, b, v) in segs:
                xa, xb = x_of(a), x_of(b)
                mid = (xa + xb) / 2
                S.append(f'<path d="M {xa:.1f} {yt+4} L {xa+6:.1f} {(yt+yb)/2:.1f} '
                         f'L {xa:.1f} {yb-4} L {xb-6:.1f} {yb-4} L {xb:.1f} {(yt+yb)/2:.1f} '
                         f'L {xb-6:.1f} {yt+4} Z" fill="#1f6feb22" stroke="#58a6ff" stroke-width="1.5"/>')
                S.append(f'<text x="{mid:.1f}" y="{(yt+yb)/2+4:.0f}" fill="#e6edf3" '
                         f'text-anchor="middle">0x{bin2hex(v)}</text>')

    S.append('</svg>')
    open(out, "w").write("\n".join(S))
    print(f"wrote {out}  ({len(sigs)} signals, t={t0}..{t1} {tscale})")

if __name__ == "__main__":
    main()
