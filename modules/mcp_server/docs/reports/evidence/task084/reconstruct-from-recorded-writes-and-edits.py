# -*- coding: utf-8 -*-
"""TASK-084 reconstructor.

Two recorded sources are stronger than the "read epoch" TASK-083 used:

  * `events-write.jsonl`  - the *whole file* of a recorded write;
  * `events-edit.jsonl`   - every edit's full OLD and NEW text.

So: take the newest recorded whole-file write, replay every later edit in time
order (exact substring match, then a whitespace-normalised match), and use the
newest read-window lines as the line-number skeleton.  The uncovered runs of the
skeleton are then filled from the replayed buffer by anchoring on the skeleton
lines around the gap - i.e. the gap content is *recorded text*, not a guess.

usage:
  python rec.py <subpath> [rev]        -> report: skeleton coverage, gaps, replay stats
  python rec.py <subpath> [rev] --out <path>   -> write the assembled file
"""
import io
import json
import os
import re
import sys

IDX = r"C:\Users\wyl\AppData\Local\Temp\mcp-recovery\staging\__payload-index"
WS = re.compile(r"\s+")


def norm(p):
    return (p or "").replace("/", "\\").lower()


_CACHE = {}


def _index(which):
    """One pass per jsonl, grouped by normalised path, cached."""
    if which in _CACHE:
        return _CACHE[which]
    by = {}
    p = os.path.join(IDX, which)
    with io.open(p, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            r["_k"] = which
            by.setdefault(norm(r.get("path", "")), []).append(r)
    _CACHE[which] = by
    return by


def _rows(which, sub):
    by = _index(which)
    out = []
    for path, rows in by.items():
        if sub in path:
            out.extend(rows)
    return out


def load(sub):
    return _rows("events-read.jsonl", sub), _rows("events-edit.jsonl", sub), _rows("events-write.jsonl", sub)


def newest_reads(sub, rev=None):
    """line -> (time, text); rev=None -> the highest totalLines seen."""
    reads, _, _ = load(sub)
    if not reads:
        return {}, {}
    if rev is None:
        rev = max((r.get("totalLines") or 0) for r in reads)
    best = {}
    meta = {}
    for r in reads:
        if (r.get("totalLines") or 0) != rev:
            continue
        t = r.get("time", 0)
        for no, txt in (r.get("lines") or []):
            if no not in best or t > best[no][0]:
                best[no] = (t, txt)
        meta.setdefault("windows", 0)
        meta["windows"] += 1
    return {k: v[1] for k, v in best.items()}, {"rev": rev, "covered": len(best), "windows": meta.get("windows", 0)}


def replay(sub, verbose=True):
    reads, edits, writes = load(sub)
    if writes:
        base = max(writes, key=lambda r: r.get("time", 0))
        buf = base.get("content", "")
        t0 = base.get("time", 0)
        src = "write seq=%s t=%s" % (base.get("seq"), t0)
    else:
        # fall back: newest full-coverage read window
        reads2 = sorted(reads, key=lambda r: ((r.get("totalLines") or 0), r.get("time", 0)), reverse=True)
        buf, t0, src = "", 0, "none"
        for r in reads2:
            tot = r.get("totalLines") or 0
            lns = {no: txt for no, txt in (r.get("lines") or [])}
            if len(lns) >= tot and tot > 0:
                buf = "\n".join(lns[no] for no in range(1, tot + 1))
                t0 = r.get("time", 0)
                src = "full read rev%s t=%s" % (tot, t0)
                break
    stats = {"base": src, "applied": 0, "skipped": [], "fuzzy": 0}
    pending = sorted([e for e in edits if e.get("time", 0) > t0], key=lambda e: e.get("time", 0))
    for e in pending:
        old, new = e.get("old") or "", e.get("new") or ""
        if old and old in buf:
            buf = buf.replace(old, new, 1)
            stats["applied"] += 1
            continue
        # whitespace-tolerant retry: locate by first+last non-empty line
        ol = [x for x in old.split("\n") if x.strip()]
        hit = None
        if ol:
            first = ol[0].strip()
            last = ol[-1].strip()
            lines = buf.split("\n")
            for i, l in enumerate(lines):
                if l.strip() != first:
                    continue
                for j in range(i, min(i + len(old.split("\n")) + 40, len(lines))):
                    if lines[j].strip() == last:
                        hit = (i, j)
                        break
                if hit:
                    break
            if hit:
                lines[hit[0]:hit[1] + 1] = new.split("\n")
                buf = "\n".join(lines)
                stats["applied"] += 1
                stats["fuzzy"] += 1
                continue
        stats["skipped"].append({"seq": e.get("seq"), "t": e.get("time"),
                                 "old_lines": len(old.split("\n")),
                                 "first": (old.split("\n")[0] if old else "")[:80]})
    if verbose:
        print("replay base: %s" % stats["base"])
        print("replay: applied=%d (fuzzy=%d) skipped=%d" % (stats["applied"], stats["fuzzy"], len(stats["skipped"])))
        for s in stats["skipped"]:
            print("   SKIP seq=%s old=%s lines :: %s" % (s["seq"], s["old_lines"], s["first"]))
    return buf.split("\n"), stats


def runs_of(missing):
    out = []
    if not missing:
        return out
    s = prev = missing[0]
    for no in missing[1:]:
        if no == prev + 1:
            prev = no
            continue
        out.append((s, prev))
        s = prev = no
    out.append((s, prev))
    return out


def assemble_runs(sub, rev=None, anchor=4, verbose=True):
    """Run-based assembly: locate each contiguous covered run of the target
    revision inside the replayed buffer, then read the uncovered runs straight
    out of the buffer between them.  The gap text is recorded text."""
    skel, meta = newest_reads(sub, rev)
    rev = meta["rev"]
    buf, stats = replay(sub, verbose=verbose)
    if verbose:
        print("skeleton rev%s: %d lines covered (%d windows)" % (rev, meta["covered"], meta["windows"]))
    covered = [no for no in range(1, rev + 1) if no in skel]
    missing = [no for no in range(1, rev + 1) if no not in skel]
    gaps = runs_of(missing)
    runs = [(s, e) for s, e in runs_of(covered)]
    if verbose:
        print("covered runs: %d   uncovered runs: %s" % (len(runs), ", ".join("%d-%d" % g for g in gaps)))

    def find_run(run, start):
        s, e = run
        n = e - s + 1
        probe = min(n, 12)
        pat = [skel[s + k].rstrip("\r") for k in range(probe)]
        for i in range(start, len(buf) - probe + 1):
            if all(buf[i + k].rstrip("\r") == pat[k] for k in range(probe)):
                # extend while the run continues
                j = i + probe
                k = probe
                while k < n and j < len(buf) and buf[j].rstrip("\r") == skel[s + k].rstrip("\r"):
                    j += 1
                    k += 1
                return i, j, k  # buf start, buf end (exclusive), lines matched
        return None

    mapped = []
    cursor = 0
    for run in runs:
        hit = find_run(run, cursor)
        if hit is None:
            hit = find_run(run, 0)
        if hit is None:
            mapped.append(None)
            continue
        i, j, k = hit
        mapped.append((run, i, j, k))
        cursor = j
    nmatch = sum(1 for m in mapped if m)
    if verbose:
        print("runs located in the replayed buffer: %d/%d" % (nmatch, len(runs)))

    ok_map = [m for m in mapped if m]
    if not ok_map:
        raise SystemExit("no covered run could be located in the replayed buffer")
    out = []
    first_run, fi, _fj, _k = ok_map[0]
    head = buf[fi - (first_run[0] - 1):fi] if first_run[0] > 1 else []
    if len(head) != first_run[0] - 1:
        head = buf[max(0, fi - (first_run[0] - 1)):fi]
    out.extend(head[:first_run[0] - 1] if len(head) >= first_run[0] - 1 else head)
    for idx, m in enumerate(mapped):
        if not m:
            continue
        run, i, j, k = m
        out.extend(skel[no] for no in range(run[0], run[1] + 1))
        # gap after this run = up to the next mapped run
        nxt = None
        for m2 in mapped[idx + 1:]:
            if m2:
                nxt = m2
                break
        if nxt is None:
            tail_start = j
            expected = rev - run[1]
            tail = buf[tail_start:tail_start + expected]
            if verbose:
                print("  tail after %d: want %d got %d %s" % (run[1], expected, len(tail),
                                                             "OK" if len(tail) == expected else "*** MISMATCH ***"))
            out.extend(tail)
        else:
            nrun, ni, nj, nk = nxt
            want = nrun[0] - run[1] - 1
            piece = buf[j:ni]
            if verbose:
                print("  gap %d-%d want %d got %d %s" % (run[1] + 1, nrun[0] - 1, want, len(piece),
                                                        "OK" if len(piece) == want else "*** MISMATCH ***"))
            out.extend(piece[:want] if len(piece) > want else piece)
    if verbose:
        print("assembled %d lines (target %d)" % (len(out), rev))
    return out, {"rev": rev, "gaps": gaps, "stats": stats}


def assemble_anchor(sub, rev=None, anchor=4, verbose=True):
    skel, meta = newest_reads(sub, rev)
    rev = meta["rev"]
    buf, stats = replay(sub, verbose=verbose)
    if verbose:
        print("skeleton rev%s: %d lines covered (%d windows)" % (rev, meta["covered"], meta["windows"]))
    missing = [no for no in range(1, rev + 1) if no not in skel]
    gaps = runs_of(missing)
    if verbose:
        print("uncovered runs: %s" % (", ".join("%d-%d" % g for g in gaps) if gaps else "(none)"))
    out = []
    bufset = {}
    for i, l in enumerate(buf):
        bufset.setdefault(l.strip(), []).append(i)
    pos = 0  # cursor in buf
    filled = {}
    for a, b in gaps:
        # anchors: last `anchor` skeleton lines before a, first `anchor` after b
        before = [skel[no] for no in range(max(1, a - anchor), a) if no in skel]
        after = [skel[no] for no in range(b + 1, min(rev, b + anchor) + 1) if no in skel]
        i0 = None
        if before:
            cand = [i for i in range(len(buf) - len(before) + 1)
                    if all(buf[i + k].rstrip("\r") == before[k].rstrip("\r") for k in range(len(before))) and i >= pos]
            if cand:
                i0 = cand[0] + len(before)
        if i0 is None:
            i0 = pos
        i1 = None
        if after:
            for j in range(i0, len(buf) - len(after) + 1):
                if all(buf[j + k].rstrip("\r") == after[k].rstrip("\r") for k in range(len(after))):
                    i1 = j
                    break
        if i1 is None:
            i1 = i0 + (b - a + 1)
        piece = buf[i0:i1]
        if verbose:
            print("  gap %d-%d  want %d  got %d  %s" % (a, b, b - a + 1, len(piece),
                                                        "OK" if len(piece) == b - a + 1 else "*** SIZE MISMATCH ***"))
        filled[(a, b)] = piece
        pos = i1
    # build output
    res = []
    nxt = 1
    for a, b in gaps:
        while nxt < a:
            res.append(skel[nxt])
            nxt += 1
        res.extend(filled[(a, b)])
        nxt = b + 1
    while nxt <= rev:
        res.append(skel[nxt])
        nxt += 1
    if verbose:
        print("assembled %d lines (target %d)" % (len(res), rev))
    return res, {"rev": rev, "gaps": gaps, "stats": stats}


def _bal(lines):
    d = p = 0
    for l in lines:
        s = l.split("//", 1)[0]
        for ch in s:
            if ch == "{":
                d += 1
            elif ch == "}":
                d -= 1
            elif ch == "(":
                p += 1
            elif ch == ")":
                p -= 1
    return d, p, None


def assemble_best(sub, rev=None, verbose=False):
    """Try both assemblers, keep the one whose length equals the recorded target
    revision and whose braces/parens are the most balanced."""
    results = []
    for name, fn in (("runs", assemble_runs), ("anchor", assemble_anchor)):
        try:
            lines, info = fn(sub, rev, verbose=False)
        except Exception as e:  # noqa: BLE001
            results.append((name, None, None, str(e)))
            continue
        info["method"] = name
        results.append((name, lines, info, None))
    ok = [r for r in results if r[1] is not None and len(r[1]) == r[2]["rev"]]
    if verbose:
        for name, lines, info, err in results:
            if lines is None:
                sys.stderr.write("   %s: EXC %s\n" % (name, err))
            else:
                d, p, _ = _bal(lines)
                sys.stderr.write("   %s: %d lines (target %d, bal {%d,%d})\n" % (name, len(lines), info["rev"], d, p))
    if not ok:
        raise SystemExit("no assembler reproduced the target length for %s" % sub)

    def score(r):
        d, p, _ = _bal(r[1])
        return (abs(d) + abs(p),)

    ok.sort(key=score)
    return ok[0][1], ok[0][2]


def assemble(sub, rev=None, anchor=4, verbose=True):
    return assemble_best(sub, rev, verbose=verbose)


def main():
    sub = sys.argv[1]
    argv = sys.argv[2:]
    rev = None
    if argv and argv[0].isdigit():
        rev = int(argv[0])
        argv = argv[1:]
    out = None
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    res, info = assemble(sub, rev)
    if out:
        with io.open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(res) + "\n")
        print("wrote %s" % out)


if __name__ == "__main__":
    main()
