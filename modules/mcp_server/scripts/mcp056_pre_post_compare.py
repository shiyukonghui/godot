#!/usr/bin/env python3
"""TASK-056: the byte-level before/after comparison of D1 and D3.

The "before" records are tracked, so the comparison does not depend on any
binary that no longer exists:

  D1  docs/reports/evidence/task055/post/plain-91-plural-cs.{request,response}.json
      (the immediately pre-fix build: the `language_unavailable` item carries
      `"valid":false` and no `reason`)
  D3  docs/reports/evidence/task055/post/mono-03-build-succeeds.response.json
      (the immediately pre-fix build: `command` starts with the mixed separator
      `C:\\Program Files\\dotnet\\/dotnet.exe`, `exit_code` 0)

The "after" records are captured by scripts/mcp056_evidence.ps1.

The script is deliberately an allow-list: any difference outside the fields this
task is allowed to change is a FAILURE, not a note.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys


def load(path: str):
    with open(path, "rb") as handle:
        raw = handle.read()
    return raw, json.loads(raw.decode("utf-8"))


def payload_of(envelope: dict) -> dict:
    return json.loads(envelope["result"]["content"][0]["text"])


def item_of(payload: dict, path: str) -> dict:
    for item in payload.get("results", []):
        if item.get("path") == path:
            return item
    raise KeyError(path)


def check(ok: bool, name: str, detail: str) -> bool:
    print("[%s] %s :: %s" % ("PASS" if ok else "FAIL", name, detail))
    return ok


def compare_d1(before_path: str, after_path: str) -> bool:
    before_raw, before_env = load(before_path)
    after_raw, after_env = load(after_path)
    before = payload_of(before_env)
    after = payload_of(after_env)
    ok = True

    print("--- D1: %s vs %s ---" % (before_path, after_path))
    print("before bytes=%d after bytes=%d" % (len(before_raw), len(after_raw)))
    print("before item = " + json.dumps(item_of(before, "res://scripts/Legit.cs"), sort_keys=True))
    print("after  item = " + json.dumps(item_of(after, "res://scripts/Legit.cs"), sort_keys=True))

    b_cs = item_of(before, "res://scripts/Legit.cs")
    a_cs = item_of(after, "res://scripts/Legit.cs")

    ok &= check(b_cs.get("valid") is False, "before_published_valid_false", repr(b_cs.get("valid")))
    ok &= check(a_cs.get("valid") is None, "after_publishes_valid_null", repr(a_cs.get("valid")))
    ok &= check("valid" in a_cs, "after_still_has_the_valid_key", str(sorted(a_cs.keys())))
    ok &= check("reason" not in b_cs, "before_had_no_reason", str("reason" in b_cs))
    ok &= check(
        "get_language_for_extension" in str(a_cs.get("reason", "")),
        "after_reason_names_the_engine_call",
        str(a_cs.get("reason", ""))[:160],
    )

    # Everything else about the item must be untouched.
    for key in sorted(set(b_cs) | set(a_cs)):
        if key in ("valid", "reason"):
            continue
        ok &= check(
            b_cs.get(key) == a_cs.get(key),
            "item_field_unchanged:%s" % key,
            "%r -> %r" % (b_cs.get(key), a_cs.get(key)),
        )

    # Every payload key outside `results` must be byte-for-byte the same value.
    for key in sorted(set(before) | set(after)):
        if key == "results":
            continue
        ok &= check(before.get(key) == after.get(key), "payload_field_unchanged:%s" % key, repr(after.get(key)))
    ok &= check(len(before.get("results", [])) == len(after.get("results", [])), "result_count_unchanged", str(len(after.get("results", []))))

    # The other file of the batch is a real verdict and must not have moved.
    b_gd = item_of(before, "res://scripts/plain.gd")
    a_gd = item_of(after, "res://scripts/plain.gd")
    ok &= check(b_gd == a_gd, "the_ok_item_is_untouched", json.dumps(a_gd, sort_keys=True))

    # No other `language_unavailable`-like claim of "false" survives anywhere.
    # Checked on the payload text (the unescaped JSON string the tool emitted),
    # not on the envelope's escaped form.
    after_text = after_env["result"]["content"][0]["text"]
    before_text = before_env["result"]["content"][0]["text"]
    ok &= check('"valid":false' in before_text, "before_payload_had_valid_false", before_text[:200])
    ok &= check('"valid":false' not in after_text, "after_payload_has_no_valid_false", "payload text scan")
    ok &= check('"valid":null' in after_text, "the_wire_really_carries_a_null", "payload text scan")
    return bool(ok)


def compare_d3(before_path: str, after_path: str) -> bool:
    _, before_env = load(before_path)
    _, after_env = load(after_path)
    before = payload_of(before_env)
    after = payload_of(after_env)
    ok = True

    print("--- D3: %s vs %s ---" % (before_path, after_path))
    b_cmd = str(before["command"])
    a_cmd = str(after["command"])
    print("before command = " + b_cmd)
    print("after  command = " + a_cmd)

    b_exe = b_cmd.split(" build ", 1)[0]
    a_exe = a_cmd.split(" build ", 1)[0]
    ok &= check(before["exit_code"] == 0, "before_exit_code_0", str(before["exit_code"]))
    ok &= check(after["exit_code"] == 0, "after_exit_code_0", str(after["exit_code"]))
    ok &= check(("\\/" in b_exe) or ("/\\" in b_exe), "before_had_a_mixed_separator", b_exe)
    ok &= check(("\\/" not in a_exe) and ("/\\" not in a_exe), "after_has_no_mixed_separator", a_exe)
    ok &= check(("\\\\" not in a_exe) or a_exe.startswith("\\\\"), "after_has_no_doubled_separator", a_exe)
    ok &= check(a_exe.endswith("\\dotnet.exe") or a_exe.endswith("/dotnet"), "after_names_dotnet", a_exe)
    ok &= check(re.sub(r"[\\/]+", "\\\\", b_exe).lower() == re.sub(r"[\\/]+", "\\\\", a_exe).lower(), "the_executable_is_the_same_file", "%s vs %s" % (b_exe, a_exe))
    ok &= check(" build " in a_cmd and a_cmd.endswith(".csproj -c Debug"), "the_arguments_are_unchanged", a_cmd.split(" build ", 1)[1])
    ok &= check(str(after.get("commands", [""])[0]) == a_cmd, "commands_array_matches_command", str(after.get("commands")))
    ok &= check(os.path.exists(a_exe), "the_reported_executable_exists_on_disk", a_exe)

    # The pre-fix record resolved a directory spelled with a trailing backslash
    # plus path_join's '/'; the fix replaces the run, not the file.
    b_dir = os.path.dirname(b_exe.replace("/", os.sep).replace("\\", os.sep))
    a_dir = os.path.dirname(a_exe)
    ok &= check(os.path.normcase(os.path.normpath(b_dir)) == os.path.normcase(os.path.normpath(a_dir)) and b_dir == a_dir, "the_directory_is_the_same", "%s vs %s" % (b_dir, a_dir))
    return bool(ok)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=None)
    args = parser.parse_args()
    repo = args.repo or os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
    task055 = os.path.join(repo, "modules", "mcp_server", "docs", "reports", "evidence", "task055", "post")
    task056 = os.path.join(repo, "modules", "mcp_server", "docs", "reports", "evidence", "task056")

    ok = True
    ok &= compare_d1(
        os.path.join(task055, "plain-91-plural-cs.response.json"),
        os.path.join(task056, "plain-91-plural-cs.response.json"),
    )
    d3_before = os.path.join(task055, "mono-03-build-succeeds.response.json")
    d3_after = os.path.join(task056, "mono-build-csharp.response.json")
    if os.path.exists(d3_after) and os.path.exists(d3_before):
        ok &= compare_d3(d3_before, d3_after)
    else:
        print("[SKIP] D3 comparison: missing %s or %s" % (d3_before, d3_after))

    print("")
    print("PRE_POST_COMPARE=%s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
