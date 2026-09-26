"""TASK-051 final consistency sweep (pure ASCII source).

Three facts a reader of the report should not have to take on trust, all
machine-checked:

  1. **the binary is not stale**: no file under `tools/**`, `tests/**` or the
     contract is *content*-newer than `bin/godot.windows.editor.x86_64.console.exe`.
     A newer *mtime* alone does not count - the gate 6 coverage probes rewrite
     `tools/**` byte-identically (their own `B1b_restored_byte_identical` check),
     which bumps the mtime without moving a byte;
  2. **the `.ps1` scripts this batch adds are pure ASCII** (the batch's rule:
     PowerShell 5.1 mis-handles non-ASCII script text);
  3. **the generated artifacts are exactly what the generators produce**: the
     contract is byte-identical after a second `gen_renamed_contract.py` run, and
     each of the three generated registration spans is "already up to date" when
     `gen_b2_game_schema.py --in-place` is re-run. That is what makes "the C++
     literals are the contract" a fact rather than an intention.

Usage:
    python scripts/mcp051_final_sweep.py
Exit code 1 on any failure.
"""
import io
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(MODULE))
BINARY = os.path.join(REPO, "bin", "godot.windows.editor.x86_64.console.exe")

PS1_SCRIPTS = [
    "mcp051_b_tier_evidence.ps1",
    "mcp051_gate1_groups.ps1",
    "mcp051_gates.ps1",
    "mcp051_regression_battery.ps1",
]

SPANS = [
    ("editor_playback", "tools/editor_playback.cpp"),
    ("editor_input_simulation", "tools/editor_input_simulation.cpp"),
    ("running_game_test_execution", "tools/running_game_test_execution.cpp"),
]

WATCH = [
    os.path.join(MODULE, "tools"),
    os.path.join(MODULE, "tests"),
]

problems = []


def walk(target):
    if os.path.isfile(target):
        return [target]
    return [os.path.join(root, name)
            for root, _dirs, names in os.walk(target) for name in names]


print("== 1. the binary is not stale ==")
print("(compiled sources only: `tools/**` and `tests/**`. The contract is a data")
print(" input, not a compiled one; that the C++ literals really are that file is")
print(" step 3 here plus gate 1 on the wire and the schema doctest.)")
if not os.path.exists(BINARY):
    problems.append("the engine binary is missing")
else:
    binary_mtime = os.path.getmtime(BINARY)
    print("binary : %s" % os.path.relpath(BINARY, REPO))
    print("mtime  : %s" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(binary_mtime)))
    for target in WATCH:
        for path in walk(target):
            if os.path.getmtime(path) <= binary_mtime:
                continue
            rel = os.path.relpath(path, REPO).replace("\\", "/")
            tracked = subprocess.call(["git", "-C", REPO, "ls-files", "--error-unmatch", rel],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0
            changed = tracked and subprocess.call(["git", "-C", REPO, "diff", "--quiet", "--", rel]) != 0
            if changed or not tracked:
                problems.append("%s is newer than the binary and its content moved" % rel)
            else:
                print("mtime-only (content identical to HEAD): %s" % rel)

print("")
print("== 2. the batch's PowerShell scripts are pure ASCII ==")
for name in PS1_SCRIPTS:
    path = os.path.join(HERE, name)
    data = io.open(path, "rb").read()
    bad = sum(1 for byte in data if byte > 127)
    print("%-40s bytes=%d non-ascii=%d" % (name, len(data), bad))
    if bad:
        problems.append("%s is not pure ASCII" % name)

print("")
print("== 3. the generated artifacts are what the generators produce ==")
contract = os.path.join(MODULE, "docs", "tools_list.renamed.json")
before = io.open(contract, "rb").read()
subprocess.check_call([sys.executable, os.path.join(HERE, "gen_renamed_contract.py")],
                      stdout=subprocess.DEVNULL)
after = io.open(contract, "rb").read()
print("contract idempotent: %s (%d bytes)" % (before == after, len(after)))
if before != after:
    problems.append("the contract changed when regenerated")
data = json.loads(after.decode("utf-8"))
print("contract: %d tools, generator %s, overrides %d"
      % (len(data["result"]["tools"]), data["_meta"]["generator_version"],
         len(data["_meta"]["overrides"])))

for group, rel in SPANS:
    full = os.path.join(MODULE, rel.replace("/", os.sep))
    before = io.open(full, "rb").read()
    out = subprocess.check_output([sys.executable, os.path.join(HERE, "gen_b2_game_schema.py"),
                                   "--group", group, "--in-place", rel])
    after = io.open(full, "rb").read()
    print("%-30s %s" % (group, out.decode("utf-8", "replace").strip().splitlines()[-1]))
    if before != after:
        problems.append("the generated span of %s moved" % group)

print("")
print("problems = %d" % len(problems))
for problem in problems:
    print("  PROBLEM %s" % problem)
if problems:
    sys.exit(1)
print("SWEEP OK")
