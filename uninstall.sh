#!/usr/bin/env bash
set -euo pipefail

intent_compiler_target="${1:-all}"
if ! intent_compiler_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"; then
  echo "Could not locate the Intent Compiler source directory." >&2
  exit 1
fi

uninstall_codex() {
  echo "==> Uninstalling GPT / ChatGPT / Codex integration"

  if command -v codex >/dev/null 2>&1; then
    intent_compiler_plugin_help="$(codex plugin --help 2>&1 || true)"
    if printf '%s\n' "${intent_compiler_plugin_help}" | grep -Eq '^[[:space:]]*uninstall([[:space:]]|$)'; then
      codex plugin uninstall "intent-compiler@intent-compiler-local" >/dev/null 2>&1 || true
    elif printf '%s\n' "${intent_compiler_plugin_help}" | grep -Eq '^[[:space:]]*remove([[:space:]]|$)'; then
      codex plugin remove "intent-compiler@intent-compiler-local" >/dev/null 2>&1 || true
    fi

    intent_compiler_marketplace_help="$(codex plugin marketplace --help 2>&1 || true)"
    if printf '%s\n' "${intent_compiler_marketplace_help}" | grep -Eq '^[[:space:]]*remove([[:space:]]|$)'; then
      codex plugin marketplace remove "intent-compiler-local" >/dev/null 2>&1 || true
    elif printf '%s\n' "${intent_compiler_marketplace_help}" | grep -Eq '^[[:space:]]*delete([[:space:]]|$)'; then
      codex plugin marketplace delete "intent-compiler-local" >/dev/null 2>&1 || true
    elif printf '%s\n' "${intent_compiler_marketplace_help}" | grep -Eq '^[[:space:]]*rm([[:space:]]|$)'; then
      codex plugin marketplace rm "intent-compiler-local" >/dev/null 2>&1 || true
    fi
  fi

  intent_compiler_codex_root="${CODEX_HOME:-${HOME}/.codex}"
  intent_compiler_skill="${intent_compiler_codex_root}/skills/compile-intent"
  intent_compiler_marker="${intent_compiler_skill}/.intent-compiler-installed-by-repo"
  if [[ -f "${intent_compiler_marker}" ]]; then
    if ! intent_compiler_expected_parent="$(cd "${intent_compiler_codex_root}/skills" 2>/dev/null && pwd -P)" || \
       ! intent_compiler_actual_parent="$(cd "$(dirname "${intent_compiler_skill}")" 2>/dev/null && pwd -P)"; then
      echo "Could not verify the Codex fallback directory safely." >&2
      return 1
    fi
    if [[ "$(basename "${intent_compiler_skill}")" != "compile-intent" || "${intent_compiler_actual_parent}" != "${intent_compiler_expected_parent}" ]]; then
      echo "Refusing to remove an unexpected plugin directory." >&2
      exit 1
    fi
    if ! rm -rf -- "${intent_compiler_skill}" 2>/dev/null; then
      echo "Could not remove the Codex fallback skill." >&2
      return 1
    fi
    echo "Removed the Codex fallback skill."
  else
    echo "Codex fallback skill is already absent or was not installed by this repository."
  fi
}

uninstall_claude() {
  echo "==> Uninstalling Claude Code integration"
  if ! command -v claude >/dev/null 2>&1; then
    echo "Claude Code CLI not found; its plugin registry cannot be safely changed." >&2
    exit 1
  fi

  if claude plugin list --json 2>/dev/null | grep -Fq 'intent-compiler@intent-compiler-plugins'; then
    if ! claude plugin uninstall "intent-compiler@intent-compiler-plugins" --scope user >/dev/null 2>&1; then
      echo "Claude plugin uninstall failed." >&2
      return 1
    fi
  else
    echo "Claude plugin is already absent."
  fi

  if ! intent_compiler_marketplaces="$(claude plugin marketplace list --json 2>/dev/null)"; then
    echo "Could not inspect Claude marketplaces safely." >&2
    return 1
  fi
  intent_compiler_marketplace_check=127
  if command -v python3 >/dev/null 2>&1; then
    if INTENT_COMPILER_ROOT="${intent_compiler_root}" INTENT_COMPILER_MARKETPLACES="${intent_compiler_marketplaces}" python3 2>/dev/null <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["INTENT_COMPILER_ROOT"]).resolve()
items = json.loads(os.environ["INTENT_COMPILER_MARKETPLACES"])
match = next((item for item in items if item.get("name") == "intent-compiler-plugins"), None)
if match is None:
    raise SystemExit(2)
source = match.get("path") or match.get("installLocation")
if source is None or Path(source).resolve() != root:
    raise SystemExit(3)
PY
    then
      intent_compiler_marketplace_check=0
    else
      intent_compiler_marketplace_check=$?
    fi
  elif command -v node >/dev/null 2>&1; then
    if INTENT_COMPILER_ROOT="${intent_compiler_root}" INTENT_COMPILER_MARKETPLACES="${intent_compiler_marketplaces}" node -e '
      const path = require("path");
      const items = JSON.parse(process.env.INTENT_COMPILER_MARKETPLACES);
      const match = items.find((item) => item.name === "intent-compiler-plugins");
      if (!match) process.exit(2);
      const source = match.path || match.installLocation;
      if (!source || path.resolve(source) !== path.resolve(process.env.INTENT_COMPILER_ROOT)) process.exit(3);
    ' 2>/dev/null
    then
      intent_compiler_marketplace_check=0
    else
      intent_compiler_marketplace_check=$?
    fi
  fi

  if [[ ${intent_compiler_marketplace_check} -eq 0 ]]; then
    if ! claude plugin marketplace remove "intent-compiler-plugins" --scope user >/dev/null 2>&1; then
      echo "Claude marketplace removal failed." >&2
      return 1
    fi
  elif [[ ${intent_compiler_marketplace_check} -eq 2 ]]; then
    echo "Claude marketplace is already absent."
  elif [[ ${intent_compiler_marketplace_check} -eq 127 ]]; then
    echo "Preserving marketplace intent-compiler-plugins because Python 3 and Node.js are unavailable for safe path verification." >&2
  else
    echo "Preserving marketplace intent-compiler-plugins because it points elsewhere." >&2
  fi
}

case "${intent_compiler_target}" in
  all)
    uninstall_codex
    uninstall_claude
    ;;
  gpt|codex)
    uninstall_codex
    ;;
  claude)
    uninstall_claude
    ;;
  *)
    echo "Usage: ./uninstall.sh [all|gpt|codex|claude]" >&2
    exit 2
    ;;
esac

echo "Intent Compiler uninstall complete. The source repository was preserved."
