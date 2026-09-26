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
import hashlib
import io
import json
import os
import sys

# The verdict vocabulary. Every call gets exactly one.
# [REBUILT-2C low-confidence: verify] TASK-089 item A: the file-side vocabulary
# is written, not replayed (no recording carries a file-side field);
# REBUILT-2C-MANIFEST.md section 2c-8 (H-3).
VERDICT_FAILED = "failed"
VERDICT_OK_FILE_EFFECT = "ok_file_effect_observed"
VERDICT_OK_EFFECT = "ok_effect_observed"
VERDICT_OK_NO_EFFECT = "ok_no_effect_observed"
VERDICT_OK_UNAVAILABLE = "ok_effect_unavailable"
VERDICT_OK_UNOBSERVED = "ok_effect_not_observed"

# The file-side half of "did anything happen" (TASK-089 item A). `changed` and
# `mixed` mean the call really rewrote a destination on disk; `unchanged` means
# it went through a writer and the bytes are the same as before; `none` means it
# did not touch the disk at all. `not_recorded` is a trace written before the
# recorder existed, and `not_tracked` a call whose work happens after the
# response (the deferred channel) - both are declared absences, never read as
# "nothing changed".
FILE_EFFECT_CHANGED = "changed"
FILE_EFFECT_UNCHANGED = "unchanged"
FILE_EFFECT_MIXED = "mixed"
FILE_EFFECT_NONE = "none"
FILE_EFFECT_NOT_RECORDED = "not_recorded"
FILE_EFFECT_NOT_TRACKED = "not_tracked"

# The facts a row is reconstructible from. `capture` and `scene_evidence` are
# conditional: they are only knowable when capture was switched on. The same is
# true of `file_effect`: it is only knowable from a trace written by a build that
# carries the TASK-089 recorder. `error_data` (TASK-090 item A) is knowable from
# every new build - a failed call always carries the field, empty when the tool
# attached nothing - and is *not* knowable from a trace that predates it, which is
# exactly the distinction the fact is there to make.
FACTS = ("request_id", "tool", "args", "times", "result", "capture", "scene_evidence", "file_effect",
         "error_data")
# [/REBUILT-2C]


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


# ---------------------------------------------------------------------------
# TASK-092 (item B1): the sidecar of an over-bound payload.
#
# `args` (and the two bodies) are cropped at the trace's own byte bound, so a
# cropped payload used to be a fact nothing could reconstruct: the Pong session
# recorded `args_truncated: true` with `args_bytes: 9464`. The trace now names a
# file that holds the whole payload, with its byte count and its sha256, and this
# is the reader that **recomputes both** instead of trusting the line:
#
#   * `path` is tried first (the absolute original), then
#     `<trace dir>/<relative_path>` - the second one is what makes the evidence
#     survive the trace being copied to another machine;
#   * `verified` means the file exists, its sha256 matches the recorded one and
#     its size matches the recorded byte count. Anything else is reported as the
#     specific failure it is, never as "probably fine".
#
# The vocabulary mirrors `file_effect_evidence`: an absence is read as "this
# trace does not carry that evidence", never as "the payload was complete".
# ---------------------------------------------------------------------------
SIDECAR_INLINE = "inline_complete"
SIDECAR_VERIFIED = "sidecar_verified"
SIDECAR_MISSING = "sidecar_missing"
SIDECAR_MISMATCH = "sidecar_mismatch"
SIDECAR_TRUNCATED_NO_SIDECAR = "truncated_no_sidecar"
SIDECAR_ABSENT_FIELD = "sidecar_not_recorded_in_trace"


def _sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def sidecar_of(record, kind, truncated, trace_path):
    """(evidence, detail) for one bounded payload of one call.

    `kind` is the field prefix the trace uses: `args`, `result_json` or
    `error_data_json` (the sidecar object is `<kind>_sidecar`).
    """
    if not truncated:
        return SIDECAR_INLINE, {}
    entry = record.get(kind + "_sidecar")
    error = record.get(kind + "_sidecar_error")
    if isinstance(error, str) and error != "":
        return SIDECAR_TRUNCATED_NO_SIDECAR, {"sidecar_error": error}
    if not isinstance(entry, dict):
        return SIDECAR_ABSENT_FIELD, {}
    recorded_sha = entry.get("sha256")
    recorded_bytes = entry.get("bytes")
    candidates = []
    if isinstance(entry.get("path"), str) and entry["path"]:
        candidates.append(entry["path"])
    if isinstance(entry.get("relative_path"), str) and entry["relative_path"]:
        candidates.append(os.path.join(os.path.dirname(os.path.abspath(trace_path)), entry["relative_path"]))
    detail = {
        "path": entry.get("path"),
        "relative_path": entry.get("relative_path"),
        "recorded_bytes": recorded_bytes,
        "recorded_sha256": recorded_sha,
    }
    for candidate in candidates:
        if not os.path.isfile(candidate):
            continue
        detail["resolved_path"] = candidate
        actual_bytes = os.path.getsize(candidate)
        actual_sha = _sha256_file(candidate)
        detail["actual_bytes"] = actual_bytes
        detail["actual_sha256"] = actual_sha
        if actual_sha == (recorded_sha or "").upper() and actual_bytes == recorded_bytes:
            return SIDECAR_VERIFIED, detail
        detail["reason"] = "sha256 or byte count differs from the line"
        return SIDECAR_MISMATCH, detail
    detail["reason"] = "neither the absolute nor the relative path exists"
    return SIDECAR_MISSING, detail


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


def _file_effect_of(record):
    """(file status, detail) for one call, from the call line's own fields."""
    # [REBUILT-2C low-confidence: verify] TASK-089 item A: written, not replayed;
    # REBUILT-2C-MANIFEST.md section 2c-8 (H-3).
    status = record.get("file_effect_status")
    if not isinstance(status, str) or status == "":
        return FILE_EFFECT_NOT_RECORDED, {"status": None}
    rows = record.get("file_effects")
    if not isinstance(rows, list):
        rows = []
    changed = [r for r in rows if isinstance(r, dict) and r.get("changed") is True]
    unchanged = [r for r in rows if isinstance(r, dict) and r.get("changed") is not True]
    if status == "not_tracked_deferred":
        return FILE_EFFECT_NOT_TRACKED, {"status": status}
    if status == "no_mutation":
        return FILE_EFFECT_NONE, {"status": status, "rows": 0}
    if changed and unchanged:
        return FILE_EFFECT_MIXED, {"status": status, "rows": len(rows)}
    if changed:
        return FILE_EFFECT_CHANGED, {"status": status, "rows": len(rows)}
    return FILE_EFFECT_UNCHANGED, {"status": status, "rows": len(rows)}


def verdict_of(ok, scene, file_effect):
    if not ok:
        return VERDICT_FAILED
    # The file side is the stronger evidence: a call that really rewrote a
    # destination did something, whatever the screen did.
    if file_effect in (FILE_EFFECT_CHANGED, FILE_EFFECT_MIXED):
        return VERDICT_OK_FILE_EFFECT
    if scene == "changed":
        return VERDICT_OK_EFFECT
    if file_effect == FILE_EFFECT_UNCHANGED or scene == "unchanged":
        return VERDICT_OK_NO_EFFECT
    if scene == "unavailable":
        return VERDICT_OK_UNAVAILABLE
    return VERDICT_OK_UNOBSERVED


def result_flags(record):
    """The high-signal facts the tool's own body carries (TASK-089 F2/F3).

    A verdict of `ok` says the call was answered, not that what it asserted
    holds. Two shapes the round-7 session measured are turned into flags here so
    they are visible in the ledger instead of buried in the body:

      * `assertion_failed`   - the tool answered `passed: false`;
      * `created_conflict`   - the answer says `created: true` next to
                               `existed_before: true`, which cannot both be true;
      * `result_unparseable` - the body was truncated by the trace's own bound,
                               so no flag may be derived from it.
    """
    # [REBUILT-2C low-confidence: verify] TASK-089 F2/F3: written, not replayed;
    # REBUILT-2C-MANIFEST.md section 2c-8 (H-6).
    raw = record.get("result_json")
    if not isinstance(raw, str) or raw == "":
        return []
    try:
        body = json.loads(raw)
    except ValueError:
        return ["result_unparseable"]
    flags = []
    if isinstance(body, dict):
        if body.get("passed") is False:
            flags.append("assertion_failed")
        if body.get("created") is True and body.get("existed_before") is True:
            flags.append("created_conflict")
        # TASK-090 (item C, round-8 defect): a scenario driver answers with its
        # own summary (`all_passed` / `passed` / `failed` / `errors`) and nests a
        # verdict per assertion step in `results[]`. Without this the ledger
        # could not answer the question the scenario tools exist for - "did the
        # assertions hold" - because none of those keys is `passed: false` at the
        # top level.
        # [REBUILT-2C low-confidence: verify] TASK-090 item C: written, not
        # replayed; REBUILT-2C-MANIFEST.md section 2c-9 (J-3).
        if "all_passed" in body:
            if body.get("all_passed") is True:
                flags.append("scenario_passed")
            else:
                if int(body.get("errors") or 0) > 0:
                    flags.append("scenario_errors")
                if int(body.get("failed") or 0) > 0:
                    flags.append("scenario_assertion_failed")
                elif int(body.get("passed") or 0) == 0:
                    flags.append("scenario_asserted_nothing")
        # [/REBUILT-2C]
    return flags
# [/REBUILT-2C]

# TASK-090 (item A): the mirror image for a failure. `error_data_json` is the
# tool's own `data` payload (`suggestion`, `parse_error`), and the two flags below
# are what a reader looks for first: a next step to take, and a line to fix.
# [REBUILT-2C low-confidence: verify] TASK-090 item A: written, not replayed;
# REBUILT-2C-MANIFEST.md section 2c-9 (J-1).
def error_flags(record):
    if bool(record.get("ok")):
        return []
    if record.get("error_data_json_truncated"):
        return ["error_data_truncated"]
    raw = record.get("error_data_json")
    if not isinstance(raw, str) or raw == "":
        return []
    try:
        payload = json.loads(raw)
    except ValueError:
        return ["error_data_unparseable"]
    flags = []
    if isinstance(payload, dict):
        suggestion = payload.get("suggestion")
        if isinstance(suggestion, str) and suggestion != "":
            flags.append("error_suggestion")
        if isinstance(payload.get("parse_error"), dict):
            flags.append("error_parse_error")
    return flags


def error_data_of(record):
    """(payload, evidence) for the failure half of one call.

    Evidence is decidable because a build that carries the field writes it on
    *every* failed `tools/call` line, empty when nothing was attached: present =
    recorded, absent on a failure = a trace written before the field existed.
    """
    if bool(record.get("ok")):
        return None, "not_applicable"
    if "error_data_json" not in record:
        return None, "not_recorded_in_trace"
    raw = record.get("error_data_json")
    if not isinstance(raw, str) or raw == "":
        return None, "recorded_in_trace_no_payload"
    if record.get("error_data_json_truncated"):
        return None, "recorded_in_trace_truncated"
    try:
        return json.loads(raw), "recorded_in_trace"
    except ValueError:
        return None, "recorded_in_trace_unparseable"
# [/REBUILT-2C]


def row_for(record, capture_line, generation_index, trace_path):
    duration = record.get("duration_ms")
    ended = record.get("ts_ms")
    started = None
    if isinstance(duration, (int, float)) and isinstance(ended, (int, float)):
        started = ended - duration
    capture = record.get("capture") if isinstance(record.get("capture"), dict) else {}
    scene, scene_detail = _scene_of(record, capture_line)
    file_effect, file_detail = _file_effect_of(record)
    ok = bool(record.get("ok"))
    # [REBUILT-2C low-confidence: verify] TASK-090 item A: written, not replayed;
    # REBUILT-2C-MANIFEST.md section 2c-9 (J-1).
    error_payload, error_evidence = error_data_of(record)
    # [/REBUILT-2C]

    args = record.get("args")
    args_truncated = bool(record.get("args_truncated"))
    # TASK-092 (item B1): a cropped payload is reconstructible from the sidecar
    # the line names. `args_complete` is the fact the ledger now judges `args` by;
    # a crop with no verifiable sidecar stays incomplete, exactly as before.
    args_sidecar, args_sidecar_detail = sidecar_of(record, "args", args_truncated, trace_path)
    args_complete = args_sidecar in (SIDECAR_INLINE, SIDECAR_VERIFIED)
    result_sidecar, result_sidecar_detail = sidecar_of(
        record, "result_json", bool(record.get("result_json_truncated")), trace_path)
    error_sidecar, error_sidecar_detail = sidecar_of(
        record, "error_data_json", bool(record.get("error_data_json_truncated")), trace_path)
    facts = {
        "request_id": "id" in record,
        "tool": bool(record.get("tool")),
        "args": args is not None and args_complete,
        "times": started is not None,
        "result": "ok" in record and "error_code" in record,
        "capture": bool(capture),
        "scene_evidence": scene != "not_observed",
        "file_effect": file_effect not in (FILE_EFFECT_NOT_RECORDED, FILE_EFFECT_NOT_TRACKED),
        "error_data": error_evidence not in ("not_recorded_in_trace",),
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
        # TASK-092 (item B1): the read side of the sidecar rule. `args_complete`
        # is true when the payload is inline or when the file the line names was
        # found, re-hashed and re-measured here.
        "args_complete": args_complete,
        "args_evidence": args_sidecar,
        "args_sidecar": record.get("args_sidecar"),
        "args_sidecar_detail": args_sidecar_detail,
        "args_sidecar_error": record.get("args_sidecar_error"),
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
        # TASK-089 (item A): the file-side evidence the call line now carries.
        # This was the one declared gap in the model; the value is now read off
        # the trace instead of being a fixed "not_recorded_in_trace".
        "file_effect": file_effect,
        "file_effect_status": record.get("file_effect_status"),
        "file_effect_evidence": ("recorded_in_trace" if file_effect not in (FILE_EFFECT_NOT_RECORDED,)
                                 else "not_recorded_in_trace"),
        "file_effects": record.get("file_effects") if isinstance(record.get("file_effects"), list) else [],
        "file_effect_detail": file_detail,
        "result_json": record.get("result_json"),
        "result_json_bytes": record.get("result_json_bytes"),
        "result_json_truncated": bool(record.get("result_json_truncated")),
        # TASK-092 (item B1): the same read side for the two bodies. They do not
        # gate a fact today (`facts.result` is "the outcome is on the line"), but
        # a reader can now tell a cropped body from a complete one and can open
        # the whole body when it was cropped.
        "result_json_complete": result_sidecar in (SIDECAR_INLINE, SIDECAR_VERIFIED),
        "result_json_evidence": result_sidecar,
        "result_json_sidecar_detail": result_sidecar_detail,
        "result_flags": result_flags(record),
        # TASK-090 (item A): the failure payload, on the same row as the verdict
        # that says the call failed. `error_data_evidence` keeps "this build
        # records the payload" apart from "this trace predates the field".
        "error_data": error_payload,
        "error_data_json": record.get("error_data_json"),
        "error_data_json_bytes": record.get("error_data_json_bytes"),
        "error_data_json_truncated": bool(record.get("error_data_json_truncated")),
        "error_data_evidence": error_evidence,
        "error_data_complete": error_sidecar in (SIDECAR_INLINE, SIDECAR_VERIFIED),
        "error_data_sidecar_evidence": error_sidecar,
        "error_data_sidecar_detail": error_sidecar_detail,
        "error_flags": error_flags(record),
        "facts": facts,
        "facts_complete": all(facts.values()),
        "verdict": verdict_of(ok, scene, file_effect),
    }


def build(records, trace_path=""):
    rows = []
    for index, generation in enumerate(generations(records)):
        captures = {}
        for record in generation:
            if record.get("event") == "capture" and "seq" in record:
                captures[record["seq"]] = record
        for record in generation:
            if record.get("method") != "tools/call":
                continue
            rows.append(row_for(record, captures.get(record.get("seq")), index, trace_path))
    return rows


def render_text(rows, path, broken, args):
    counts = {}
    for row in rows:
        counts[row["verdict"]] = counts.get(row["verdict"], 0) + 1
    file_counts = {}
    for row in rows:
        file_counts[row["file_effect"]] = file_counts.get(row["file_effect"], 0) + 1
    lines = []
    lines.append("TRACE LEDGER %s" % path)
    lines.append("calls=%d malformed_lines=%d" % (len(rows), broken))
    lines.append("verdicts: " + (", ".join("%s=%d" % (k, counts[k]) for k in sorted(counts)) or "<none>"))
    lines.append("file_effects: " + (", ".join("%s=%d" % (k, file_counts[k]) for k in sorted(file_counts)) or "<none>"))
    lines.append("")
    header = ("%-6s %-8s %-38s %-9s %-8s %-8s %-14s %-15s %-26s %s" %
              ("seq", "req_id", "tool", "dur_ms", "ok", "err", "scene_effect", "file_effect", "flags", "verdict"))
    lines.append(header)
    lines.append("-" * len(header))
    for row in rows:
        if args.tool and row["tool"] != args.tool:
            continue
        if args.only_ineffective and row["verdict"] in (VERDICT_OK_EFFECT, VERDICT_OK_FILE_EFFECT, VERDICT_FAILED):
            continue
        flags = ",".join((row.get("result_flags") or []) + (row.get("error_flags") or [])) or "-"
        lines.append("%-6s %-8s %-38s %-9s %-8s %-8s %-14s %-15s %-26s %s" % (
            row["call_id"], row["request_id"],
            (row["tool"] or "")[:38], row["duration_ms"], row["ok"],
            row["error_code"], row["scene_effect"], row["file_effect"], flags[:26], row["verdict"]))
    complete = sum(1 for row in rows if row["facts_complete"])
    lines.append("")
    lines.append("rows whose reconstructible facts are all present: %d/%d" % (complete, len(rows)))

    # TASK-090 (item A): the failure payloads, in full (bounded per entry), so a
    # reader does not have to open the JSON to see the `suggestion` a refused call
    # carried - the whole point of putting `data` on the line.
    # [REBUILT-2C low-confidence: verify] TASK-090 item A: written, not replayed;
    # REBUILT-2C-MANIFEST.md section 2c-9 (J-1).
    payload_rows = [r for r in rows if (r.get("error_data_json") or "") != ""]
    lines.append("")
    lines.append("failure payloads (`error_data_json`) present on %d/%d call(s)"
                 % (len([r for r in rows if not r["ok"]]), len(rows)))
    for row in payload_rows:
        if args.tool and row["tool"] != args.tool:
            continue
        text = row.get("error_data_json") or ""
        if row.get("error_data_json_truncated"):
            text += " …[truncated, %s bytes]" % row.get("error_data_json_bytes")
        lines.append("  seq=%s req_id=%s %s err=%s | %s"
                     % (row["call_id"], row["request_id"], row["tool"], row["error_code"], text[:400]))
    evidence = {}
    for row in rows:
        evidence[row["error_data_evidence"]] = evidence.get(row["error_data_evidence"], 0) + 1
    lines.append("error_data_evidence: " + (", ".join("%s=%d" % (k, evidence[k]) for k in sorted(evidence)) or "<none>"))
    # [/REBUILT-2C]

    # TASK-092 (item B1): the sidecar half of the same question - was a cropped
    # payload reconstructible? The count is by evidence, and every row that named
    # a sidecar is listed with the answer this reader got by re-hashing the file.
    sidecar_counts = {}
    for row in rows:
        sidecar_counts[row["args_evidence"]] = sidecar_counts.get(row["args_evidence"], 0) + 1
    lines.append("args_evidence: " + (", ".join("%s=%d" % (k, sidecar_counts[k])
                                                for k in sorted(sidecar_counts)) or "<none>"))
    for row in rows:
        if row["args_evidence"] in (SIDECAR_INLINE, SIDECAR_ABSENT_FIELD) and not row.get("args_sidecar"):
            continue
        if args.tool and row["tool"] != args.tool:
            continue
        detail = row.get("args_sidecar_detail") or {}
        lines.append("  seq=%s req_id=%s %s args_evidence=%s recorded=%s/%s actual=%s/%s path=%s" % (
            row["call_id"], row["request_id"], row["tool"], row["args_evidence"],
            detail.get("recorded_bytes"), (detail.get("recorded_sha256") or "")[:12],
            detail.get("actual_bytes"), (detail.get("actual_sha256") or "")[:12],
            detail.get("resolved_path") or detail.get("path") or row.get("args_sidecar_error")))
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

    rows = build(records, args.trace)
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
