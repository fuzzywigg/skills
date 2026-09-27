#!/usr/bin/env bash
# Offline fixture tests for the repo's executable shell scripts.
# Run from anywhere: bash tests/run-shell-tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
failures=()

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  OK  $label"
  else
    FAIL=$((FAIL + 1))
    failures+=("$label (expected='$expected' actual='$actual')")
    echo "  FAIL $label (expected='$expected' actual='$actual')"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  OK  $label"
  else
    FAIL=$((FAIL + 1))
    failures+=("$label (missing '$needle')")
    echo "  FAIL $label (missing '$needle')"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    PASS=$((PASS + 1))
    echo "  OK  $label"
  else
    FAIL=$((FAIL + 1))
    failures+=("$label (unexpected '$needle')")
    echo "  FAIL $label (unexpected '$needle')"
  fi
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  assert_eq "$label" "$expected" "$actual"
}

assert_symlink_to() {
  local label="$1" link="$2" expected_target="$3"
  if [[ -L "$link" ]]; then
    local resolved
    resolved="$(readlink -f "$link")"
    assert_eq "$label" "$expected_target" "$resolved"
  else
    FAIL=$((FAIL + 1))
    failures+=("$label (not a symlink: $link)")
    echo "  FAIL $label (not a symlink: $link)"
  fi
}

# ---------------------------------------------------------------------------
echo "== list-skills.sh =="

list_out="$("$ROOT/scripts/list-skills.sh")"
list_rc=$?
assert_exit "list-skills exits 0" "0" "$list_rc"
assert_contains "lists diagnose skill" "skills/engineering/diagnose/SKILL.md" "$list_out"
assert_contains "lists git-guardrails skill" "skills/misc/git-guardrails-claude-code/SKILL.md" "$list_out"
assert_contains "lists deprecated skills too" "skills/deprecated/qa/SKILL.md" "$list_out"

sorted="$(printf '%s\n' "$list_out" | sort)"
assert_eq "list-skills output is sorted" "$sorted" "$list_out"

# ---------------------------------------------------------------------------
echo "== link-skills.sh =="

link_home="$(mktemp -d)"
trap 'rm -rf "$link_home"' EXIT
export HOME="$link_home"

link_out="$(bash "$ROOT/scripts/link-skills.sh")"
link_rc=$?
assert_exit "link-skills exits 0" "0" "$link_rc"
assert_contains "link-skills reports diagnose" "linked diagnose ->" "$link_out"
assert_symlink_to "diagnose symlink target" \
  "$HOME/.claude/skills/diagnose" \
  "$ROOT/skills/engineering/diagnose"
assert_symlink_to "git-guardrails symlink target" \
  "$HOME/.claude/skills/git-guardrails-claude-code" \
  "$ROOT/skills/misc/git-guardrails-claude-code"

if [[ -e "$HOME/.claude/skills/qa" ]]; then
  FAIL=$((FAIL + 1))
  failures+=("deprecated skill qa should not be linked")
  echo "  FAIL deprecated skill qa should not be linked"
else
  PASS=$((PASS + 1))
  echo "  OK  deprecated skill qa is not linked"
fi

# Bail when ~/.claude/skills is a symlink into the repo
bad_home="$(mktemp -d)"
mkdir -p "$bad_home/.claude"
ln -s "$ROOT/skills" "$bad_home/.claude/skills"
HOME="$bad_home"
set +e
bail_err="$(bash "$ROOT/scripts/link-skills.sh" 2>&1 >/dev/null)"
bail_rc=$?
set -e
assert_exit "link-skills bails on dest symlink into repo" "1" "$bail_rc"
assert_contains "bail error mentions symlink" "symlink into this repo" "$bail_err"
rm -rf "$bad_home"
export HOME="$link_home"

# ---------------------------------------------------------------------------
echo "== block-dangerous-git.sh =="

BLOCK="$ROOT/skills/misc/git-guardrails-claude-code/scripts/block-dangerous-git.sh"

run_block() {
  local cmd="$1" rc
  set +e
  printf '%s' "{\"tool_input\":{\"command\":$(jq -Rn --arg c "$cmd" '$c')}}" | bash "$BLOCK" >/dev/null 2>&1
  rc=$?
  set -e
  echo "$rc"
}

assert_exit "allows safe git status" "0" "$(run_block 'git status')"
assert_exit "allows git commit" "0" "$(run_block 'git commit -m hello')"
assert_exit "blocks git push" "2" "$(run_block 'git push origin main')"
assert_exit "blocks git reset --hard" "2" "$(run_block 'git reset --hard HEAD')"
assert_exit "blocks git clean -fd" "2" "$(run_block 'git clean -fd')"
assert_exit "blocks git clean -f" "2" "$(run_block 'git clean -f')"
assert_exit "blocks git branch -D" "2" "$(run_block 'git branch -D feature')"
assert_exit "blocks push --force" "2" "$(run_block 'git push --force origin main')"
assert_exit "blocks reset --hard alias form" "2" "$(run_block 'something reset --hard')"

block_msg="$(printf '%s' '{"tool_input":{"command":"git push"}}' | bash "$BLOCK" 2>&1 >/dev/null || true)"
assert_contains "block message names pattern" "BLOCKED:" "$block_msg"

# ---------------------------------------------------------------------------
echo "== hitl-loop.template.sh =="

HITL="$ROOT/skills/engineering/diagnose/scripts/hitl-loop.template.sh"
# Three reads: step Enter, capture ERRORED, capture ERROR_MSG
set +e
hitl_out="$(printf '\ny\nnone\n' | bash "$HITL")"
hitl_rc=$?
set -e
assert_exit "hitl-loop exits 0 with piped answers" "0" "$hitl_rc"
assert_contains "prints ERRORED capture" "ERRORED=y" "$hitl_out"
assert_contains "prints ERROR_MSG capture" "ERROR_MSG=none" "$hitl_out"
assert_contains "prints Captured header" "--- Captured ---" "$hitl_out"

# ---------------------------------------------------------------------------
echo
echo "Passed: $PASS  Failed: $FAIL"
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${failures[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
echo "All shell fixture tests passed."
