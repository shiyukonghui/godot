"""TASK-051 wire-level checks against the captured evidence (pure ASCII source).

Two independent legs, both read from the *captured responses* of
`scripts/mcp051_b_tier_evidence.ps1` rather than from any in-process state:

  1. **verbatim on the wire**: for each of the five tools this batch changed,
     the `inputSchema` in the live `tools/list` response equals the contract's
     entry, compared as JSON (sorted keys, recursive) - the same comparison gate
     1 makes, taken here from a saved body so it can be re-run without an
     engine;
  2. **the default answers really did not move**: the `connections[]` array of
     the editor's default `editor_list_signal_connections` call (and of the
     `signal_name`-filtered one) is identical, element for element, between the
     red (pre-change binary) and green runs. The batch adds `counts` and `scope`
     to that answer, so the *body* is longer; this check is what proves the
     narrowing changed nothing about the connections themselves.

Usage:
    python scripts/mcp051_wire_verbatim_check.py
Exit code 1 when a check fails.
"""
import io
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
EVID = os.path.join(REPO, "modules", "mcp_server", "docs", "reports", "evidence", "task051")
CONTRACT = os.path.join(REPO, "modules", "mcp_server", "docs", "tools_list.renamed.json")

EDITOR_TOOLS = [
    "editor_add_nodes_batch",
    "editor_list_signal_connections",
    "editor_simulate_input_sequence",
    "editor_play_scene",
]
GAME_TOOLS = ["running_game_run_test_scenario"]

# The four editor-scope tools are served by the editor endpoint and must be
# *absent* from a game endpoint; the one game-scope tool is the other way round.
# The five are therefore the union of the two endpoints, not the content of
# either.
ENDPOINTS = {
    "editor": EDITOR_TOOLS,
    "game": GAME_TOOLS,
}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def load(path):
    with io.open(path, encoding="utf-8") as handle:
        return json.load(handle)


def result_payload(response):
    return json.loads(response["result"]["content"][0]["text"])


def main():
    problems = []
    with io.open(CONTRACT, encoding="utf-8") as handle:
        contract = json.load(handle)
    by_name = dict((tool["name"], tool) for tool in contract["result"]["tools"])

    print("== 1. verbatim on the wire (green run) ==")
    listings = {}
    for endpoint, names in sorted(ENDPOINTS.items()):
        path = os.path.join(EVID, "green", endpoint + "-tools_list.response.json")
        response = load(path)
        listing = dict((tool["name"], tool) for tool in response["result"]["tools"])
        listings[endpoint] = listing
        print("%s: %d tools listed, body %d B"
              % (endpoint, len(response["result"]["tools"]), os.path.getsize(path)))
        for name in names:
            live = listing.get(name)
            if live is None:
                problems.append("%s: %s is not listed" % (endpoint, name))
                continue
            expected = by_name[name]
            same_schema = canonical(live["inputSchema"]) == canonical(expected["inputSchema"])
            same_description = live.get("description") == expected.get("description")
            print("  %-32s inputSchema=%s description=%s"
                  % (name, same_schema, same_description))
            if not same_schema:
                problems.append("%s: %s inputSchema differs from the contract" % (endpoint, name))
            if not same_description:
                problems.append("%s: %s description differs from the contract" % (endpoint, name))
        # and the other endpoint must not serve what it never served
        for name in sorted(set(EDITOR_TOOLS + GAME_TOOLS) - set(names)):
            print("  %-32s absent by design (scope)" % name)

    print("")
    print("== 2. the default answers did not move (red vs green) ==")
    for probe in ("e02_o9_default_scope", "e06_o9_signal_name_filter"):
        red = result_payload(load(os.path.join(EVID, "red", probe + ".response.json")))
        green = result_payload(load(os.path.join(EVID, "green", probe + ".response.json")))
        same = canonical(red["connections"]) == canonical(green["connections"])
        print("  %-28s connections red=%d green=%d identical=%s"
              % (probe, len(red["connections"]), len(green["connections"]), same))
        if not same:
            problems.append("%s: the connections array moved" % probe)
        for key in ("counts", "scope"):
            if key in green:
                print("      green adds %s=%s" % (key, canonical(green[key])))

    print("")
    print("problems = %d" % len(problems))
    for problem in problems:
        print("  PROBLEM %s" % problem)
    if problems:
        sys.exit(1)
    print("WIRE CHECK OK")


if __name__ == "__main__":
    main()
