#!/usr/bin/env bash
set -euo pipefail

intent_compiler_target="${1:-all}"
if ! intent_compiler_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"; then
  echo "Could not locate the Intent Compiler source directory." >&2
  exit 1
fi
intent_compiler_plugin="${intent_compiler_root}/plugins/intent-compiler"

install_codex() {
  if command -v codex >/dev/null 2>&1; then
    if ! codex plugin marketplace add "${intent_compiler_root}" >/dev/null 2>&1; then
      echo "Codex marketplace registration failed." >&2
      return 1
    fi
    if ! codex plugin add "intent-compiler@intent-compiler-local" >/dev/null 2>&1; then
      echo "Codex plugin installation failed." >&2
      return 1
    fi
  else
    intent_compiler_codex_root="${CODEX_HOME:-${HOME}/.codex}"
    if ! mkdir -p "${intent_compiler_codex_root}/skills/compile-intent" 2>/dev/null; then
      echo "Could not create the current user's Codex skill directory." >&2
      return 1
    fi
    if ! cp -R "${intent_compiler_plugin}/skills/compile-intent/." "${intent_compiler_codex_root}/skills/compile-intent/" 2>/dev/null; then
      echo "Could not copy the shared skill into the current user's Codex directory." >&2
      return 1
    fi
    if ! { printf '%s\n' 'intent-compiler-marker-v1' > "${intent_compiler_codex_root}/skills/compile-intent/.intent-compiler-installed-by-repo"; } 2>/dev/null; then
      echo "Could not write the privacy-safe installation marker." >&2
      return 1
    fi
    echo "Codex CLI not found; installed the shared skill in the current user's Codex directory."
  fi
}

install_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "Claude Code CLI not found." >&2
    exit 1
  fi
  if ! claude plugin validate "${intent_compiler_root}" --strict >/dev/null 2>&1; then
    echo "Claude marketplace validation failed." >&2
    return 1
  fi
  if ! claude plugin marketplace add "${intent_compiler_root}" --scope user >/dev/null 2>&1; then
    echo "Claude marketplace registration failed." >&2
    return 1
  fi
  if claude plugin install --help 2>&1 | grep -q -- '--yes'; then
    if ! claude plugin install "intent-compiler@intent-compiler-plugins" --scope user --yes >/dev/null 2>&1 && \
       ! claude plugin update "intent-compiler@intent-compiler-plugins" --scope user >/dev/null 2>&1; then
      echo "Claude plugin installation and update both failed." >&2
      return 1
    fi
  else
    if ! claude plugin install "intent-compiler@intent-compiler-plugins" --scope user >/dev/null 2>&1 && \
       ! claude plugin update "intent-compiler@intent-compiler-plugins" --scope user >/dev/null 2>&1; then
      echo "Claude plugin installation and update both failed." >&2
      return 1
    fi
  fi
}

case "${intent_compiler_target}" in
  all)
    install_codex
    install_claude
    ;;
  gpt|codex)
    install_codex
    ;;
  claude)
    install_claude
    ;;
  *)
    echo "Usage: ./install.sh [all|gpt|codex|claude]" >&2
    exit 2
    ;;
esac

echo "Intent Compiler installation complete. Start a new agent session before testing."
