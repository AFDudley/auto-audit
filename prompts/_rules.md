## Rules for this stage

- You audit the repository at `$TARGET`. The scope is `$SCOPE` (a path relative to the repository root).
- Write files only under `$OUT`. Do not change, create, or delete anything in the repository.
- Earlier stages wrote their results under `$RUN`. Read them when this prompt names them.
- When a skill tells you to run a slash command or a workflow that this session does not have,
  do the same work yourself. Follow the skill text and use its task agents when they exist.
- Cite every claim with `path:line`. When you cannot cite it, record it as an open question.
- When this stage writes `findings.jsonl`, write one JSON object per line with exactly these keys:
  `title` (string), `severity` (`critical`, `high`, `medium`, `low`, or `info`), `file` (path
  relative to the repository root), `line` (integer), `claim` (what is wrong), `evidence` (why
  you believe it, with citations). Write an empty file when you find nothing.
- The last line you print must be `DONE`.
