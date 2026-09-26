#!/usr/bin/env python
"""Analyse an MCP server call trace (`--mcp-trace=<path>`, TASK-038).

Input is the JSON Lines file the module writes when the trace is enabled: one
JSON object per JSON-RPC request, with the facts the *server* observed (method,
tool, arguments, outcome, error code, wall times, response size).

The observer's question is never "did it work", it is "what friction did the
caller hit on the way, and what does that say about the tool surface". This
script answers it with four groups of signals:

  * friction        - a tool that failed and then succeeded (the caller had to
                      find the right shape), the same tool called twice with the
                      same arguments, the error code distribution;
  * missing tools   - a tool name that does not exist (-32601), and argument
                      names that were probed repeatedly and never accepted,
                      split into two buckets against the contract's published
                      `inputSchema` (TASK-077 D-B3): the names the failing tool
                      does NOT declare, and the names it DOES declare - the
                      second half is not evidence of a missing parameter, the
                      call failed for some other reason;
  * mergeable calls - the frequent 2- and 3-step tool sequences (candidates for
                      a single tool that does the whole sequence);
  * anomalies       - a deferred wait that hit its own ceiling, an abnormally
                      large response, one tool dominating the session.

TASK-054 (O-11 / O-12) tightened three of those signals and made the file
segmented:

  * the file is **append-only across runs**, so a `trace_opened` event line
    (`{"event":"trace_opened","pid":...,"mcp_port":...}`) written by every
    process marks where a generation begins. Sessions, episode windows and
    n-grams never cross one, and `seq` is only comparable inside one
    (it restarts at 1 in every new process);
  * "fail then succeed" needs the *same tool*, the *same connection* and **no
    other tool call in between** - otherwise an unrelated call that happened to
    fall inside the window reads as one episode of learning;
  * the diagnostics' own side channel is not session traffic: capture event
    lines (`event:"capture"`) and the full `tools/list` dump are excluded from
    the "abnormally large response" and "one tool dominates" verdicts, and event
    lines are not tool calls at all.

Output is a human readable summary plus a JSON document (`--json <path>` writes
the JSON there, default is to print it after the summary).

Usage:
    python analyze_mcp_trace.py <trace.jsonl> [--json out.json] [--quiet]
"""

from __future__ import annotations

import argparse
import collections
import json
import sys

# The large-response warning line: a single answer that is bigger than this is
# worth a look (it is usually an unbounded listing).
DEFAULT_MAX_RESULT_BYTES = 1 << 20  # 1 MiB
# A single tool taking more than this share of the session is reported: the
# caller is probably working around the tool surface (or looping).
DEFAULT_DOMINANCE = 0.30
# A "fail then succeed" pair further apart than this many calls is not read as
# the same episode of learning.
DEFAULT_EPISODE_WINDOW = 12
# Argument names probed at least this many times and never accepted.
DEFAULT_PROBE_MIN = 2

# TASK-054 (O-12): the event line every process writes when it opens the trace
# file. It is the only generation boundary a file carries.
GENERATION_EVENT = "trace_opened"
# TASK-054 (O-11): the capture extension's side-channel line (GDR-27 / TASK-044)
# shares the file but is not a request.
CAPTURE_EVENT = "capture"


def load(path):
    """Reads the JSON Lines file. A malformed line is reported, never fatal."""
    records = []
    bad_lines = []
    with open(path, "r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                value = json.loads(line)
            except ValueError as exc:
                bad_lines.append({"line": number, "error": str(exc)})
                continue
            if not isinstance(value, dict):
                bad_lines.append({"line": number, "error": "not a JSON object"})
                continue
            records.append(value)
    return records, bad_lines


def is_event_line(record):
    """True for a side-channel line: no `method`, no `seq` of its own."""
    return bool(record.get("event"))


def is_capture_line(record):
    return record.get("event") == CAPTURE_EVENT


def is_tools_list(record):
    """The full contract dump. It is a diagnostic bypass, never a workflow."""
    return record.get("method") == "tools/list" or record.get("is_tools_list") is True


def generation_of(records):
    """The generation index of every record, in file order (TASK-054 / O-12).

    A `trace_opened` line opens generation 1; the lines before the first one
    belong to generation 0, which is what a trace written by a pre-TASK-054
    binary (or one whose head was truncated) looks like: one generation, and
    every signal still computed.
    """
    generations = []
    current = 0
    for record in records:
        if record.get("event") == GENERATION_EVENT:
            current += 1
        generations.append(current)
    return generations


def generation_report(records, generations):
    """One entry per generation, so the segmentation is visible, not implied."""
    by_generation = collections.OrderedDict()
    for index, record in enumerate(records):
        entry = by_generation.setdefault(generations[index], {
            "generation": generations[index],
            "opened": None,
            "records": 0,
            "tool_calls": 0,
            "connections": set(),
            "first_seq": None,
            "last_seq": None,
        })
        entry["records"] += 1
        if record.get("event") == GENERATION_EVENT:
            entry["opened"] = record
            continue
        if record.get("method") == "tools/call":
            entry["tool_calls"] += 1
        seq = record.get("seq")
        if seq is not None:
            if entry["first_seq"] is None:
                entry["first_seq"] = seq
            entry["last_seq"] = seq
        if record.get("connection") is not None:
            entry["connections"].add(record.get("connection"))
    out = []
    for entry in by_generation.values():
        entry["connections"] = sorted(entry["connections"], key=lambda value: str(value))
        out.append(entry)
    return out


def session_keys(records, generations):
    """What "one session" means for this file: `(generation, connection)`.

    TASK-054 (O-11): the n-gram and friction signals are only meaningful inside
    one session, but `connection` is not always a session *key*. The audit
    measured the case that matters (`REPORT-AUDIT-RACING-BACKLOG` section 5.11):
    a harness that issues one request per invocation opens a **new connection per
    call** (`connection = 2..9, every entry different`), so bucketing by
    connection leaves every bucket with one entry and the n-grams are
    *structurally* empty - which is exactly the defect that was filed.

    The audit's fix (2) covers it: "when every bucket has a single entry, declare
    the degeneration and cluster by file order / `ts_ms` instead". So a
    generation whose tool calls all sit on distinct connections uses the
    generation alone as the key (file order within it is the session order), and
    the degeneration is reported rather than hidden. A client that keeps its
    connection open - the real MCP case - still gets the strict key.

    Returns `(keys, degenerate_generations)`, `keys` aligned with `records`.
    """
    per_generation = collections.OrderedDict()
    for index, record in enumerate(records):
        if record.get("method") != "tools/call" or is_event_line(record):
            continue
        entry = per_generation.setdefault(generations[index], [])
        entry.append(record.get("connection"))

    degenerate = set()
    for generation, connections in per_generation.items():
        distinct = {str(value) for value in connections}
        if len(connections) > 1 and len(distinct) == len(connections):
            degenerate.add(generation)

    keys = []
    for index, record in enumerate(records):
        generation = generations[index]
        if generation in degenerate:
            keys.append((generation,))
        else:
            keys.append((generation, record.get("connection")))
    return keys, sorted(degenerate)


def canonical_args(record):
    """A stable string for 'the same arguments'."""
    return json.dumps(record.get("args"), sort_keys=True, ensure_ascii=False)


def call_args(record):
    """The argument object of one call, or `None` when it cannot be read.

    TASK-075 (D11 / the round-5 findings' OP2): the trace writes `args` as a JSON
    **string** (one of the module's measured shapes - the round-5 trace has
    `args` as `str` in 198 of 198 calls), and this analyser used to test
    `isinstance(args, dict)` only. That test is False for every real call, so the
    whole `probed_argument_names` signal - "the caller kept naming an argument the
    tool does not have" - was structurally empty and reported as `probed args
    none`. Both spellings are accepted here, and a string that is not a JSON
    object is reported as *unreadable* rather than silently treated as "no
    arguments" (see `missing_tools`).
    """
    args = record.get("args")
    if isinstance(args, dict):
        return args
    if isinstance(args, str):
        try:
            parsed = json.loads(args)
        except ValueError:
            return None
        return parsed if isinstance(parsed, dict) else None
    return None


def calls(records):
    """The `tools/call` records, in file order (which is what `seq` orders).

    TASK-054 (O-11): an event line (`trace_opened` / `capture`) shares the file
    but is not a request, so it is never a tool call - counting one would put a
    second `tool` field next to the call it merely describes.
    """
    return [r for r in records if r.get("method") == "tools/call" and not is_event_line(r)]


def friction(records, window):
    """Fail-then-success episodes, repeated calls and the error distribution.

    TASK-054 (O-11) rewrote the first signal. The old rule was "the same tool
    reached a successful call within the next `window` calls", which counts two
    calls that are not one episode at all:

      * a *different* tool ran in between - the caller moved on, the later
        success belongs to another attempt, not to learning this one's shape;
      * the two calls sit on different connections or in different generations
        (different runs of the process) - they are not one workflow at all.

    A pair now needs the same tool, the same connection, the same generation,
    and no other tool call in between.
    """
    generations = generation_of(records)
    keys, degenerate = session_keys(records, generations)
    tool_calls = [
        (index, record, keys[index])
        for index, record in enumerate(records)
        if record.get("method") == "tools/call" and not is_event_line(record)
    ]
    result = {
        "fail_then_success": [],
        "repeated_same_args": [],
        "error_code_distribution": {},
        "error_code_by_tool": {},
        "session_keys": {
            "kind": "generation+connection",
            "degenerate_generations": degenerate,
            "note": ("generation alone is the session key in these generations: every tool call opened its own "
                     "connection, so a connection equality test would reject every pair (the audit's measured case)"),
        },
    }

    # --- fail then success ------------------------------------------------
    # A failure is only "friction the caller worked through" when the same tool
    # later answers a *successful* call. The pair is reported with the failing
    # arguments, so the reader can see which shape was wrong.
    for position, (_, record, record_key) in enumerate(tool_calls):
        if record.get("ok", True):
            continue
        tool = record.get("tool", "")
        for later_position in range(position + 1, min(position + 1 + window, len(tool_calls))):
            _, later, later_key = tool_calls[later_position]
            # A new session ends the episode: another process (a new generation,
            # where `seq` restarts) or another connection...
            if later_key != record_key:
                break
            # ...and a different tool means the caller moved on: a later success
            # of this tool is a *new* attempt, not the resolution of this one.
            if later.get("tool", "") != tool:
                break
            if not later.get("ok", False):
                continue
            result["fail_then_success"].append({
                "tool": tool,
                "session": list(record_key),
                "failed_seq": record.get("seq"),
                "failed_error_code": record.get("error_code"),
                "failed_error_message": record.get("error_message", ""),
                "failed_args": record.get("args"),
                "failed_args_truncated": record.get("args_truncated", False),
                "succeeded_seq": later.get("seq"),
                "succeeded_args": later.get("args"),
                "calls_apart": (later_position - position),
            })
            break

    # --- the same tool with the same arguments ----------------------------
    # Keyed by session too: the same call in two runs (or two connections) is not
    # one repetition.
    seen = collections.OrderedDict()
    for _, record, record_key in tool_calls:
        key = (record_key, record.get("tool", ""), canonical_args(record))
        seen.setdefault(key, []).append(record)
    for (record_key, tool, args), group in seen.items():
        if len(group) < 2:
            continue
        result["repeated_same_args"].append({
            "tool": tool,
            "session": list(record_key),
            "args": args,
            "count": len(group),
            "seqs": [g.get("seq") for g in group],
            "outcomes": [bool(g.get("ok", True)) for g in group],
        })
    result["repeated_same_args"].sort(key=lambda item: -item["count"])

    # --- error codes ------------------------------------------------------
    distribution = collections.Counter()
    by_tool = collections.defaultdict(collections.Counter)
    for _, record, _ in tool_calls:
        if record.get("ok", True):
            continue
        code = record.get("error_code", 0)
        distribution[str(code)] += 1
        by_tool[record.get("tool", "")][str(code)] += 1
    result["error_code_distribution"] = dict(sorted(distribution.items(), key=lambda kv: -kv[1]))
    result["error_code_by_tool"] = {tool: dict(counter) for tool, counter in sorted(by_tool.items())}
    return result


def missing_tools(records, probe_min):
    result = {"method_not_found": [], "probed_argument_names": [], "unreadable_argument_lists": 0,
              "truncated_argument_lists": 0}

    # A `-32601` on a `tools/call` names a tool the server does not have (or one
    # that belongs to the other process). This is the strongest missing-tool
    # clue available.
    for record in calls(records):
        if record.get("ok", True):
            continue
        if record.get("error_code") != -32601:
            continue
        result["method_not_found"].append({
            "tool": record.get("tool", ""),
            "seq": record.get("seq"),
            "message": record.get("error_message", ""),
        })

    # An argument name that shows up in several *failed* calls and in no
    # successful call of any tool was probed, not used: the schema the caller
    # expected is not the schema the tool has.
    #
    # TASK-075 (D11): the argument object is read through `call_args()`, which
    # accepts both spellings the trace can carry (the JSON string it really
    # writes, and a dict). A call whose argument list is neither is counted in
    # `unreadable_argument_lists` - the honest report of "I could not read this
    # one" - instead of silently contributing no keys, which is the shape that
    # hid the signal for two rounds.
    failed_keys = collections.Counter()
    succeeded_keys = collections.Counter()
    failed_examples = {}
    for record in calls(records):
        args = call_args(record)
        if args is None:
            # Two different facts, and the trace itself tells them apart: a
            # `args_truncated` row was cut by the recorder's own budget (the round-5
            # trace has exactly one, seq 128 `editor_add_nodes_batch`), while
            # anything else is an argument list this analyser could not read.
            if record.get("args_truncated"):
                result["truncated_argument_lists"] += 1
            else:
                result["unreadable_argument_lists"] += 1
            continue
        keys = list(args.keys())
        if record.get("ok", True):
            for key in keys:
                succeeded_keys[key] += 1
        else:
            for key in keys:
                failed_keys[key] += 1
                failed_examples.setdefault(key, []).append({
                    "tool": record.get("tool", ""),
                    "seq": record.get("seq"),
                    "error_code": record.get("error_code"),
                })
    for key, count in failed_keys.most_common():
        if count < probe_min or succeeded_keys.get(key, 0) > 0:
            continue
        result["probed_argument_names"].append({
            "name": key,
            "failed_calls": count,
            "succeeded_calls": 0,
            "examples": failed_examples[key][:5],
        })
    return result


def mergeable(records, top_n=10):
    # A sequence only means something inside one session: two clients running
    # side by side are not one workflow, and two runs of the process (whose `seq`
    # restarts) are not a continuation of each other. TASK-054 (O-11) added the
    # generation to the key and handles the one-connection-per-call degeneration
    # in `session_keys()`.
    generations = generation_of(records)
    keys, _ = session_keys(records, generations)
    by_session = collections.OrderedDict()
    for index, record in enumerate(records):
        if record.get("method") != "tools/call" or is_event_line(record):
            continue
        by_session.setdefault(keys[index], []).append(record.get("tool", ""))

    unigrams = collections.Counter()
    bigrams = collections.Counter()
    trigrams = collections.Counter()
    for sequence in by_session.values():
        unigrams.update(sequence)
        bigrams.update(zip(sequence, sequence[1:]))
        trigrams.update(zip(sequence, sequence[1:], sequence[2:]))

    def shapes(counter, size):
        items = []
        for gram, count in counter.most_common():
            # A 1-gram is a plain string name; `list()` would split it into
            # characters (the defect O-11 recorded: `running_game_run_test_
            # scenario` was reported as `["r","u","n",...]`).
            sequence = [gram] if isinstance(gram, str) else list(gram)
            items.append({
                "sequence": sequence,
                "length": size,
                "count": count,
            })
            if len(items) >= top_n:
                break
        return items

    return {
        "unigrams": shapes(unigrams, 1),
        "bigrams": shapes(bigrams, 2),
        "trigrams": shapes(trigrams, 3),
    }


def anomalies(records, max_result_bytes, dominance):
    tool_calls = calls(records)
    result = {
        "timeouts": [],
        "pending_over_ceiling": [],
        "large_responses": [],
        "large_responses_excluded": 0,
        "dominant_tool": None,
        "parse_errors": [],
    }

    for record in records:
        if record.get("method") in ("", None) and not record.get("ok", True) and not is_event_line(record):
            result["parse_errors"].append({
                "seq": record.get("seq"),
                "error_code": record.get("error_code"),
                "error_message": record.get("error_message", ""),
            })

    for record in records:
        if record.get("error_code") == -32000 and record.get("pending_ms") is not None:
            result["timeouts"].append({
                "tool": record.get("tool", ""),
                "seq": record.get("seq"),
                "pending_ms": record.get("pending_ms"),
                "timeout_ms": record.get("timeout_ms"),
                "message": record.get("error_message", ""),
            })
        timeout_ms = record.get("timeout_ms") or 0
        pending_ms = record.get("pending_ms")
        if timeout_ms and pending_ms is not None and pending_ms > timeout_ms:
            result["pending_over_ceiling"].append({
                "tool": record.get("tool", ""),
                "seq": record.get("seq"),
                "pending_ms": pending_ms,
                "timeout_ms": timeout_ms,
            })
        if (record.get("result_bytes") or 0) > max_result_bytes:
            # TASK-054 (O-11): the diagnostic bypass must not appear in its own
            # statistics. A capture event line and the full `tools/list` dump are
            # both large by construction - one carries a before/after picture
            # pair, the other is the whole contract - and neither is a tool
            # answer the caller asked for. Counting them flagged the observer's
            # own switch as an unbounded-response defect.
            if is_capture_line(record) or is_tools_list(record):
                result["large_responses_excluded"] += 1
                continue
            result["large_responses"].append({
                "method": record.get("method", ""),
                "tool": record.get("tool", ""),
                "seq": record.get("seq"),
                "result_bytes": record.get("result_bytes"),
            })

    if tool_calls:
        # `calls()` already excludes the event lines; the dominance share is
        # therefore a share of real tool calls, not of the file's lines.
        counts = collections.Counter(r.get("tool", "") for r in tool_calls)
        tool, count = counts.most_common(1)[0]
        share = float(count) / float(len(tool_calls))
        if share > dominance:
            result["dominant_tool"] = {
                "tool": tool,
                "count": count,
                "total_calls": len(tool_calls),
                "share": round(share, 4),
            }
    return result


def summarise(records, report):
    lines = []
    tool_calls = calls(records)
    failed = [r for r in tool_calls if not r.get("ok", True)]
    lines.append("trace: %d JSON-RPC request(s), %d tools/call, %d failed"
                 % (len(records), len(tool_calls), len(failed)))
    methods = collections.Counter(r.get("method", "") for r in records)
    lines.append("methods: %s" % ", ".join("%s=%d" % (m or "(unparsed)", c)
                                           for m, c in methods.most_common()))
    generations = report["generations"]
    if len(generations) > 1:
        lines.append("generations: %d (a `seq` is only comparable inside one)" % len(generations))
        for entry in generations:
            opened = entry["opened"] or {}
            lines.append("  #%s pid=%s role=%s port=%s version=%s  records=%d tools/call=%d seq=%s..%s"
                         % (entry["generation"], opened.get("pid"), opened.get("role"),
                            opened.get("mcp_port"), opened.get("version"), entry["records"],
                            entry["tool_calls"], entry["first_seq"], entry["last_seq"]))
    else:
        # A single generation is the old, unsegmented file: keep the summary a
        # reader of the pre-TASK-054 output already knows. The span is measured
        # over the *request* lines only - a `trace_opened` marker has neither a
        # `seq` nor a `connection` and would otherwise print as `None`.
        requests = [r for r in records if not is_event_line(r)]
        if requests:
            first, last = requests[0], requests[-1]
            lines.append("seq %s..%s, connection(s): %s"
                         % (first.get("seq"), last.get("seq"),
                            sorted({r.get("connection") for r in requests}, key=lambda value: str(value))))
            lines.append("wall span (from ts_ms): %s ms"
                         % ((last.get("ts_ms") or 0) - (first.get("ts_ms") or 0)))
    degenerate = report.get("session_keys", {}).get("degenerate_generations") or []
    if degenerate:
        lines.append("session keys: generation alone for generation(s) %s "
                     "(one connection per call: `connection` is not a session key there - declared, not ignored)"
                     % ", ".join(str(value) for value in degenerate))

    lines.append("")
    lines.append("== friction ==")
    fric = report["friction"]
    if fric["fail_then_success"]:
        for item in fric["fail_then_success"]:
            lines.append("  fail->success  %s: seq %s failed with %s (%s), seq %s succeeded"
                         % (item["tool"], item["failed_seq"], item["failed_error_code"],
                            item["failed_error_message"], item["succeeded_seq"]))
            lines.append("                 failed args: %s"
                         % json.dumps(item["failed_args"], ensure_ascii=False))
    else:
        lines.append("  fail->success  none")
    if fric["repeated_same_args"]:
        for item in fric["repeated_same_args"][:10]:
            lines.append("  repeated       %s x%d %s"
                         % (item["tool"], item["count"], item["args"]))
    else:
        lines.append("  repeated       none")
    lines.append("  error codes    %s"
                 % (json.dumps(fric["error_code_distribution"]) if fric["error_code_distribution"] else "{}"))
    for tool, codes in fric["error_code_by_tool"].items():
        lines.append("                 %s: %s" % (tool, json.dumps(codes)))

    lines.append("")
    lines.append("== missing tool clues ==")
    miss = report["missing_tools"]
    if miss["method_not_found"]:
        for item in miss["method_not_found"]:
            lines.append("  -32601         %s (seq %s)" % (item["tool"], item["seq"]))
    else:
        lines.append("  -32601         none")
    if miss["probed_argument_names"]:
        for item in miss["probed_argument_names"]:
            lines.append("  probed arg     %s (failed x%d, never accepted)"
                         % (item["name"], item["failed_calls"]))
    else:
        lines.append("  probed args    none")
    if miss.get("unreadable_argument_lists"):
        lines.append("  unreadable arg lists %d (a `tools/call` whose `args` is neither a JSON object nor a JSON "
                     "object string: counted, never read as 'no arguments')"
                     % miss["unreadable_argument_lists"])
    if miss.get("truncated_argument_lists"):
        lines.append("  truncated arg lists  %d (the recorder's own budget cut the argument text; `args_truncated` "
                     "is set on those rows)" % miss["truncated_argument_lists"])

    lines.append("")
    lines.append("== mergeable call sequences ==")
    merge = report["mergeable"]
    for label in ("bigrams", "trigrams"):
        shown = [item for item in merge[label] if item["count"] > 1]
        if not shown:
            lines.append("  %s: none repeated" % label)
            continue
        for item in shown:
            lines.append("  %s x%d  %s" % (label, item["count"], " -> ".join(item["sequence"])))

    lines.append("")
    lines.append("== anomalies ==")
    anom = report["anomalies"]
    lines.append("  timeouts       %d" % len(anom["timeouts"]))
    for item in anom["timeouts"]:
        lines.append("                 %s seq %s pending_ms=%s timeout_ms=%s"
                     % (item["tool"], item["seq"], item["pending_ms"], item["timeout_ms"]))
    lines.append("  pending over ceiling  %d" % len(anom["pending_over_ceiling"]))
    lines.append("  large responses       %d" % len(anom["large_responses"]))
    for item in anom["large_responses"]:
        lines.append("                 seq %s %s result_bytes=%s"
                     % (item["seq"], item["tool"] or item["method"], item["result_bytes"]))
    if anom.get("large_responses_excluded"):
        lines.append("                 (%d excluded: capture event line / tools/list)"
                     % anom["large_responses_excluded"])
    if anom["dominant_tool"]:
        item = anom["dominant_tool"]
        lines.append("  dominant tool  %s: %d/%d calls (%.1f%%)"
                     % (item["tool"], item["count"], item["total_calls"], item["share"] * 100.0))
    else:
        lines.append("  dominant tool  none above the threshold")
    if anom["parse_errors"]:
        lines.append("  unparsed payloads %d" % len(anom["parse_errors"]))
    return "\n".join(lines)


def self_test():
    """TASK-075: the repository's own assertion against the D11 regression.

    The defect was structural and would come back the moment `call_args()` is
    replaced by an `isinstance(record["args"], dict)` test again, so this mode
    feeds the analyser a synthetic trace that *does* carry the signal and
    requires it to be found - both spellings of `args`, plus the control that an
    argument the successful call really accepts is NOT reported.

    Exit 0 when every expectation holds, 1 otherwise.
    """
    records = [
        {"method": "tools/call", "tool": "editor_set_tilemap_cell", "ok": False,
         "error_code": -32602, "seq": 1, "connection": 1, "error_message": "Unknown parameter 'atlas_x'",
         "args": json.dumps({"node_path": "Layer", "atlas_x": 0, "atlas_y": 0})},
        {"method": "tools/call", "tool": "editor_set_tilemap_cell", "ok": False,
         "error_code": -32602, "seq": 2, "connection": 1, "error_message": "Unknown parameter 'atlas_x'",
         "args": json.dumps({"node_path": "Layer", "atlas_x": 1, "atlas_y": 1})},
        {"method": "tools/call", "tool": "editor_set_tilemap_cell", "ok": True,
         "error_code": 0, "seq": 3, "connection": 1,
         "args": json.dumps({"node_path": "Layer", "source_id": 0})},
        # The control: a dict-shaped `args` is still read.
        {"method": "tools/call", "tool": "editor_set_node_property", "ok": False,
         "error_code": -32602, "seq": 4, "connection": 1, "error_message": "Unknown parameter 'bogus'",
         "args": {"path": "Layer", "property": "x", "bogus": 1}},
        {"method": "tools/call", "tool": "editor_set_node_property", "ok": False,
         "error_code": -32602, "seq": 5, "connection": 1, "error_message": "Unknown parameter 'bogus'",
         "args": {"path": "Layer", "property": "y", "bogus": 2}},
        # A call whose `args` is not a JSON object: counted, not silently empty.
        {"method": "tools/call", "tool": "editor_open_scene", "ok": True,
         "error_code": 0, "seq": 6, "connection": 1, "args": "not json"},
        {"method": "tools/call", "tool": "editor_open_scene", "ok": True,
         "error_code": 0, "seq": 7, "connection": 1},
    ]
    report = missing_tools(records, DEFAULT_PROBE_MIN)
    names = [item["name"] for item in report["probed_argument_names"]]
    failures = []
    if "atlas_x" not in names:
        failures.append("the probed argument 'atlas_x' of a string-shaped `args` was not reported (the D11 defect)")
    if "atlas_y" not in names:
        failures.append("the probed argument 'atlas_y' of a string-shaped `args` was not reported")
    if "bogus" not in names:
        failures.append("the probed argument 'bogus' of a dict-shaped `args` was not reported")
    if "node_path" in names:
        failures.append("'node_path' is accepted by a successful call and must never be reported as probed")
    if "source_id" in names:
        failures.append("'source_id' is accepted by a successful call and must never be reported as probed")
    if report["unreadable_argument_lists"] != 2:
        failures.append("unreadable argument lists: expected 2 (a non-JSON string and an absent `args`), got %d"
                        % report["unreadable_argument_lists"])
    if report["truncated_argument_lists"] != 0:
        failures.append("truncated argument lists: expected 0 (none of the synthetic rows sets `args_truncated`), got %d"
                        % report["truncated_argument_lists"])
    for failure in failures:
        print("FAIL: %s" % failure)
    if failures:
        print("SELF-TEST FAILED (%d problem(s))" % len(failures))
        return 1
    print("SELF-TEST PASS (probed arg names found through both `args` spellings; %s; counted %d unreadable and %d "
          "truncated argument list(s))"
          % (", ".join(sorted(names)), report["unreadable_argument_lists"], report["truncated_argument_lists"]))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Analyse an MCP server call trace (TASK-038).")
    parser.add_argument("trace", nargs="?", help="the JSON Lines file written by --mcp-trace=<path>")
    parser.add_argument("--json", dest="json_path", default="",
                        help="write the machine readable report here")
    parser.add_argument("--quiet", action="store_true", help="suppress the human summary")
    parser.add_argument("--self-test", action="store_true",
                        help="run the repository's own regression assertion for the D11 probed-argument signal")
    parser.add_argument("--max-result-bytes", type=int, default=DEFAULT_MAX_RESULT_BYTES)
    parser.add_argument("--dominance", type=float, default=DEFAULT_DOMINANCE)
    parser.add_argument("--window", type=int, default=DEFAULT_EPISODE_WINDOW,
                        help="how many calls apart a fail-then-success pair may be")
    parser.add_argument("--probe-min", type=int, default=DEFAULT_PROBE_MIN)
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.trace:
        parser.error("a trace file is required unless --self-test is given")

    records, bad_lines = load(args.trace)
    generations = generation_of(records)
    _, degenerate_generations = session_keys(records, generations)
    report = {
        "trace_file": args.trace,
        "records": len(records),
        "bad_lines": bad_lines,
        # TASK-054 (O-12): the segmentation first, because every other signal is
        # computed inside a generation.
        "generations": generation_report(records, generations),
        # TASK-054 (O-11): whether `connection` was usable as a session key, and
        # where it was not (declared, not silently ignored).
        "session_keys": {
            "kind": "generation+connection",
            "degenerate_generations": degenerate_generations,
            "note": ("a generation whose tool calls all opened their own connection is keyed by the generation alone "
                     "(file order); `connection` carries no session information there"),
        },
        "friction": friction(records, args.window),
        "missing_tools": missing_tools(records, args.probe_min),
        "mergeable": mergeable(records),
        "anomalies": anomalies(records, args.max_result_bytes, args.dominance),
    }

    if not args.quiet:
        print(summarise(records, report))
    if args.json_path:
        with open(args.json_path, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
    else:
        print("")
        print("-- JSON --")
        print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
