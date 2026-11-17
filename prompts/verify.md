# Stage: verification

Read `skill://fp-check`. Another model found the issues in `$PENDING`. Each line has an `id`.

Try to refute each finding against the code. Do not trust the finder's evidence: read the cited
lines and the code that reaches them.

Write `$OUT/verdicts.jsonl` with exactly one line for each `id` in `$PENDING`, with exactly these
keys: `id` (string), `verdict` (`TRUE_POSITIVE` or `FALSE_POSITIVE`), `severity` (your own rating:
`critical`, `high`, `medium`, `low`, or `info`), `reason` (one or two sentences with citations).
