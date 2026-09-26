"""TASK-063: the sha256 manifest of the evidence tree.

Two legs, deliberately separate:

  * `SHA256SUMS.tsv` is over the evidence **as it was captured** (the directory
    that was copied out of `%TEMP%\\mcp063`), so a reader can recompute it;
  * the plumbing (`module_mcp_server.cpp`, `mcp_server.cpp`, `gen_renamed_contract.py`,
    ...) is a separate program, so the manifest itself can be checked.

Usage:  python scripts/mcp063_evidence_manifest.py [--check]
"""

import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE_ROOT = os.path.dirname(HERE)
ROOT = os.path.join(MODULE_ROOT, "docs", "reports", "evidence", "task063")
MANIFEST = os.path.join(ROOT, "SHA256SUMS.tsv")


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def walk(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root).replace("\\", "/")
            if rel == "SHA256SUMS.tsv":
                continue
            out.append((rel, full))
    return sorted(out)


def main():
    check = "--check" in sys.argv
    entries = walk(ROOT)
    if not entries:
        sys.exit("FATAL: no evidence files under %s" % ROOT)
    lines = []
    bad = []
    for rel, full in entries:
        actual = sha256_file(full)
        lines.append("%s  %d  %s" % (actual, os.path.getsize(full), rel))
        if check:
            bad.append((rel, actual))
    text = "\n".join(lines) + "\n"
    if check:
        with open(MANIFEST, "rb") as handle:
            on_disk = handle.read().decode("utf-8")
        if on_disk != text:
            print("MISMATCH: the manifest does not describe the tree")
            for line in on_disk.splitlines():
                if line not in lines:
                    print("  was: " + line)
            for line in lines:
                if line not in on_disk.splitlines():
                    print("  now: " + line)
            return 1
        print("SHA256 OK: %d file(s), manifest %s" % (len(entries), MANIFEST))
        return 0
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print("wrote %s (%d file(s))" % (MANIFEST, len(entries)))
    print("manifest sha256 = %s" % sha256_file(MANIFEST))
    return 0


if __name__ == "__main__":
    sys.exit(main())
