# TASK-074 section C -- aggregator's raw outputs. ASCII script names, UTF-8 data.
Generated: 2026-09-25 (section C run)
Report:   docs/reports/PLATFORMER-FINDINGS.md

scripts : c_recompute.py c_verify.py c_evidence.py c_items.py c_items2.py
          c_calls.py c_calls2.py c_caps.py c_batch30.py c_misc.py c_dups.py
outputs : c_recompute.json c_verify.json c_evidence.json (data)
          c_recompute.stdout.txt c_verify.stdout.txt c_evidence.stdout.txt
          c_items.stdout.txt c_items2.stdout.txt c_calls.stdout.txt
          c_calls2.stdout.txt c_caps.stdout.txt c_batch30.stdout.txt
          c_misc.stdout.txt c_analyze_editor.txt c_analyze_editor.json
note    : c_recompute.py reads traces with plain utf-8; CALLS.jsonl and
          PROGRESS.md carry a UTF-8 BOM so those readers use utf-8-sig.
          Nothing here writes to modules/mcp_server/** or modules/mono/**.
