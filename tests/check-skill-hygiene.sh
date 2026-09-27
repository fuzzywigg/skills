#!/usr/bin/env bash
# Require SKILL.md in each non-deprecated skill package directory.
# Walks skills/{engineering,misc,personal,productivity,in-progress}/*/
# Skips deprecated/ and category roots (README.md only).
# Run from anywhere: bash tests/check-skill-hygiene.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CATEGORIES=(engineering misc personal productivity in-progress)

checked=0
missing=()

shopt -s nullglob

echo "== skill package hygiene (SKILL.md) =="

for category in "${CATEGORIES[@]}"; do
  category_dir="$ROOT/skills/$category"
  if [[ ! -d "$category_dir" ]]; then
    echo "  SKIP skills/$category (category missing)"
    continue
  fi

  packages=("$category_dir"/*/)
  if (( ${#packages[@]} == 0 )); then
    echo "  SKIP skills/$category (no packages)"
    continue
  fi

  for package_dir in "${packages[@]}"; do
    package_name="$(basename "$package_dir")"
    rel="skills/$category/$package_name"
    if [[ -f "$package_dir/SKILL.md" ]]; then
      checked=$((checked + 1))
      echo "  OK  $rel"
    else
      missing+=("$rel")
      echo "  FAIL $rel (missing SKILL.md)"
    fi
  done
done

echo
echo "Checked $checked package(s) under skills/{engineering,misc,personal,productivity,in-progress}/"

if (( ${#missing[@]} > 0 )); then
  echo "Missing SKILL.md in ${#missing[@]} package(s):"
  for rel in "${missing[@]}"; do
    echo "  - $rel"
  done
  exit 1
fi

echo "All checked packages have SKILL.md."
