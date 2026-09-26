#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mcp_trace_ledger.py -- one row per tool call: was this operation, and was it
effective?

`--mcp-trace=<path>` already records the raw facts of every JSON-RPC request
(TASK-038) and, with `--mcp-capture=<mode>`, the before/after pictures and the
pixel comparison of a tool call (TASK-044). What no reader did is turn those
records into the question an operator actually asks: *this call answered `ok` -
did anything happen?* `analyze_mcp_trace.py` answers aggregate questions
(friction, n-grams, missing tools, anomalously large responses); this file
answers the per-call one, and it states exactly which of the facts a call is
reconstructible from are present, so a gap is visible instead of implied.

The model, the field list and the verdict rules are specified in
`docs/reports/MCP-TRACEABILITY.md`; this script is that specification made
executable.

Usage:
    python scripts/mcp_trace_ledger.py <trace.jsonl> [--json OUT] [--text OUT]
                                       [--tool NAME] [--only-ineffective]

Exit 0 when the file was read (whatever the verdicts), 2 on a usage/IO error.
"""
import argparse
import io
import json
import sys

# The verdict vocabulary. Every call gets exactly one.
VERDICT_FAILED = "failed"
VERDICT_OK_EFFECT = "ok_effect_observed"
VERDICT_OK_NO_EFFECT = "ok_no_effect_observed"
VERDICT_OK_UNAVAILABLE = "ok_effect_unavailable"
VERDICT_OK_UNOBSERVED = "ok_effect_not_observed"

# The facts a row is reconstructible from. `capture` and `scene_evidence` are
# conditional: they are only knowable when capture was switched on.
FACTS = ("request_id", "tool", "args", "times", "result", "capture", "scene_evidence")


def load(path):
    records = []
    broken = 0
    with io.open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                broken += 1
                continue
            if isinstance(obj, dict):
                records.append(obj)
            else:
                broken += 1
    return records, broken


def generations(records):
    """Split on `trace_opened`: `seq` is only comparable inside one generation."""
    out = []
    current = []
    for record in records:
        if record.get("event") == "trace_opened":
            if current:
                out.append(current)
            current = [record]
            continue
        current.append(record)
    if current:
        out.append(current)
    return out


def _scene_of(record, capture_line):
    """(scene status, detail) for one call."""
    if capture_line is not None:
        changed = capture_line.get("changed")
        detail = {
            "before_path": (capture_line.get("before") or {}).get("path"),
            "after_path": (capture_line.get("after") or {}).get("path"),
            "before_sha256": (capture_line.get("before") or {}).get("sha256"),
            "after_sha256": (capture_line.get("after") or {}).get("sha256"),
            "before_bytes": (capture_line.get("before") or {}).get("bytes"),
            "after_bytes": (capture_line.get("after") or {}).get("bytes"),
            "width": (capture_line.get("after") or {}).get("width"),
            "height": (capture_line.get("after") or {}).get("height"),
            "scale": capture_line.get("scale"),
            "frames_waited": capture_line.get("frames_waited"),
            "changed": changed,
            "changed_pixels": capture_line.get("changed_pixels"),
            "total_pixels": capture_line.get("total_pixels"),
            "changed_pixel_ratio": capture_line.get("changed_pixel_ratio"),
            "diff_path": (capture_line.get("diff") or {}).get("path"),
            "capture_status": capture_line.get("status"),
        }
        if changed is True:
            return "changed", detail
        if changed is False:
            return "unchanged", detail
        return "unavailable", detail
    capture = record.get("capture")
    if isinstance(capture, dict) and capture.get("status") == "unavailable":
        return "unavailable", {"capture_status": "unavailable", "reason": capture.get("reason")}
    return "not_observed", {}


def verdict_of(ok, scene):
    if not ok:
        return VERDICT_FAILED
    if scene == "changed":
        return VERDICT_OK_EFFECT
    if scene == "unchanged":
        return VERDICT_OK_NO_EFFECT
    if scene == "unavailable":
        return VERDICT_OK_UNAVAILABLE
    return VERDICT_OK_UNOBSERVED


def row_for(record, capture_line, generation_index):
    duration = record.get("duration_ms")
    ended = record.get("ts_ms")
    started = None
    if isinstance(duration, (int, float)) and isinstance(ended, (int, float)):
        started = ended - duration
    capture = record.get("capture") if isinstance(record.get("capture"), dict) else {}
    scene, scene_detail = _scene_of(record, capture_line)
    ok = bool(record.get("ok"))

    args = record.get("args")
    args_truncated = bool(record.get("args_truncated"))
    facts = {
        "request_id": "id" in record,
        "tool": bool(record.get("tool")),
        "args": args is not None and not args_truncated,
        "times": started is not None,
        "result": "ok" in record and "error_code" in record,
        "capture": bool(capture),
        "scene_evidence": scene != "not_observed",
    }
    return {
        "generation": generation_index,
        "call_id": record.get("seq"),
        "request_id": record.get("id"),
        "connection": record.get("connection"),
        "tool": record.get("tool"),
        "args": args,
        "args_bytes": record.get("args_bytes"),
        "args_truncated": args_truncated,
        "started_ts_ms": started,
        "ended_ts_ms": ended,
        "duration_ms": duration,
        "ok": ok,
        "error_code": record.get("error_code"),
        "error_message": record.get("error_message"),
        "result_bytes": record.get("result_bytes"),
        "capture_mode": capture.get("mode"),
        "capture_viewport": capture.get("viewport"),
        "capture_status": capture.get("status"),
        "capture_reason": capture.get("reason"),
        "scene_effect": scene,
        "scene_evidence": scene_detail,
        # The runtime trace carries scene-side evidence only. A file the call
        # wrote is *not* recorded here; the honest value is a declared absence,
        # not an empty success. See MCP-TRACEABILITY.md section 4.
        "file_effect_evidence": "not_recorded_in_trace",
        "facts": facts,
        "facts_complete": all(facts.values()),
        "verdict": verdict_of(ok, scene),
    }


def build(records):
    rows = []
    for index, generation in enumerate(generations(records)):
        captures = {}
        for record in generation:
            if record.get("event") == "capture" and "seq" in record:
                captures[record["seq"]] = record
        for record in generation:
            if record.get("method") != "tools/call":
                continue
            rows.append(row_for(record, captures.get(record.get("seq")), index))
    return rows


def render_text(rows, path, broken, args):
    counts = {}
    for row in rows:
        counts[row["verdict"]] = counts.get(row["verdict"], 0) + 1
    lines = []
    lines.append("TRACE LEDGER %s" % path)
    lines.append("calls=%d malformed_lines=%d" % (len(rows), broken))
    lines.append("verdicts: " + (", ".join("%s=%d" % (k, counts[k]) for k in sorted(counts)) or "<none>"))
    lines.append("")
    header = ("%-6s %-8s %-38s %-9s %-8s %-8s %-22s %s" %
              ("seq", "req_id", "tool", "dur_ms", "ok", "err", "scene_effect", "verdict"))
    lines.append(header)
    lines.append("-" * len(header))
    for row in rows:
        if args.tool and row["tool"] != args.tool:
            continue
        if args.only_ineffective and row["verdict"] in (VERDICT_OK_EFFECT, VERDICT_FAILED):
            continue
        lines.append("%-6s %-8s %-38s %-9s %-8s %-8s %-22s %s" % (
            row["call_id"], row["request_id"],
            (row["tool"] or "")[:38], row["duration_ms"], row["ok"],
            row["error_code"], row["scene_effect"], row["verdict"]))
    complete = sum(1 for row in rows if row["facts_complete"])
    lines.append("")
    lines.append("rows whose reconstructible facts are all present: %d/%d" % (complete, len(rows)))
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description="One traceability row per tool call.")
    parser.add_argument("trace")
    parser.add_argument("--json", default=None)
    parser.add_argument("--text", default=None)
    parser.add_argument("--tool", default=None)
    parser.add_argument("--only-ineffective", action="store_true")
    args = parser.parse_args(argv)

    try:
        records, broken = load(args.trace)
    except IOError as exc:
        sys.stderr.write("mcp_trace_ledger: cannot read %s: %s\n" % (args.trace, exc))
        return 2

    rows = build(records)
    text = render_text(rows, args.trace, broken, args)
    sys.stdout.write(text)
    if args.text:
        io.open(args.text, "w", encoding="utf-8", newline="\n").write(text)
        sys.stdout.write("wrote %s\n" % args.text)
    if args.json:
        payload = {
            "trace": args.trace,
            "calls": len(rows),
            "malformed_lines": broken,
            "rows": rows,
        }
        io.open(args.json, "w", encoding="utf-8", newline="\n").write(
            json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
        sys.stdout.write("wrote %s\n" % args.json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
