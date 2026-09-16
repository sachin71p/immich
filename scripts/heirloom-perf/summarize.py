#!/usr/bin/env python3
"""summarize.py — Markdown perf summary of an heirloom-perf Instruments trace.

Usage: summarize.py <trace>

Exports the `potential-hangs`, `time-profile` and `os-signpost` tables via
`xcrun xctrace export`, resolves the export's id/ref deduplication, and prints:
  - hang count, total duration and worst hang;
  - top 20 main-thread inclusive frames owned by Heirloom/PhotosCore;
  - signpost interval stats (count/p50/p95/max per name).

Approach mirrors the 04-baseline-profile.md analysis: 1 ms Running samples on
the main thread, inclusive attribution per frame, owned-code filter on the
Heirloom app binary (PhotosCore links statically into it).
"""

import math
import os
import statistics
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True, check=False)


def table_indexes(trace):
    """Map schema name -> [1-based table indexes] from the trace TOC.

    Why positional: the TOC lists tables as ordered children of run/data with
    no index attribute, so the Nth <table> is table[N] in export xpaths.
    """
    r = sh("xcrun", "xctrace", "export", trace, "--toc")
    if r.returncode != 0:
        raise SystemExit(f"error: xctrace --toc failed:\n{r.stderr}")
    indexes = {}
    root = ET.fromstring(r.stdout)
    run = root.find("run")
    data = run.find("data") if run is not None else None
    tables = data.findall("table") if data is not None else list(root.iter("table"))
    for n, tbl in enumerate(tables, 1):
        indexes.setdefault(tbl.attrib.get("schema"), []).append(n)
    return indexes


def export_table(trace, index, outpath):
    r = sh(
        "xcrun", "xctrace", "export", trace,
        "--xpath", f"//trace-toc[1]/run[1]/data[1]/table[{index}]",
        "--output", outpath,
    )
    if r.returncode != 0:
        raise SystemExit(f"error: xctrace export of table {index} failed:\n{r.stderr}")


def row_cells(row, fmt_by_id):
    """Yield (tag, text, fmt) for a row's cells, resolving ref dedup.

    Why manual: xctrace emits each distinct string once (`id` + `fmt`) and
    later rows reference it (`ref`), so naive text reads see empty cells.
    """
    for cell in list(row):
        ref = cell.attrib.get("ref")
        if ref is not None:
            yield cell.tag, "", fmt_by_id.get(ref, "")
            continue
        cid = cell.attrib.get("id")
        fmt = cell.attrib.get("fmt", cell.text or "")
        if cid is not None:
            fmt_by_id[cid] = fmt
        yield cell.tag, (cell.text or ""), fmt


def parse_hangs(path):
    fmt_by_id = {}
    hangs = []
    tree = ET.parse(path)
    for row in tree.getroot().iter("row"):
        cells = dict((tag, (text, fmt)) for tag, text, fmt in row_cells(row, fmt_by_id))
        try:
            dur_ns = int(cells["duration"][0])
        except (KeyError, ValueError):
            continue
        start = cells.get("start-time", ("", ""))[1]
        dur_fmt = cells.get("duration", ("", ""))[1]
        htype = cells.get("hang-type", ("", ""))[1]
        hangs.append((start, dur_ns / 1e9, dur_fmt, htype))
    return hangs


def is_main_thread(thread_fmt):
    return "Main Thread" in thread_fmt


def is_owned(binary_name):
    # PhotosCore links statically into the app binary, so one check covers both.
    return "heirloom" in (binary_name or "").lower()


def parse_time_profile(path):
    """Stream rows (the export is tens of MB with inline backtraces).

    Returns (main_running_samples, owned_inclusive) where owned_inclusive maps
    (binary, frame) -> inclusive sample count on the main thread.
    """
    fmt_by_id = {}
    stacks_by_id = {}
    binaries_by_id = {}
    frames_by_id = {}
    main_samples = 0
    owned = {}
    context = ET.iterparse(path, events=("end",))
    for _, elem in context:
        if elem.tag != "row":
            continue
        thread_fmt = ""
        state = ""
        backtrace = None
        for cell in list(elem):
            if cell.tag == "thread":
                ref = cell.attrib.get("ref")
                if ref is not None:
                    thread_fmt = fmt_by_id.get(ref, "")
                else:
                    thread_fmt = cell.attrib.get("fmt", "")
                    if cell.attrib.get("id"):
                        fmt_by_id[cell.attrib["id"]] = thread_fmt
            elif cell.tag == "thread-state":
                # Like threads, states dedup via id/ref with empty text.
                ref = cell.attrib.get("ref")
                if ref is not None:
                    state = fmt_by_id.get(ref, "")
                else:
                    state = (cell.text or "") or cell.attrib.get("fmt", "")
                    if cell.attrib.get("id"):
                        fmt_by_id[cell.attrib["id"]] = state
            elif cell.tag == "tagged-backtrace":
                ref = cell.attrib.get("ref")
                if ref is not None:
                    backtrace = stacks_by_id.get(ref)
                else:
                    frames = []
                    for fr in cell.iter("frame"):
                        # Frames dedup via id/ref; only the first occurrence
                        # carries name/addr plus the nested binary element.
                        if fr.attrib.get("ref") is not None:
                            key = frames_by_id.get(fr.attrib["ref"])
                            if key is not None:
                                frames.append(key)
                            continue
                        name = fr.attrib.get("name", "")
                        # Binaries dedup via id/ref like everything else.
                        b = fr.find("binary")
                        bname = ""
                        if b is not None:
                            if b.attrib.get("ref") is not None:
                                bname = binaries_by_id.get(b.attrib["ref"], "")
                            else:
                                bname = b.attrib.get("name", "")
                                if b.attrib.get("id"):
                                    binaries_by_id[b.attrib["id"]] = bname
                        key = (bname, name)
                        if fr.attrib.get("id"):
                            frames_by_id[fr.attrib["id"]] = key
                        frames.append(key)
                    backtrace = frames
                    if cell.attrib.get("id"):
                        stacks_by_id[cell.attrib["id"]] = frames
        # Only on-CPU samples drive the hot-frame ranking (matches the
        # baseline doc's "Running samples only" convention).
        if state == "Running" and is_main_thread(thread_fmt) and backtrace:
            main_samples += 1
            for key in set(backtrace):  # inclusive: one credit per frame per sample
                if is_owned(key[0]):
                    owned[key] = owned.get(key, 0) + 1
        elem.clear()
    return main_samples, owned


def parse_signpost_intervals(paths):
    """OSSignpostIntervals rows carry start + duration + name directly."""
    fmt_by_id = {}
    durations = {}
    for path in paths:
        tree = ET.parse(path)
        for row in tree.getroot().iter("row"):
            cells = dict((tag, (text, fmt)) for tag, text, fmt in row_cells(row, fmt_by_id))
            try:
                dur_ns = int(cells["duration"][0])
            except (KeyError, ValueError):
                continue
            name = (
                cells.get("signpost-name", ("", ""))[1]
                or cells.get("signpost-name", ("", ""))[0]
                or cells.get("name", ("", ""))[1]
                or cells.get("name", ("", ""))[0]
            )
            durations.setdefault(name or "(unnamed)", []).append(dur_ns / 1e9)
    return durations


def parse_signpost_events(paths):
    """Fallback: pair os-signpost begin/end events by identifier."""
    fmt_by_id = {}
    begins = {}
    durations = {}
    for path in paths:
        tree = ET.parse(path)
        for row in tree.getroot().iter("row"):
            cells = dict((tag, (text, fmt)) for tag, text, fmt in row_cells(row, fmt_by_id))
            try:
                ts = int(cells["time"][0])
            except (KeyError, ValueError):
                continue
            etype = cells.get("event-type", ("", ""))[1].lower()
            ident = cells.get("identifier", ("", ""))[0] or cells.get("identifier", ("", ""))[1]
            name = (
                cells.get("signpost-name", ("", ""))[1]
                or cells.get("signpost-name", ("", ""))[0]
                or cells.get("name", ("", ""))[1]
                or cells.get("name", ("", ""))[0]
            )
            if "begin" in etype:
                begins[ident] = (ts, name)
            elif "end" in etype and ident in begins:
                start, bname = begins.pop(ident)
                durations.setdefault(bname or name or "(unnamed)", []).append((ts - start) / 1e9)
    return durations


def pct(q, data):
    if not data:
        return 0.0
    s = sorted(data)
    return s[min(len(s) - 1, int(math.ceil(q * len(s))) - 1)]


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: summarize.py <trace>")
    trace = sys.argv[1]
    if not os.path.exists(trace):
        raise SystemExit(f"error: no such trace: {trace}")

    indexes = table_indexes(trace)
    tmp = tempfile.mkdtemp(prefix="heirloom-perf-")

    out = [f"# Perf summary: {os.path.basename(trace)}", ""]

    # --- Hangs ---
    hangs = []
    for i in indexes.get("potential-hangs", [])[:1]:
        p = os.path.join(tmp, "hangs.xml")
        export_table(trace, i, p)
        hangs = parse_hangs(p)
    total = sum(d for _, d, _, _ in hangs)
    worst = max((d for _, d, _, _ in hangs), default=0.0)
    out.append(f"## Hangs: {len(hangs)} total, {total:.2f} s combined, worst {worst:.2f} s")
    out.append("")
    out.append("| Start | Duration | Type |")
    out.append("|---|---|---|")
    for start, _, dur_fmt, htype in hangs:
        out.append(f"| {start} | {dur_fmt} | {htype} |")
    if not hangs:
        out.append("| — | no hangs recorded | — |")
    out.append("")

    # --- Time profile ---
    main_samples = 0
    owned = {}
    for i in indexes.get("time-profile", [])[:1]:
        p = os.path.join(tmp, "time-profile.xml")
        export_table(trace, i, p)
        main_samples, owned = parse_time_profile(p)
    out.append(f"## Main thread: {main_samples} Running samples (~{main_samples / 1000:.2f} s on-CPU)")
    out.append("")
    out.append("| Samples | % main | Frame (binary) |")
    out.append("|---|---|---|")
    # Skip process-entry frames: they nest every sample (cf. the baseline doc,
    # which likewise starts its owned table below the runloop/entry baseline).
    def is_entry(frame_name):
        return frame_name in ("main", "__debug_main_executable_dylib_entry_point") or "$main" in frame_name

    top = [kv for kv in sorted(owned.items(), key=lambda kv: -kv[1]) if not is_entry(kv[0][1])][:20]
    for (bname, fname), n in top:
        share = 100.0 * n / main_samples if main_samples else 0.0
        out.append(f"| {n} | {share:.1f}% | `{fname}` ({bname}) |")
    if not top:
        out.append("| — | no Heirloom-owned main-thread frames sampled | — |")
    out.append("")

    # --- Signposts ---
    # Prefer OSSignpostIntervals (start/duration/name per row); fall back to
    # pairing os-signpost begin/end events when the template omits it.
    durations = {}
    ipaths = []
    for n, i in enumerate(indexes.get("OSSignpostIntervals", [])):
        p = os.path.join(tmp, f"interval-{n}.xml")
        export_table(trace, i, p)
        ipaths.append(p)
    if ipaths:
        durations = parse_signpost_intervals(ipaths)
    if not durations:
        spaths = []
        for n, i in enumerate(indexes.get("os-signpost", [])):
            p = os.path.join(tmp, f"signpost-{n}.xml")
            export_table(trace, i, p)
            spaths.append(p)
        if spaths:
            durations = parse_signpost_events(spaths)
    out.append("## Signpost intervals (HeirloomSignpost names)")
    out.append("")
    out.append("| Name | Count | p50 | p95 | Max |")
    out.append("|---|---|---|---|---|")
    for name in sorted(durations):
        d = durations[name]
        out.append(
            f"| {name} | {len(d)} | {pct(0.50, d):.3f} s "
            f"| {pct(0.95, d):.3f} s | {max(d):.3f} s |"
        )
    if not durations:
        out.append("| — | no signpost intervals recorded (app has no signposts yet, or none fired) | — |")
    out.append("")

    print("\n".join(out))


if __name__ == "__main__":
    main()
