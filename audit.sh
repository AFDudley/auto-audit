#!/usr/bin/env bash
# audit.sh — run a staged security audit of one repository with omp agents.
#
#   audit.sh <repo> [scope] [spec]
#
#   repo   path to a git checkout
#   scope  path inside the repo to audit (default: the whole repo)
#   spec   path inside the repo to a specification document (enables the spec stage)
#
# Each stage is one `omp -p` run with one model tier and the skills that the stage needs.
# A stage writes files under the run directory. A gate checks those files before the next
# stage starts. Any failure stops the run. See README.md.
set -euo pipefail

usage() { echo "usage: audit.sh <repo> [scope] [spec]" >&2; exit 2; }
if [ $# -lt 1 ] || [ $# -gt 3 ]; then usage; fi

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tiers.env
. "$HERE/tiers.env"

TARGET=$(cd "$1" && pwd)
SCOPE=${2:-.}
SPEC=${3:-}
git -C "$TARGET" rev-parse --git-dir >/dev/null
[ -e "$TARGET/$SCOPE" ] || { echo "audit.sh: scope $SCOPE does not exist in $TARGET" >&2; exit 2; }
[ -z "$SPEC" ] || [ -f "$TARGET/$SPEC" ] || { echo "audit.sh: spec $SPEC does not exist in $TARGET" >&2; exit 2; }

RUN="${AUDIT_RUNS:-$HERE/.scratch/runs}/$(basename "$TARGET")-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
export TARGET SCOPE SPEC RUN

log() { echo "[$(date -u +%H:%M:%S)] $*" >&2; }
fail() { echo "audit.sh: $*" >&2; exit 1; }

# ---- manifest: what this run audited, and with what ----
{
  jq -n \
    --arg target "$TARGET" --arg scope "$SCOPE" --arg spec "$SPEC" \
    --arg commit "$(git -C "$TARGET" rev-parse HEAD)" \
    --arg dirty "$(git -C "$TARGET" status --porcelain | wc -l | tr -d ' ')" \
    --arg omp "$(omp --version 2>&1 | head -1)" \
    --arg fast "$AUDIT_MODEL_FAST" --arg work "$AUDIT_MODEL_WORK" \
    --arg deep "$AUDIT_MODEL_DEEP" --arg check "$AUDIT_MODEL_CHECK" \
    --arg plugins "$(omp plugin list | grep '@')" \
    --arg started "$(date -u +%FT%TZ)" \
    '{target: $target, scope: $scope, spec: $spec, commit: $commit, uncommitted_files: ($dirty|tonumber),
      omp: $omp, models: {fast: $fast, work: $work, deep: $deep, check: $check},
      plugins: ($plugins | split("\n") | map(gsub("^ +"; ""))), started: $started}'
} > "$RUN/manifest.json"
log "run directory: $RUN"

# ---- one stage = one omp run ----
# stage <name> <template> <model> <cost> <thinking> <skills, comma-separated, or "-" for none>
stage() {
  local name=$1 template=$2 model=$3 cost=$4 thinking=$5 skills=$6
  OUT="$RUN/$name"; export OUT
  mkdir -p "$OUT"
  local prompt skill_args
  # The single quotes are intended: envsubst substitutes only the variables named in this list.
  # shellcheck disable=SC2016
  prompt=$(cat "$HERE/prompts/$template.md" "$HERE/prompts/_rules.md" \
    | envsubst '$TARGET $SCOPE $SPEC $RUN $OUT $PENDING $CONFIRMED $KNOWN')
  if [ "$skills" = "-" ]; then skill_args=(--no-skills); else skill_args=(--skills "$skills"); fi
  log "stage $name: $model, cost limit \$$cost"
  # --session-dir keeps the full session (every tool call) in the stage directory.
  # transcript.txt holds only the agent's final message and omp's warnings.
  if ! omp -p --session-dir "$OUT/session" --cwd "$TARGET" --model "$model" --thinking "$thinking" \
      "${skill_args[@]}" --max-cost "$cost" --max-time "$AUDIT_MAX_TIME" --auto-approve \
      "$prompt" > "$OUT/transcript.txt" 2>&1; then
    tail -20 "$OUT/transcript.txt" >&2
    fail "stage $name: omp failed (see $OUT/transcript.txt and $OUT/session/)"
  fi
  grep -v '^[[:space:]]*$' "$OUT/transcript.txt" | tail -1 | tr -d '[:space:]' | grep -qx 'DONE' \
    || fail "stage $name: the agent did not print DONE as its last line"
}

# ---- gates ----
need_file() { [ -s "$1" ] || fail "gate: $1 is missing or empty"; }

# need_findings <file>: present (may be empty), one valid finding object per line.
need_findings() {
  [ -f "$1" ] || fail "gate: $1 is missing"
  jq -e -s 'all(.[];
      (keys == ["claim","evidence","file","line","severity","title"])
      and (.severity | IN("critical","high","medium","low","info"))
      and (.line | type == "number"))' "$1" >/dev/null \
    || fail "gate: $1 has a line that is not a valid finding"
}

# need_verdicts <verdicts> <pending>: one valid verdict for every id in pending.
need_verdicts() {
  jq -e -s 'all(.[]; (.verdict | IN("TRUE_POSITIVE","FALSE_POSITIVE"))
      and (.severity | IN("critical","high","medium","low","info")) and (.reason | length > 0))' "$1" >/dev/null \
    || fail "gate: $1 has a line that is not a valid verdict"
  diff <(jq -r .id "$2" | sort) <(jq -r .id "$1" | sort) >/dev/null \
    || fail "gate: $1 does not have exactly one verdict for each finding in $2"
}

# merge_findings <stage dirs...>: append new findings to $RUN/findings.jsonl with ids,
# and print the path of a file that holds only the new ones.
merge_findings() {
  local new="$RUN/.new.jsonl" n
  n=$( [ -f "$RUN/findings.jsonl" ] && wc -l < "$RUN/findings.jsonl" || echo 0)
  : > "$new"
  for d in "$@"; do
    [ -f "$d/findings.jsonl" ] || continue
    jq -c --arg stage "$(basename "$d")" '. + {stage: $stage}' "$d/findings.jsonl" >> "$new"
  done
  jq -c --argjson n "$n" -s 'to_entries[] | .value + {id: ("F" + ((.key + $n + 1) | tostring))}' "$new" > "$new.ids"
  mv "$new.ids" "$new"
  cat "$new" >> "$RUN/findings.jsonl"
  echo "$new"
}

# ---- 1. inventory ----
stage inventory inventory "$AUDIT_MODEL_FAST" "$AUDIT_COST_FAST" low 'trailmark-summary,supply-chain-risk-auditor'
need_file "$RUN/inventory/INVENTORY.md"; need_findings "$RUN/inventory/findings.jsonl"

# ---- 2. context ----
stage context context "$AUDIT_MODEL_DEEP" "$AUDIT_COST_DEEP" high audit-context-building
need_file "$RUN/context/DOSSIER.md"
grep -q '^## Unenforced assumptions' "$RUN/context/DOSSIER.md" || fail "gate: DOSSIER.md has no Unenforced assumptions section"
grep -q '^## Open questions' "$RUN/context/DOSSIER.md" || fail "gate: DOSSIER.md has no Open questions section"

# ---- 3. hunting passes, in parallel ----
hunts=(entry static defaults)
has_solidity=$(git -C "$TARGET" ls-files -- "$SCOPE" | grep -c '\.sol$' || true)
[ "$has_solidity" -gt 0 ] && hunts+=(contracts dimensional)
[ -n "$SPEC" ] && hunts+=(spec)
log "hunting passes: ${hunts[*]}"

hunt() {
  case $1 in
    entry)       stage entry entry "$AUDIT_MODEL_WORK" "$AUDIT_COST_WORK" medium entry-point-analyzer ;;
    static)      stage static static "$AUDIT_MODEL_WORK" "$AUDIT_COST_WORK" medium 'semgrep,sarif-parsing' ;;
    defaults)    stage defaults defaults "$AUDIT_MODEL_WORK" "$AUDIT_COST_WORK" medium insecure-defaults ;;
    dimensional) stage dimensional dimensional "$AUDIT_MODEL_WORK" "$AUDIT_COST_WORK" medium dimensional-analysis ;;
    contracts)   stage contracts contracts "$AUDIT_MODEL_DEEP" "$AUDIT_COST_DEEP" high 'secure-workflow-guide,token-integration-analyzer' ;;
    spec)        stage spec spec "$AUDIT_MODEL_DEEP" "$AUDIT_COST_DEEP" high spec-to-code-compliance ;;
  esac
  need_findings "$RUN/$1/findings.jsonl"
}
pids=()
for h in "${hunts[@]}"; do hunt "$h" & pids+=($!); done
status=0
for p in "${pids[@]}"; do wait "$p" || status=1; done
[ $status -eq 0 ] || fail "a hunting pass failed"

# ---- 4. merge ----
: > "$RUN/findings.jsonl"; : > "$RUN/verdicts.jsonl"
dirs=("$RUN/inventory"); for h in "${hunts[@]}"; do dirs+=("$RUN/$h"); done
PENDING=$(merge_findings "${dirs[@]}"); export PENDING
log "findings to verify: $(wc -l < "$PENDING")"

# ---- 5 and 6. verify, then hunt variants of confirmed findings, until no new finding ----
round=1
while [ -s "$PENDING" ]; do
  cp "$PENDING" "$RUN/pending-$round.jsonl"; PENDING="$RUN/pending-$round.jsonl"; export PENDING
  stage "verify-$round" verify "$AUDIT_MODEL_CHECK" "$AUDIT_COST_CHECK" high fp-check
  need_verdicts "$RUN/verify-$round/verdicts.jsonl" "$PENDING"
  cat "$RUN/verify-$round/verdicts.jsonl" >> "$RUN/verdicts.jsonl"

  CONFIRMED="$RUN/confirmed-$round.jsonl"; KNOWN="$RUN/findings.jsonl"; export CONFIRMED KNOWN
  jq -c --slurpfile v "$RUN/verify-$round/verdicts.jsonl" \
    'select(.id as $id | any($v[]; .id == $id and .verdict == "TRUE_POSITIVE"))' "$PENDING" > "$CONFIRMED"
  log "round $round: $(wc -l < "$CONFIRMED") of $(wc -l < "$PENDING") confirmed"
  [ -s "$CONFIRMED" ] || break

  stage "variants-$round" variants "$AUDIT_MODEL_WORK" "$AUDIT_COST_WORK" medium variant-analysis
  need_findings "$RUN/variants-$round/findings.jsonl"
  PENDING=$(merge_findings "$RUN/variants-$round"); export PENDING
  round=$((round + 1))
done

# ---- 7. report ----
stage report report "$AUDIT_MODEL_DEEP" "$AUDIT_COST_DEEP" high -
need_file "$RUN/report/REPORT.md"
log "done: $RUN/report/REPORT.md"
