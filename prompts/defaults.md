# Stage: insecure defaults

Read `skill://insecure-defaults`. Read `$RUN/inventory/INVENTORY.md` first.

Find insecure defaults in the scope and in its deployment configuration: hard-coded secrets,
fallback values for missing configuration, permissive defaults, debug settings that reach
production. Write each one to `$OUT/findings.jsonl`.
