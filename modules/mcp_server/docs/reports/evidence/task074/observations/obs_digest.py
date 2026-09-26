#!/usr/bin/env python
# TASK-074 section B observer digest (read-only over the frozen trace copies).
# ASCII only. Writes several reports next to itself.
from __future__ import annotations
import collections, hashlib, io, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TRACES = os.path.join(HERE, 'traces')
# TASK-075: the output path is the first argument when one is given, so this
# corrected digest can be written next to the frozen one (`digest.txt`, the
# section-B artefact) instead of overwriting it. The evidence files stay
# append-only; the before/after pair lives in `digest.pre-task075.txt` (produced
# by the pre-fix script) and `digest.task075.txt`.
OUT_PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'digest.txt')
OUT = io.open(OUT_PATH, 'w', encoding='utf-8')

def w(*parts):
    OUT.write(' '.join(str(p) for p in parts) + '\n')

def load(name):
    path = os.path.join(TRACES, name)
    if not os.path.exists(path):
        return []
    recs = []
    for n, line in enumerate(io.open(path, 'r', encoding='utf-8'), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if isinstance(r, dict):
            r['__line'] = n
            r['__file'] = name
            recs.append(r)
    return recs

def is_call(r):
    return r.get('method') == 'tools/call'

def is_capture(r):
    return r.get('event') == 'capture'

def is_open(r):
    return r.get('event') == 'trace_opened'

EDITOR = 'trace-editor.jsonl'
GAMES = ['trace-game.jsonl', 'trace-game2.jsonl', 'trace-game3.jsonl', 'trace-game4.jsonl']

# ---------------------------------------------------------------- editor ----
recs = load(EDITOR)
calls = [r for r in recs if is_call(r)]
caps = [r for r in recs if is_capture(r)]
opens = [r for r in recs if is_open(r)]
wire = [r for r in recs if r.get('method') == 'tools/list']

w('== FILE INVENTORY ==')
for name in [EDITOR] + GAMES:
    rr = load(name)
    w('  %-22s lines=%-4d calls=%-4d captures=%-4d opens=%-2d' % (
        name, len(rr), sum(1 for r in rr if is_call(r)),
        sum(1 for r in rr if is_capture(r)), sum(1 for r in rr if is_open(r))))
w('')

w('== GENERATIONS (trace_opened) ==')
for r in opens:
    w('  %s line=%d pid=%s port=%s role=%s version=%s started_ms=%s' % (
        r['__file'], r['__line'], r.get('pid'), r.get('mcp_port'), r.get('role'),
        r.get('version'), r.get('started_ts_ms')))
w('')

w('== EDITOR SUMMARY ==')
w('  tools/call=%d  tools/list=%d  capture-lines=%d  total-lines=%d' % (len(calls), len(wire), len(caps), len(recs)))
for r in wire:
    w('  tools/list -> tools=%s result_bytes=%s ok=%s' % (r.get('tools'), r.get('result_bytes'), r.get('ok')))
w('  connections: %d distinct; max=%s' % (len(set(r.get('connection') for r in calls)),
                                          max((r.get('connection') or 0) for r in calls)))
w('')

# ------------------------------------------------------------- failures -----
# TASK-075 (D9): these lists are built from the EDITOR trace only - `calls` is
# `load(EDITOR)` filtered. The score that was filed against this digest (the
# round-5 findings' D9: "the game side has 14 non-ok calls, both reports say 2")
# came from exactly this shape: there was no game-side failure count anywhere, so
# the only way to read one was to count the per-call rows of the GAME TRACES
# section by eye. The section below therefore counts per port from the
# *authoritative* per-call record (`CALLS.jsonl`) and states what the traces
# cover; `editor_bad` keeps its old meaning and its old number, now under a name
# that says which process it belongs to.
w('== ALL NON-OK CALLS (editor trace only, in seq order) ==')
w('  seq  line conn tool                              code      message')
editor_bad = [r for r in calls if not r.get('ok')]
for r in sorted(editor_bad, key=lambda r: r.get('seq') or 0):
    msg = (r.get('error_message') or '').replace('\n', ' ')
    w('  %-4s %-4s %-4s %-33s %-9s %s' % (r.get('seq'), r.get('__line'), r.get('connection'),
                                          r.get('tool'), r.get('error_code'), msg[:110]))
w('  count=%d (editor trace ONLY; the game side is counted in the D9 section)' % len(editor_bad))
w('')

w('== -32601 (tool name does not exist) ==')
for r in sorted(calls, key=lambda r: r.get('seq') or 0):
    if r.get('error_code') == -32601:
        w('  seq=%-4s line=%-4s tool=%s args=%s' % (r.get('seq'), r.get('__line'), r.get('tool'), r.get('args')))
w('')

w('== ERROR CODE DISTRIBUTION (editor trace only) ==')
c = collections.Counter((r.get('tool'), r.get('error_code')) for r in editor_bad)
for (tool, code), n in sorted(c.items(), key=lambda kv: (kv[1], kv[0]), reverse=True):
    w('  %-4d %-34s %s' % (n, tool, code))
w('')

# ------------------------------------------------- repeated identical calls -
w('== REPEATED IDENTICAL (tool,args) CALLS ==')
seen = collections.defaultdict(list)
for r in calls:
    seen[(r.get('tool'), r.get('args'))].append(r)
for (tool, args), rs in sorted(seen.items(), key=lambda kv: -len(kv[1])):
    if len(rs) < 2:
        continue
    codes = [r.get('error_code') for r in rs]
    w('  x%-2d %-33s codes=%s seqs=%s' % (len(rs), tool, codes, [r.get('seq') for r in rs]))
    w('      args=%s' % (args or '')[:160])
w('')

# ---------------------------------------------------------------- captures --
w('== CAPTURE LINES: status / changed ==')
st = collections.Counter((r.get('status'), r.get('changed')) for r in caps)
for k, n in sorted(st.items(), key=lambda kv: -kv[1]):
    w('  status=%-10s changed=%-5s x%d' % (k[0], k[1], n))
w('  captures with a reason (degraded):')
for r in caps:
    if r.get('reason'):
        w('    seq=%s tool=%s status=%s reason=%s' % (r.get('seq'), r.get('tool'), r.get('status'), r.get('reason')))
w('')
w('== CAPTURE: ok=true calls whose viewport did NOT change ==')
w('  (a signal only: a write can be real and still invisible in the 2d viewport)')
byseq = {}
for r in calls:
    byseq[r.get('seq')] = r
unchanged_ok = []
for r in caps:
    call = byseq.get(r.get('seq'))
    if call is None:
        continue
    if call.get('ok') and r.get('status') == 'done' and r.get('changed') is False:
        unchanged_ok.append((r.get('seq'), call.get('tool')))
cnt = collections.Counter(t for _, t in unchanged_ok)
for t, n in cnt.most_common():
    w('  %-34s x%d' % (t, n))
w('  total=%d of %d ok-calls-with-capture' % (len(unchanged_ok),
      sum(1 for r in caps if byseq.get(r.get('seq'), {}).get('ok'))))
w('')

w('== CAPTURE: changed=true (these prove the write reached the screen) ==')
for r in caps:
    if r.get('changed') is True:
        call = byseq.get(r.get('seq'), {})
        w('  seq=%-4s tool=%-33s pixels=%-8s ratio=%-8s sha_before=%s sha_after=%s' % (
            r.get('seq'), r.get('tool'), r.get('changed_pixels'), r.get('changed_pixel_ratio'),
            (r.get('before') or {}).get('sha256', '')[:12], (r.get('after') or {}).get('sha256', '')[:12]))
w('')

# ------------------------------------------------------------ per tool ------
w('== PER-TOOL CALLS (editor) ==')
tc = collections.Counter(r.get('tool') for r in calls)
tf = collections.Counter(r.get('tool') for r in editor_bad)
total = len(calls)
for t, n in tc.most_common():
    w('  %-34s calls=%-4d failed=%-3d share=%.1f%%' % (t, n, tf.get(t, 0), 100.0 * n / total))
w('')

# ------------------------------------------------------------- timing -------
w('== SLOWEST CALLS (top 12 by duration_ms) ==')
for r in sorted(calls, key=lambda r: -(r.get('duration_ms') or 0))[:12]:
    w('  %-8s ms  seq=%-4s %-33s bytes=%s ok=%s' % (r.get('duration_ms'), r.get('seq'), r.get('tool'),
                                                    r.get('result_bytes'), r.get('ok')))
w('')
w('== DEFERRED / pending fields ==')
for r in recs:
    if 'pending_ms' in r or 'timeout_ms' in r:
        w('  %s' % json.dumps({k: r[k] for k in ('__file', '__line', 'seq', 'tool', 'ok', 'error_code',
                                                 'error_message', 'pending_ms', 'timeout_ms', 'duration_ms')},
                              ensure_ascii=False))
w('')

# ------------------------------------------------------------ n-grams -------
w('== N-GRAMS (editor, same generation) ==')
seqs = sorted([r for r in calls], key=lambda r: r.get('seq') or 0)
tools = [r.get('tool') for r in seqs]
for n in (2, 3):
    gram = collections.Counter(tuple(tools[i:i + n]) for i in range(len(tools) - n + 1))
    w('  -- %d-grams with count >= 2 --' % n)
    for g, k in gram.most_common():
        if k >= 2:
            w('    x%-2d %s' % (k, ' -> '.join(g)))
w('')

# ------------------------------------------------------------ game ----------
w('== GAME TRACES ==')
for name in GAMES:
    rr = load(name)
    w('  -- %s: lines=%d --' % (name, len(rr)))
    for r in rr:
        if is_open(r):
            w('     OPEN pid=%s port=%s role=%s version=%s' % (r.get('pid'), r.get('mcp_port'), r.get('role'), r.get('version')))
        elif is_call(r):
            w('     seq=%-4s %-33s ok=%-5s code=%-7s ms=%-5s args=%s' % (
                r.get('seq'), r.get('tool'), r.get('ok'), r.get('error_code'), r.get('duration_ms'),
                (r.get('args') or '')[:150]))
        elif is_capture(r):
            w('     CAP  seq=%-4s %-33s status=%s changed=%s reason=%s' % (
                r.get('seq'), r.get('tool'), r.get('status'), r.get('changed'), r.get('reason')))
        elif r.get('method') == 'tools/list':
            w('     LIST tools=%s bytes=%s' % (r.get('tools'), r.get('result_bytes')))
    w('')

# ===========================================================================
# D9 (TASK-075): the non-ok counts, counted per port on the authoritative record
# ===========================================================================
#
# WHY THIS SECTION EXISTS
#   The round-5 findings (PLATFORMER-FINDINGS section 2.2) charged both reports
#   with saying "the game side has 2 non-ok calls" while the per-call record has
#   14. Both numbers were produced without a game-side counter: `editor_bad`
#   above is editor-only, and the game traces were only ever *listed*, one row
#   per call (see GAME TRACES), so the only way to get a game-side number was to
#   count rows by eye. This section removes that step: the numbers come from
#   `CALLS.jsonl` (one JSON object per `tools/call`, with the port) and are
#   cross-checked against the raw response files, and the digest states how much
#   of the record the *traces* actually carry - because the traces are a bounded
#   snapshot (a forced kill truncates the tail, and a session that never enabled
#   the trace leaves none at all).
w('== D9: NON-OK CALLS BY PORT (CALLS.jsonl, the authoritative per-call record) ==')
calls_path = os.path.join(HERE, '..', 'CALLS.jsonl')
by_port = collections.Counter()
by_port_code = collections.defaultdict(collections.Counter)
by_port_tool = collections.defaultdict(collections.Counter)
record_rows = 0
record_ok = 0
iserror_values = collections.Counter()
if os.path.exists(calls_path):
    # `utf-8-sig`: the round-5 CALLS.jsonl carries a UTF-8 BOM (the findings'
    # OP6), and a plain `utf-8` read raises on the first line.
    for line in io.open(calls_path, 'r', encoding='utf-8-sig'):
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if not isinstance(row, dict):
            continue
        record_rows += 1
        # The outcome of one call in this record is the `result` string
        # ("ok" / "error curl=<n> code=<json-rpc error code>"), NOT the `isError`
        # boolean: measured on the frozen file, `isError` is False in all 232 rows
        # (the harness wrote the field from a truthiness test that never fired),
        # so a count taken from `isError` reports 0 for the whole session. That is
        # the second half of D9's root cause and the reason this section reads
        # `result`.
        result_text = str(row.get('result', ''))
        iserror_values[str(row.get('isError'))] += 1
        if result_text.split(' ')[0] != 'error':
            record_ok += 1
            continue
        code_match = re.search(r'code=(-?\d+)', result_text)
        code = int(code_match.group(1)) if code_match else None
        port = row.get('port')
        by_port[port] += 1
        by_port_code[port][code] += 1
        by_port_tool[port][row.get('tool')] += 1
    for port in sorted(by_port, key=lambda p: (p is None, p)):
        w('  port %-6s non-ok=%-3d codes=%s' % (port, by_port[port],
                                                dict(sorted(by_port_code[port].items()))))
        for tool, n in by_port_tool[port].most_common():
            w('        x%-3d %s' % (n, tool))
    w('  rows=%d  ok=%d  non-ok total=%d' % (record_rows, record_ok, sum(by_port.values())))
    w('  editor (9888) non-ok=%d   game (9889) non-ok=%d' % (by_port.get(9888, 0), by_port.get(9889, 0)))
    w('  the record\'s own `isError` boolean, for the record: %s' % dict(iserror_values))
else:
    w('  CALLS.jsonl NOT FOUND at %s: no per-port count is possible here' % calls_path)
w('')

w('== D9: WHAT THE TRACES COVER (the trace is a bounded snapshot) ==')
trace_non_ok = collections.OrderedDict()
for name in [EDITOR] + GAMES:
    rr = load(name)
    trace_non_ok[name] = sum(1 for r in rr if is_call(r) and not r.get('ok'))
for name, n in trace_non_ok.items():
    w('  %-22s non-ok in trace = %d' % (name, n))
trace_editor = trace_non_ok.get(EDITOR, 0)
trace_game = sum(trace_non_ok.get(name, 0) for name in GAMES)
w('  ---------------------------------------------------------------')
w('  editor: trace=%d   CALLS.jsonl=%d   delta=%d (not represented in the trace)'
  % (trace_editor, by_port.get(9888, 0), by_port.get(9888, 0) - trace_editor))
w('  game:   trace=%d   CALLS.jsonl=%d   delta=%d (not represented in any trace)'
  % (trace_game, by_port.get(9889, 0), by_port.get(9889, 0) - trace_game))
w('  COVERAGE: the traces carry %d of the %d editor-side and %d of the %d game-side failures recorded in '
  'CALLS.jsonl. A per-trace count is a LOWER BOUND, never the session total: a forced kill truncates the tail '
  'of a trace and a session that never enabled the trace leaves none at all, so CALLS.jsonl (and raw/**) is '
  'what a number must be quoted from.'
  % (trace_editor, by_port.get(9888, 0), trace_game, by_port.get(9889, 0)))
if by_port and trace_game < by_port.get(9889, 0):
    w('  COVERAGE WARNING: %d of the %d recorded game-side failures appear in NO trace line.'
      % (by_port.get(9889, 0) - trace_game, by_port.get(9889, 0)))
w('')

w('== D9: CROSS-CHECK AGAINST raw/** (one directory per call, response with an error key) ==')
raw_dir = os.path.join(HERE, '..', 'raw')
raw_total = 0
raw_error = 0
if os.path.isdir(raw_dir):
    for name in sorted(os.listdir(raw_dir)):
        response = os.path.join(raw_dir, name, 'response.json')
        if not os.path.isfile(response):
            continue
        raw_total += 1
        try:
            text = io.open(response, 'r', encoding='utf-8-sig').read()
        except Exception:
            continue
        try:
            parsed = json.loads(text)
        except ValueError:
            continue
        if isinstance(parsed, dict) and parsed.get('error') is not None:
            raw_error += 1
    match = (raw_error == sum(by_port.values()))
    w('  raw dirs with a response.json = %d ; of them carrying an "error" key = %d' % (raw_total, raw_error))
    w('  CALLS.jsonl non-ok total = %d ; raw/** non-ok = %d ; %s'
      % (sum(by_port.values()), raw_error, 'MATCH' if match else 'MISMATCH'))
    if not match:
        w('  MISMATCH: two independent records of the same session disagree; do not quote either as the count.')
else:
    w('  raw/** NOT FOUND at %s' % raw_dir)
w('')

OUT.close()
print('digest written: %s (%d bytes)' % (OUT_PATH, os.path.getsize(OUT_PATH)))