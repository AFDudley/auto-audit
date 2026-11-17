# Stage: entry points

Read `skill://entry-point-analyzer`. Read `$RUN/context/DOSSIER.md` first.

1. List every externally reachable entry point in the scope: HTTP routes, message handlers,
   exported functions, contract functions that change state. Give each its access control.
   Write the list to `$OUT/ENTRY_POINTS.md`.
2. Write each entry point that has missing or weak access control to `$OUT/findings.jsonl`.
