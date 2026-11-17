# Stage: report

Read `$RUN/manifest.json`, `$RUN/context/DOSSIER.md`, `$RUN/findings.jsonl` and
`$RUN/verdicts.jsonl`. Read each stage's other files under `$RUN` when a finding needs them.

Write `$OUT/REPORT.md` in ASD-STE100 Simplified Technical English:

1. Scope and method: the target commit, the stages that ran, the models (from the manifest).
2. A summary table of the `TRUE_POSITIVE` findings, ordered by the verifier's severity.
3. One section per `TRUE_POSITIVE` finding: what is wrong, the evidence with citations, the
   impact, and the fix.
4. A short list of the `FALSE_POSITIVE` findings with the verifier's reason.
5. The unenforced assumptions and the open questions from the dossier that no finding covers.

Use only facts from the files under `$RUN` and the repository. Do not invent findings.
