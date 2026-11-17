# Stage: variant analysis

Read `skill://variant-analysis`. `$CONFIRMED` holds findings that a verifier confirmed. `$KNOWN`
holds every finding the audit has so far.

For each confirmed finding, search the scope for other instances of the same root cause. Write
each new instance to `$OUT/findings.jsonl`. Do not repeat a finding that is already in `$KNOWN`
(same file and same root cause). Write an empty file when you find no new instance.
