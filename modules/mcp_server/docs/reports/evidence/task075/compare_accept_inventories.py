import hashlib
import io
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
PATTERN = re.compile(r"implemented=(\d+) contract=(\d+) expected_contract=(\d+) tool_names=(\S+)")


def parse(path):
    text = io.open(path, encoding="utf-8", errors="replace").read()
    match = PATTERN.search(text)
    names = match.group(4).split(",")
    cases = re.search(r"(\d+)/(\d+) cases passed", text)
    return {
        "implemented": int(match.group(1)),
        "contract": int(match.group(2)),
        "expected_contract": int(match.group(3)),
        "names": len(names),
        "names_sha256": hashlib.sha256(",".join(names).encode()).hexdigest(),
        "cases": cases.group(0),
        "new_tool_last": names[-1] == "project_read_text_file",
    }, names


first, names_a = parse(os.path.join(HERE, "accept_m1_run1.txt"))
second, names_b = parse(os.path.join(HERE, "accept_m1_run2.txt"))
result = {
    "run1": first,
    "run2": second,
    "lists_identical": names_a == names_b,
    "verdict": "PASS" if (names_a == names_b and first["cases"] == second["cases"]) else "FAIL",
}
text = json.dumps(result, indent=1) + "\n"
io.open(os.path.join(HERE, "accept_m1_inventory_compare.json"), "w", encoding="utf-8").write(text)
print(text)
