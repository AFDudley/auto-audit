# Stage: static analysis

Read `skill://semgrep` and `skill://sarif-parsing`.

1. Run Semgrep over the scope in "important only" mode. You do not need approval for the plan:
   this run is not interactive. Write the SARIF output to `$OUT/semgrep.sarif`.
2. Triage each result against the code. Write each result that you judge real to
   `$OUT/findings.jsonl`. Write the results that you reject, with one line of reason each, to
   `$OUT/REJECTED.md`.
