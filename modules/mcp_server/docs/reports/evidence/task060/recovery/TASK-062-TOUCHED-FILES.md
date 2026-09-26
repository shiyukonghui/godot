`PATHFIX-TRANSFORM.tsv` shows the plan hashed to exactly `127a85ae...` immediately after the move
and before TASK-062 touched it. TASK-062 deliberately **did not recompute** that field, because
rewriting it would destroy the provenance record. The hash of the plan after TASK-062 is in
`PATHFIX-TRANSFORM.tsv` (after pass 1) and `ANNOTATION-TRANSFORM.tsv` / `POST-RECOVERY-MANIFEST.sha256.tsv`
(after pass 2).

Same reasoning for `BREAKOUT-OBSERVATIONS.md` section 7: 11 of its 13 sha256 rows still verify;
the 2 that do not are exactly `c-obs/watch.ps1` and `c-obs/analyze-final.json`, i.e. the two files
pass 1 changed.

## Pass 3 - LF normalisation of TASK-062's own generated evidence

`[IO.File]::WriteAllLines` on Windows writes CRLF. TASK-062's own ten generated artefacts
(the two move manifests, the three transform/record TSVs, `MOVE-COMPARISON.txt`,
`TASK-062-TOUCHED-FILES.md`, the trace-recovery manifest and the two analysis JSONs) were therefore
first written with CRLF and were then rewritten as **LF-only**, so that they are byte-stable and
match the repository-wide `* text=auto eol=lf` policy. The affected paths are listed in
`POST-RECOVERY-MANIFEST.sha256.tsv`.

`MOVE-BEFORE.sha256.tsv` and `MOVE-AFTER.sha256.tsv` were normalised **together** and remain
byte-identical to each other (`Compare-Object` differences = 0), so the no-content-loss proof is
unaffected. Their own sha256 is now
`a7a623a5417e44fbe0fe9a779e9de117d2bd9ee3d5313a6ad3572b021c29f7ce` (both).

## Pass 4 - documented, not fixed: git EOL normalisation of 21 recovered originals

21 of the recovered original artefacts contain CRLF, and the repository-wide
`* text=auto eol=lf` rule normalises them to LF inside the git object. Those files are **left
exactly as recovered on disk**; the divergence between "as recovered" and "as committed" is
recorded in `GIT-EOL-NORMALIZATION.tsv` / `GIT-EOL-NORMALIZATION.md`. Nothing was silently
changed, and the `c1`-`c4` evidence (the part with `.sha256` sidecars) is unaffected.
