# Stage: smart contracts

Read `skill://secure-workflow-guide` and `skill://token-integration-analyzer`. Read
`$RUN/context/DOSSIER.md` and `$RUN/entry/ENTRY_POINTS.md` first, if they exist.

1. Run Slither over the Solidity contracts in the scope. Write its output to `$OUT/slither.txt`.
2. Review the contracts: access control, signature handling, token transfers, arithmetic, and the
   invariants that protect the funds. Write each issue to `$OUT/findings.jsonl`.
