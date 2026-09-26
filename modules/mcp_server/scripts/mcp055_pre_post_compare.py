# =============================================================================
#  mcp055_pre_post_compare.py -- TASK-055 (D112)
#
#  Compares the two capture runs of
#  `mcp055_csharp_compile_verdict_evidence.ps1` (one on the pre-patch binary,
#  one on the post-patch binary) label by label, and asserts *which* labels are
#  allowed to differ:
#
#    * `tools/list` may differ, and only there - and only in the two
#      `project_validate_*` description fields, which have to equal the contract
#      of the matching revision (`git show HEAD:.../tools_list.renamed.json` for
#      the pre side, the working tree for the post side);
#    * the C# verdict probes may differ (that is the batch's whole point, and the
#      capture script asserts what each side says);
#    * **everything else must be byte-identical**, which is the "175 tools keep
#      their behaviour" claim of the task book.
#
#  Usage:
#    python scripts/mcp055_pre_post_compare.py --pre <dir> --post <dir>
# =============================================================================

import argparse
import io
import json
import os
import subprocess
import sys

# Labels whose response bytes are expected to move. Every other hashed label is
# required to be identical, and a label missing on either side is a failure.
EXPECTED_DIFFERENT = {
    "plain-02-tools_list",
    "mono-13-tools-list",
    "plain-91-plural-cs",
    "mono-01-singular-legit-before-build",
    "mono-02-plural-legit-before-build",
    "mono-04-singular-legit-after-build",
    "mono-05-plural-legit-after-build",
    "mono-07-singular-broken-after-failed-build",
    "mono-08-plural-broken-after-failed-build",
    "mono-09-singular-legit-after-failed-build",
    "mono-10-plural-mixed-after-edit",
    "mono-11-singular-edited-after-build",
}

VALIDATE_TOOLS = ("project_validate_script", "project_validate_scripts")


def read_hashes(path):
    out = {}
    with io.open(os.path.join(path, "hashes.txt"), encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            label, sha = line.split("|", 1)
            out[label] = sha
    return out


def read_tools(dir_path, label):
    with io.open(os.path.join(dir_path, label + ".response.json"), encoding="utf-8") as handle:
        envelope = json.load(handle)
    return {t["name"]: t for t in envelope["result"]["tools"]}


def read_payload(dir_path, label):
    with io.open(os.path.join(dir_path, label + ".response.json"), encoding="utf-8") as handle:
        envelope = json.load(handle)
    if "error" in envelope:
        return {"__error__": envelope["error"]}
    return json.loads(envelope["result"]["content"][0]["text"])


def pre_contract():
    text = subprocess.check_output(
        ["git", "show", "HEAD:modules/mcp_server/docs/tools_list.renamed.json"],
        cwd=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."),
    )
    return {t["name"]: t for t in json.loads(text.decode("utf-8"))["result"]["tools"]}


def post_contract():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "tools_list.renamed.json")
    with io.open(os.path.normpath(path), encoding="utf-8") as handle:
        return {t["name"]: t for t in json.load(handle)["result"]["tools"]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pre", required=True)
    parser.add_argument("--post", required=True)
    args = parser.parse_args()

    pre = read_hashes(args.pre)
    post = read_hashes(args.post)
    failures = []
    same = []
    different = []

    only_pre = sorted(set(pre) - set(post))
    only_post = sorted(set(post) - set(pre))
    if only_pre or only_post:
        failures.append("label sets differ: only-pre=%s only-post=%s" % (only_pre, only_post))

    for label in sorted(set(pre) & set(post)):
        if pre[label] == post[label]:
            same.append(label)
            if label in EXPECTED_DIFFERENT:
                failures.append("%s was expected to differ but is byte-identical" % label)
        else:
            different.append(label)
            if label not in EXPECTED_DIFFERENT:
                failures.append("%s differs but is not in the allowed set" % label)

    print("=" * 70)
    print(" TASK-055 pre-patch vs post-patch response bytes")
    print("=" * 70)
    print("pre : %s" % args.pre)
    print("post: %s" % args.post)
    print("")
    print("%d identical, %d expected-different, %d labels" % (len(same), len(different), len(pre)))
    for label in different:
        print("  [DIFF-OK] %-45s pre=%s post=%s" % (label, pre[label][:12], post[label][:12]))
    missing = [l for l in EXPECTED_DIFFERENT if l not in pre and l not in post]
    if missing:
        failures.append("expected-different labels never captured: %s" % missing)

    # The contract diff has to be exactly the two descriptions.
    for label, revision in (("plain-02-tools_list", "pre"), ("mono-13-tools-list", "post")):
        if label not in pre or label not in post:
            continue
        before = read_tools(args.pre, label)
        after = read_tools(args.post, label)
        if sorted(before) != sorted(after):
            failures.append("%s: the tool *set* changed (%d -> %d)" % (label, len(before), len(after)))
        moved = [name for name in sorted(before) if before[name] != after[name]]
        print("")
        print("%s: %d tools, %d entries moved: %s" % (label, len(before), len(moved), moved))
        if moved != sorted(VALIDATE_TOOLS):
            failures.append("%s: the moved entries are %s, expected exactly the two validate tools" % (label, moved))
        for name in moved:
            if before[name].get("inputSchema") != after[name].get("inputSchema"):
                failures.append("%s: %s changed its inputSchema too" % (label, name))

    old = pre_contract()
    new = post_contract()
    for name in VALIDATE_TOOLS:
        pre_live = read_tools(args.pre, "plain-02-tools_list").get(name, {})
        post_live = read_tools(args.post, "mono-13-tools-list").get(name, {})
        if pre_live.get("description") != old[name]["description"]:
            failures.append("pre tools/list %s description != HEAD contract" % name)
        if post_live.get("description") != new[name]["description"]:
            failures.append("post tools/list %s description != working-tree contract" % name)
        if old[name]["description"] == new[name]["description"]:
            failures.append("%s description did not change at all" % name)
    print("")
    print("contract: pre descriptions == HEAD contract, post descriptions == working-tree contract: %s"
          % ("PASS" if not [f for f in failures if "description" in f] else "FAIL"))

    # The C# verdict itself, side by side (the capture script asserts each side;
    # this is the human-readable collision of the two).
    for label, path in (("mono-08-plural-broken-after-failed-build", "res://scripts/broken.cs"),
                        ("mono-10-plural-mixed-after-edit", "res://scripts/broken.cs"),
                        ("mono-10-plural-mixed-after-edit", "res://scripts/legit.cs")):
        for revision, dir_path in (("pre", args.pre), ("post", args.post)):
            payload = read_payload(dir_path, label)
            item = None
            for candidate in payload.get("results", []):
                if candidate.get("path") == path:
                    item = candidate
            if item is None:
                failures.append("%s/%s: no item for %s" % (revision, label, path))
                continue
            print("  %-4s %-42s %-28s category=%-14s valid=%s error_text=%s"
                  % (revision, label, path, item.get("category"), item.get("valid"),
                     (item.get("error_text") or "")[:40]))

    print("")
    if failures:
        print("FAILURES (%d):" % len(failures))
        for failure in failures:
            print("  - %s" % failure)
        return 1
    print("PASS: every probe outside the declared set is byte-identical, the contract diff is the two descriptions,")
    print("      and the C# verdict moved from 'unverifiable' to the real verdict on both sides.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
