#!/usr/bin/env bash
# audit-all.sh — audit a repository component by component, in the order of a triage file.
#
#   audit-all.sh <repo> <triage-file> [max-components]
#
# The triage file ranks the components of the repository. See README.md for its format.
# Before it audits anything, this script checks that every tracked source file belongs to
# exactly one triage entry (the longest matching path wins).
#
# It runs audit.sh once per component, highest rank first, one at a time. It reuses a completed
# run with the same commit, scope, and spec, so after a failure you can run it again and it
# continues with the failed component. It writes COVERAGE.md after each component.
set -euo pipefail

usage() { echo "usage: audit-all.sh <repo> <triage-file> [max-components]" >&2; exit 2; }
if [ $# -lt 2 ] || [ $# -gt 3 ]; then usage; fi
fail() { echo "audit-all.sh: $*" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
TARGET=$(cd "$1" && pwd)
TRIAGE=$(realpath "$2")
MAX=${3:-0}
[[ $MAX =~ ^[0-9]+$ ]] || usage
COMMIT=$(git -C "$TARGET" rev-parse HEAD)
RUNS="${AUDIT_RUNS:-$HERE/.scratch/runs}"
ALL="$RUNS/$(basename "$TARGET")-all-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$ALL"
cp "$TRIAGE" "$ALL/triage.txt"

# Source files: the extensions that the audit stages read.
SRC_RE='\.(mjs|cjs|js|jsx|ts|tsx|sol|py|sh|go|rs)$'

trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; s=${s%"${s##*[![:space:]]}"}; printf '%s' "$s"; }

# ---- parse the triage ----
kinds=(); paths=(); specs=(); reasons=()
while IFS='|' read -r k p s r; do
  k=$(trim "$k")
  [[ -z $k || $k == \#* ]] && continue
  p=$(trim "$p"); s=$(trim "$s"); r=$(trim "$r")
  [[ $k == component || $k == exclude ]] || fail "triage: unknown kind '$k'"
  [ -e "$TARGET/$p" ] || fail "triage: path $p does not exist in $TARGET"
  [[ $s == - || -f "$TARGET/$s" ]] || fail "triage: spec $s does not exist in $TARGET"
  [ -n "$r" ] || fail "triage: $p has no reason"
  for q in "${paths[@]}"; do [ "$q" != "$p" ] || fail "triage: $p is listed twice"; done
  kinds+=("$k"); paths+=("$p"); specs+=("$s"); reasons+=("$r")
done < "$TRIAGE"
[ ${#paths[@]} -gt 0 ] || fail "triage: no entries"

# ---- coverage gate: every tracked source file has exactly one owner ----
files=(); lines=(); unowned=()
for i in "${!paths[@]}"; do files[i]=0; lines[i]=0; done
while IFS= read -r f; do
  best=-1; bestlen=-1
  for i in "${!paths[@]}"; do
    p=${paths[i]}
    if [[ $f == "$p" || $f == "$p"/* ]] && (( ${#p} > bestlen )); then best=$i; bestlen=${#p}; fi
  done
  if (( best < 0 )); then unowned+=("$f"); continue; fi
  files[best]=$(( files[best] + 1 ))
  lines[best]=$(( lines[best] + $(wc -l < "$TARGET/$f") ))
done < <(git -C "$TARGET" ls-files | grep -E "$SRC_RE")
if [ ${#unowned[@]} -gt 0 ]; then
  printf '  %s\n' "${unowned[@]}" >&2
  fail "triage: ${#unowned[@]} tracked source files belong to no entry (listed above)"
fi
for i in "${!paths[@]}"; do
  [ "${files[i]}" -gt 0 ] || fail "triage: ${paths[i]} owns no source file"
done

# ---- find a completed run for one component at this commit ----
find_run() {
  local scope=$1 spec=$2 m d best=""
  [ "$spec" = "-" ] && spec=""
  for m in "$RUNS"/*/manifest.json; do
    [ -f "$m" ] || continue
    d=$(dirname "$m")
    [ -s "$d/report/REPORT.md" ] || continue
    jq -e --arg t "$TARGET" --arg c "$COMMIT" --arg s "$scope" --arg sp "$spec" \
      '.target == $t and .commit == $c and .scope == $s and .spec == $sp' "$m" >/dev/null || continue
    best=$d   # run names end in a UTC time, so the last match in glob order is the newest
  done
  printf '%s' "$best"
}

confirmed() {  # confirmed findings of one run, by severity, highest first
  jq -r -s '[.[] | select(.verdict == "TRUE_POSITIVE") | .severity] as $s
    | [("critical","high","medium","low","info") as $l | ($s | map(select(. == $l)) | length) as $n
       | select($n > 0) | "\($n) \($l)"] | if length == 0 then "none" else join(", ") end' "$1/verdicts.jsonl"
}

# ---- COVERAGE.md ----
status=(); run=()
write_coverage() {
  local i rank=0 n_comp=0 n_done=0 l_comp=0 l_done=0 l_excl=0 out="$ALL/COVERAGE.md"
  for i in "${!paths[@]}"; do
    if [ "${kinds[i]}" = component ]; then
      n_comp=$((n_comp + 1)); l_comp=$((l_comp + lines[i]))
      if [[ ${status[i]:-} == audited* ]]; then n_done=$((n_done + 1)); l_done=$((l_done + lines[i])); fi
    else
      l_excl=$((l_excl + lines[i]))
    fi
  done
  {
    echo "# Coverage: $(basename "$TARGET") at ${COMMIT:0:7}"
    echo
    echo "**Audited $n_done of $n_comp components: $l_done of $l_comp source lines.** Excluded: $l_excl source lines."
    echo
    echo "| Rank | Component | Files | Lines | Status | Confirmed findings | Run |"
    echo "|---|---|---|---|---|---|---|"
    for i in "${!paths[@]}"; do
      [ "${kinds[i]}" = component ] || continue
      rank=$((rank + 1))
      local found="-" where="-"
      if [ -n "${run[i]:-}" ]; then found=$(confirmed "${run[i]}"); where="\`${run[i]#"$RUNS"/}\`"; fi
      echo "| $rank | \`${paths[i]}\` | ${files[i]} | ${lines[i]} | ${status[i]:-not run} | $found | $where |"
    done
    echo
    echo "## Reasons for the ranking"
    echo
    rank=0
    for i in "${!paths[@]}"; do
      [ "${kinds[i]}" = component ] || continue
      rank=$((rank + 1)); echo "$rank. \`${paths[i]}\`: ${reasons[i]}"
    done
    echo
    echo "## Excluded"
    echo
    echo "| Path | Files | Lines | Reason |"
    echo "|---|---|---|---|"
    for i in "${!paths[@]}"; do
      [ "${kinds[i]}" = exclude ] || continue
      echo "| \`${paths[i]}\` | ${files[i]} | ${lines[i]} | ${reasons[i]} |"
    done
  } > "$out"
}

# ---- audit the components in rank order ----
rank=0
write_coverage
for i in "${!paths[@]}"; do
  [ "${kinds[i]}" = component ] || continue
  rank=$((rank + 1))
  if (( MAX > 0 && rank > MAX )); then status[i]="not run (limit $MAX)"; continue; fi
  d=$(find_run "${paths[i]}" "${specs[i]}")
  if [ -n "$d" ]; then
    status[i]="audited (reused)"; run[i]=$d
  else
    status[i]="running"; write_coverage
    args=("$TARGET" "${paths[i]}"); [ "${specs[i]}" = "-" ] || args+=("${specs[i]}")
    echo "audit-all.sh: rank $rank: ${paths[i]}" >&2
    if ! "$HERE/audit.sh" "${args[@]}"; then
      status[i]="failed"; write_coverage
      fail "rank $rank (${paths[i]}) failed. Run audit-all.sh again to continue. See $ALL/COVERAGE.md"
    fi
    d=$(find_run "${paths[i]}" "${specs[i]}")
    [ -n "$d" ] || fail "rank $rank: audit.sh succeeded but no completed run was found"
    status[i]="audited"; run[i]=$d
  fi
  write_coverage
done
echo "audit-all.sh: $ALL/COVERAGE.md" >&2
