#!/usr/bin/env bash
# =============================================================================
# setup-ai-standards.sh
#
# Bootstraps a new (or existing) repository with the AI development standards
# from the ai-dev-standards repo.
#
# Token-reducing rules ("Context discipline") are included automatically in
# every CLAUDE.md / copilot-instructions.md file this script installs.
#
# Usage:
#   ./setup-ai-standards.sh [TARGET_DIR]
#
#   TARGET_DIR  - path to the repo to set up (default: current directory)
# =============================================================================

set -euo pipefail

# --------------- helpers -----------------------------------------------------

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
success() { echo -e "${GREEN}[done]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }

ask() {
  # ask <prompt> <varname>
  local prompt="$1" varname="$2"
  read -rp "$(echo -e "${BOLD}${prompt}${RESET} ")" "$varname"
}

pick() {
  # pick <prompt> <options...>  — returns chosen option on stdout
  local prompt="$1"; shift
  local options=("$@")
  echo -e "${BOLD}${prompt}${RESET}"
  local i=1
  for opt in "${options[@]}"; do
    echo "  $i) $opt"
    ((i++))
  done
  local choice
  while true; do
    read -rp "Choice [1-${#options[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      echo "${options[$((choice-1))]}"
      return
    fi
    warn "Please enter a number between 1 and ${#options[@]}."
  done
}

# --------------- locate this script's repo -----------------------------------

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$STANDARDS_DIR/general/CLAUDE.md" ]]; then
  echo "ERROR: Cannot find general/CLAUDE.md relative to this script."
  echo "       Run this script from inside the ai-dev-standards repo."
  exit 1
fi

# --------------- target directory --------------------------------------------

TARGET="${1:-$(pwd)}"
if [[ ! -d "$TARGET" ]]; then
  echo "ERROR: Target directory '$TARGET' does not exist."
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

echo ""
echo -e "${BOLD}━━━ AI Dev Standards Setup ━━━${RESET}"
echo ""
info "Standards source : $STANDARDS_DIR"
info "Target repo      : $TARGET"
echo ""

# --------------- project type ------------------------------------------------

PROJECT_TYPE="$(pick "What type of project is this?" \
  "general  (no platform-specific rules)" \
  "web      (pnpm workspaces / Tailwind)" \
  "mobile   (React Native / Expo)")"

PROJECT_TYPE="${PROJECT_TYPE%% *}"   # strip description, keep first word

# --------------- AI tooling --------------------------------------------------

AI_TOOLS="$(pick "Which AI tool(s) do you want to configure?" \
  "claude   (Claude Code — copies CLAUDE.md + .claude/agents/)" \
  "copilot  (GitHub Copilot — copies .github/copilot-instructions.md + agents)" \
  "both     (install both)")"

AI_TOOLS="${AI_TOOLS%% *}"

# --------------- copy functions ----------------------------------------------

copy_file() {
  # copy_file <src> <dst>
  local src="$1" dst="$2"
  local dst_dir; dst_dir="$(dirname "$dst")"
  mkdir -p "$dst_dir"
  if [[ -f "$dst" ]]; then
    warn "Already exists, skipping: ${dst#"$TARGET/"}"
  else
    cp "$src" "$dst"
    success "Copied → ${dst#"$TARGET/"}"
  fi
}

copy_dir() {
  # copy_dir <src_dir> <dst_dir>
  local src_dir="$1" dst_dir="$2"
  mkdir -p "$dst_dir"
  for f in "$src_dir"/*.md; do
    [[ -e "$f" ]] || continue
    local fname; fname="$(basename "$f")"
    copy_file "$f" "$dst_dir/$fname"
  done
}

# --------------- install Claude Code files -----------------------------------

install_claude() {
  echo ""
  info "─── Installing Claude Code files ───"

  copy_file "$STANDARDS_DIR/general/CLAUDE.md" "$TARGET/CLAUDE.md"
  copy_dir  "$STANDARDS_DIR/general/agents"    "$TARGET/.claude/agents"

  if [[ "$PROJECT_TYPE" == "mobile" ]]; then
    copy_file "$STANDARDS_DIR/mobile/RULES.md" "$TARGET/docs/mobile-rules.md"
    copy_file "$STANDARDS_DIR/mobile/agents/device-qa.md" \
              "$TARGET/.claude/agents/device-qa.md"
    info "Remember to add 'See docs/mobile-rules.md' to CLAUDE.md"
  fi

  if [[ "$PROJECT_TYPE" == "web" ]]; then
    copy_file "$STANDARDS_DIR/web/RULES.md" "$TARGET/docs/web-rules.md"
    info "Remember to add 'See docs/web-rules.md' to CLAUDE.md"
  fi
}

# --------------- install GitHub Copilot files --------------------------------

install_copilot() {
  echo ""
  info "─── Installing GitHub Copilot files ───"

  copy_file "$STANDARDS_DIR/copilot/copilot-instructions.md" \
            "$TARGET/.github/copilot-instructions.md"

  copy_dir  "$STANDARDS_DIR/copilot/agents" \
            "$TARGET/.github/agents"

  if [[ "$PROJECT_TYPE" == "mobile" ]]; then
    copy_file "$STANDARDS_DIR/copilot/instructions/mobile.instructions.md" \
              "$TARGET/.github/instructions/mobile.instructions.md"
    info "Add '# files: **/*.{ts,tsx}' applyTo glob to mobile.instructions.md if needed"
  fi

  if [[ "$PROJECT_TYPE" == "web" ]]; then
    copy_file "$STANDARDS_DIR/copilot/instructions/web.instructions.md" \
              "$TARGET/.github/instructions/web.instructions.md"
  fi

  echo ""
  info "─── Generating .claudeignore ───"
  local ignore_file="$TARGET/.claudeignore"
  if [[ ! -f "$ignore_file" ]]; then
    cat > "$ignore_file" << 'EOF'
# generated / vendored
node_modules/
.pnp/
dist/
build/
out/
.next/
.expo/
.turbo/
coverage/
*.tsbuildinfo

# lockfiles
package-lock.json
yarn.lock
pnpm-lock.yaml
bun.lockb

# binaries / media
*.png
*.jpg
*.jpeg
*.gif
*.webp
*.svg
*.ico
*.mp4
*.mov
*.pdf
*.woff
*.woff2

# secrets / IDE
.env
.env.*
!.env.example
.DS_Store
.idea/
.vscode/
*.log
EOF
    success "Created → .claudeignore"
  else
    warn "Already exists, skipping: .claudeignore"
  fi
}

# --------------- run ---------------------------------------------------------

case "$AI_TOOLS" in
  claude)  install_claude ;;
  copilot) install_copilot ;;
  both)    install_claude; install_copilot ;;
esac

echo ""
echo -e "${BOLD}━━━ Token-reducing rules & tools (already included in files above) ━━━${RESET}"
echo ""
echo "  The standards enforce extreme token discipline. Review these mechanisms:"
echo ""
echo "  • Code Graph Context (CGC): Use an MCP server for symbol-level codebase"
echo "    queries instead of raw file reading. Highly recommended."
echo "  • Scoped Instructions: Use 'applyTo' in Copilot to only inject rules"
echo "    when matching files are open."
echo "  • Context Discipline: Baked into CLAUDE.md & copilot-instructions.md:"
echo "    - Read slices, not full files."
echo "    - Send broad searches to subagents that return conclusions."
echo "    - Minify large tool outputs before returning them to context."
echo "    - Don't paste large diffs — say what changed and where."
echo ""

# --------------- remind about placeholders -----------------------------------

echo -e "${BOLD}━━━ Next steps ━━━${RESET}"
echo ""
echo "  1. Fill in every <...> placeholder in the copied files:"
if [[ "$AI_TOOLS" == "claude" || "$AI_TOOLS" == "both" ]]; then
  echo "       $TARGET/CLAUDE.md"
fi
if [[ "$AI_TOOLS" == "copilot" || "$AI_TOOLS" == "both" ]]; then
  echo "       $TARGET/.github/copilot-instructions.md"
fi
echo ""
echo "  2. Delete any sections that don't apply to this project."
echo "  3. Add project-specific invariants under '## Invariants'."
echo "  4. Commit everything so agents pick it up on the first run."
echo ""
success "Setup complete."
