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
#   ./setup-ai-standards.sh [TARGET_DIR] [OPTIONS]
#
# Options:
#   -p, --path <dir>            Path to the repo to set up (default: pwd)
#   -a, --agent <agent>         AI tool: claude, copilot, or both
#   -t, --type <type>           Project type: general, web, or mobile
#   --install-cgc <y/n>         Install Code Graph Context (CGC) for token reduction
#   --mcp <all|none>            MCP servers to add to .mcp.json (default: prompt)
#   --supabase-project-ref <r>  Include the Supabase MCP server with this ref
#   --install-mcp-tools <y/n>   Install CLI deps the MCP servers need (tree-sitter)
#   --js <y/n>                  Also install javascript/ (pnpm/Prettier tooling)
#
# .mcp.json and .claude/settings.json are only installed for -a claude|both —
# they're a Claude Code concept and have no Copilot equivalent.
#
# A PowerShell port of this script (setup-ai-standards.ps1, same flags in
# PascalCase) lives alongside it for Windows.
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

# Every prompt below routes through `ask`/`pick`. When stdin is not a TTY —
# CI, `curl | bash`, or an AI agent running the script — reading would hit EOF
# and `set -e` would abort the run partway through, leaving a half-configured
# repo. In that case each prompt logs and takes its documented default
# instead, so a fully-flagged non-interactive invocation never blocks and a
# partially-flagged one still completes.
INTERACTIVE=1
[[ -t 0 ]] || INTERACTIVE=0

# ask <varname> <default> <prompt text>
ask() {
  local varname="$1" default="$2" prompt="$3" reply
  if (( ! INTERACTIVE )); then
    printf -v "$varname" '%s' "$default"
    info "Non-interactive stdin — defaulting to '${default}': ${prompt}"
    return
  fi
  read -rp "$(echo -e "${BOLD}${prompt}${RESET} ")" reply
  printf -v "$varname" '%s' "${reply:-$default}"
}

# pick <prompt text> <default> <option>...
# The menu goes to stderr: this function's stdout is the caller's answer.
pick() {
  local prompt="$1" default="$2"; shift 2
  local options=("$@")
  if (( ! INTERACTIVE )); then
    info "Non-interactive stdin — defaulting to '${default}': ${prompt}" >&2
    echo "$default"
    return
  fi
  echo -e "${BOLD}${prompt}${RESET}" >&2
  local i=1
  for opt in "${options[@]}"; do
    echo "  $i) $opt" >&2
    ((i++))
  done
  local choice
  while true; do
    read -rp "Choice [1-${#options[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      echo "${options[$((choice-1))]}"
      return
    fi
    warn "Please enter a number between 1 and ${#options[@]}." >&2
  done
}

# --------------- argument parsing --------------------------------------------

TARGET=""
PROJECT_TYPE=""
AI_TOOLS=""
INSTALL_CGC=""
MCP_MODE=""
SUPABASE_PROJECT_REF=""
INSTALL_MCP_TOOLS=""
IS_JS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--path) TARGET="$2"; shift 2 ;;
    -a|--agent) AI_TOOLS="$2"; shift 2 ;;
    -t|--type) PROJECT_TYPE="$2"; shift 2 ;;
    --install-cgc) INSTALL_CGC="$2"; shift 2 ;;
    --mcp) MCP_MODE="$2"; shift 2 ;;
    --supabase-project-ref) SUPABASE_PROJECT_REF="$2"; shift 2 ;;
    --install-mcp-tools) INSTALL_MCP_TOOLS="$2"; shift 2 ;;
    --js) IS_JS="$2"; shift 2 ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$1"
      else
        echo "Unknown option: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  TARGET="$(pwd)"
fi

if [[ ! -d "$TARGET" ]]; then
  echo "ERROR: Target directory '$TARGET' does not exist."
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

# --------------- locate this script's repo -----------------------------------

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -f "$STANDARDS_DIR/general/CLAUDE.md" ]]; then
  echo "ERROR: Cannot find general/CLAUDE.md relative to this script."
  echo "       Run this script from inside the ai-dev-standards repo."
  exit 1
fi

echo ""
echo -e "${BOLD}━━━ AI Dev Standards Setup ━━━${RESET}"
echo ""
info "Standards source : $STANDARDS_DIR"
info "Target repo      : $TARGET"
echo ""

# --------------- project type & AI tooling -----------------------------------

if [[ -z "$PROJECT_TYPE" ]]; then
  PROJECT_TYPE="$(pick "What type of project is this?" "general" \
    "general  (no platform-specific rules)" \
    "web      (pnpm workspaces / Tailwind)" \
    "mobile   (React Native / Expo)")"
  PROJECT_TYPE="${PROJECT_TYPE%% *}"
fi

if [[ -z "$AI_TOOLS" ]]; then
  AI_TOOLS="$(pick "Which AI tool(s) do you want to configure?" "claude" \
    "claude   (Claude Code — copies CLAUDE.md + .claude/agents/)" \
    "copilot  (GitHub Copilot — copies .github/copilot-instructions.md + agents)" \
    "both     (install both)")"
  AI_TOOLS="${AI_TOOLS%% *}"
fi

# Default to detecting it rather than guessing: a package.json is the whole test.
if [[ -z "$IS_JS" ]]; then
  js_default="n"; [[ -f "$TARGET/package.json" ]] && js_default="y"
  ask IS_JS "$js_default" "Is this a Node/pnpm (JS or TypeScript) project? (y/n):"
fi

# --------------- copy / append functions -------------------------------------

copy_or_append_file() {
  local src="$1" dst="$2"
  local dst_dir; dst_dir="$(dirname "$dst")"
  mkdir -p "$dst_dir"
  if [[ -f "$dst" ]]; then
    warn "File already exists: ${dst#"$TARGET/"}"
    info "Appending standard rules to existing file..."
    echo -e "\n\n<!-- APPENDED BY AI DEV STANDARDS -->\n" >> "$dst"
    cat "$src" >> "$dst"
    success "Appended → ${dst#"$TARGET/"}"
  else
    cp "$src" "$dst"
    success "Copied → ${dst#"$TARGET/"}"
  fi
}

copy_dir() {
  local src_dir="$1" dst_dir="$2"
  mkdir -p "$dst_dir"
  for f in "$src_dir"/*.md; do
    [[ -e "$f" ]] || continue
    local fname; fname="$(basename "$f")"
    copy_or_append_file "$f" "$dst_dir/$fname"
  done
}

# --------------- OS and MCP tool dependency install ---------------------------

# CodeGraphContext is a **Python** package: PyPI `codegraphcontext`, CLI `cgc`.
# It has never been published to npm — the old `npm i -g @codegraphcontext/cli`
# here 404'd and, under `set -e`, killed the whole setup run before any file
# was written.
install_cgc() {
  if command -v cgc &> /dev/null; then
    info "cgc is already on PATH — skipping install."
  elif command -v pipx &> /dev/null; then
    info "Installing codegraphcontext via pipx..."
    if ! pipx install codegraphcontext; then
      warn "pipx install failed — skipping CGC setup. Install it by hand with:"
      warn "  pipx install codegraphcontext"
      return
    fi
  elif command -v pip3 &> /dev/null || command -v pip &> /dev/null; then
    local pip_cmd; pip_cmd="$(command -v pip3 || command -v pip)"
    info "pipx not found — installing codegraphcontext with $pip_cmd --user..."
    if ! "$pip_cmd" install --user codegraphcontext; then
      warn "pip install failed — skipping CGC setup."
      return
    fi
  else
    warn "CodeGraphContext needs Python (pipx or pip) and neither was found."
    warn "Install it later with: pipx install codegraphcontext"
    return
  fi

  if ! command -v cgc &> /dev/null; then
    warn "Installed, but 'cgc' is not on PATH yet — add ~/.local/bin to PATH,"
    warn "then run: cd '$TARGET' && cgc index && cgc mcp setup"
    return
  fi

  # Indexing needs a running Neo4j (see 'cgc neo4j setup'). Neither step is
  # allowed to abort the setup run: the config files matter more than the index,
  # and both are safe to re-run later.
  info "Indexing target repository ($TARGET)..."
  (cd "$TARGET" && cgc index) \
    || warn "cgc index failed (is Neo4j running? try 'cgc neo4j setup') — continuing."

  info "Setting up MCP server..."
  cgc mcp setup || warn "cgc mcp setup failed — run it by hand later. Continuing."

  success "CGC installed and configured."
}

install_mcp_tool_deps() {
  echo ""
  info "─── Token Optimization Setup ───"

  # Basic OS detection
  OS="$(uname -s)"
  info "Detected OS: $OS"

  if [[ -z "$INSTALL_CGC" ]]; then
    ask INSTALL_CGC "n" "Do you want to install Code Graph Context (CGC) for extreme token optimization? (y/n):"
  fi

  if [[ "$INSTALL_CGC" =~ ^[Yy] ]]; then
    install_cgc
  else
    info "Skipping CGC installation."
  fi

  # The tree-sitter MCP server also needs a CLI dependency (pipx); the other
  # npx-based servers (playwright, git, memory, sequential-thinking) are
  # fetched lazily by Claude Code on first connection and need nothing here.
  if [[ "$MCP_MODE" == "none" ]]; then
    return
  fi

  if [[ -z "$INSTALL_MCP_TOOLS" ]]; then
    ask INSTALL_MCP_TOOLS "n" "Install the tree-sitter MCP server's CLI dependency via pipx now? (y/n):"
  fi

  if [[ "$INSTALL_MCP_TOOLS" =~ ^[Yy] ]]; then
    if ! command -v pipx &> /dev/null; then
      warn "pipx is not installed — skipping tree-sitter MCP server setup."
      warn "Install pipx, then run: pipx install mcp-server-tree-sitter"
    else
      info "Installing mcp-server-tree-sitter via pipx..."
      pipx install mcp-server-tree-sitter || warn "pipx install failed — the server will still work via 'pipx run' on first use."
      success "tree-sitter MCP dependency installed."
    fi
  else
    info "Skipping MCP tool dependency install (npx-based servers still work on first use)."
  fi
}

# --------------- install Claude Code files -----------------------------------

install_claude() {
  echo ""
  info "─── Installing Claude Code files ───"

  copy_or_append_file "$STANDARDS_DIR/general/CLAUDE.md" "$TARGET/CLAUDE.md"
  copy_dir  "$STANDARDS_DIR/general/agents"    "$TARGET/.claude/agents"

  if [[ "$PROJECT_TYPE" == "mobile" ]]; then
    copy_or_append_file "$STANDARDS_DIR/mobile/RULES.md" "$TARGET/docs/mobile-rules.md"
    copy_or_append_file "$STANDARDS_DIR/mobile/agents/device-qa.md" \
              "$TARGET/.claude/agents/device-qa.md"
    info "Remember to add 'See docs/mobile-rules.md' to CLAUDE.md"
  fi

  if [[ "$PROJECT_TYPE" == "web" ]]; then
    copy_or_append_file "$STANDARDS_DIR/web/RULES.md" "$TARGET/docs/web-rules.md"
    info "Remember to add 'See docs/web-rules.md' to CLAUDE.md"
  fi
}

# --------------- install .claude/settings.json + hooks (JS/pnpm only) --------

install_javascript() {
  echo ""
  info "─── Installing javascript/ (pnpm/Prettier tooling) ───"

  mkdir -p "$TARGET/.claude/hooks"
  cp "$STANDARDS_DIR/javascript/claude-settings/hooks/format-edited.sh" \
     "$TARGET/.claude/hooks/format-edited.sh"
  chmod +x "$TARGET/.claude/hooks/format-edited.sh"
  success "Copied → .claude/hooks/format-edited.sh"

  local src="$STANDARDS_DIR/javascript/claude-settings/settings.json"
  local dst="$TARGET/.claude/settings.json"

  if [[ ! -f "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    success "Copied → .claude/settings.json"
    return
  fi

  if ! command -v jq &> /dev/null; then
    warn ".claude/settings.json already exists and jq is not installed — skipping merge."
    warn "Merge $src into $dst by hand (permissions.allow/deny, hooks.PostToolUse)."
    return
  fi

  jq -s '
    .[0] as $existing | .[1] as $new |
    $existing
    | .permissions.allow = (($existing.permissions.allow // []) + ($new.permissions.allow // []) | unique)
    | .permissions.deny  = (($existing.permissions.deny  // []) + ($new.permissions.deny  // []) | unique)
    | .hooks.PostToolUse  = (($existing.hooks.PostToolUse // []) as $existingHooks
        | ($new.hooks.PostToolUse // []) as $newHooks
        | $existingHooks + [ $newHooks[] | select(. as $h | $existingHooks | index($h) == null) ])
  ' "$dst" "$src" > "$dst.tmp" && mv "$dst.tmp" "$dst"
  success "Merged → .claude/settings.json"
}

append_js_claudeignore() {
  local ignore_file="$TARGET/.claudeignore"
  # `x || return` and `x && return` both propagate a non-zero status out of the
  # function, which `set -e` turns into an aborted run. Spell the guards out.
  if [[ ! -f "$ignore_file" ]]; then
    return 0
  fi
  if grep -q '^node_modules/$' "$ignore_file"; then
    info "JS/TS entries already present in .claudeignore — nothing to append."
    return 0
  fi
  cat >> "$ignore_file" << 'EOF'

# generated / vendored (JS/TS)
node_modules/
.pnp/
.next/
.expo/
.turbo/
*.tsbuildinfo

# lockfiles (agent must not read, not edit)
package-lock.json
yarn.lock
pnpm-lock.yaml
bun.lockb
EOF
  success "Appended JS/TS entries → .claudeignore"
}

# --------------- install .mcp.json --------------------------------------------

render_template() {
  local src="$1" dst="$2"
  sed -e "s#{{MEMORY_FILE_PATH}}#${MEMORY_FILE_PATH//\//\\/}#g" \
      -e "s#{{SUPABASE_PROJECT_REF}}#${SUPABASE_PROJECT_REF}#g" \
      "$src" > "$dst"
}

install_mcp() {
  echo ""
  info "─── Installing .mcp.json ───"

  if [[ -z "$MCP_MODE" ]]; then
    ask MCP_MODE "all" "Add the standard MCP server set to .mcp.json? (all/none):"
  fi

  if [[ "$MCP_MODE" == "none" ]]; then
    info "Skipping MCP server setup."
    return
  fi

  local project_name; project_name="$(basename "$TARGET")"
  MEMORY_FILE_PATH="$HOME/.claude/mcp-memory/${project_name}.json"
  mkdir -p "$(dirname "$MEMORY_FILE_PATH")"

  local tmp_dir; tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  local include_supabase="n"
  if [[ -n "$SUPABASE_PROJECT_REF" ]]; then
    include_supabase="y"
  else
    # Non-interactively this answers "n": --supabase-project-ref is the only
    # way to opt in without a TTY, and it was already checked above.
    ask include_supabase "n" "Does this project use Supabase? Add the Supabase MCP server? (y/n):"
    if [[ "$include_supabase" =~ ^[Yy] ]]; then
      ask SUPABASE_PROJECT_REF "" "Supabase project ref:"
    fi
  fi

  render_template "$STANDARDS_DIR/general/mcp/mcp.json" "$tmp_dir/mcp.json"

  local server_names=(codegraphcontext playwright git tree-sitter memory sequential-thinking)

  if [[ "$include_supabase" =~ ^[Yy] && -n "$SUPABASE_PROJECT_REF" ]]; then
    render_template "$STANDARDS_DIR/general/mcp/mcp.supabase.json" "$tmp_dir/mcp.supabase.json"
    server_names+=(supabase)
  fi

  local dst="$TARGET/.mcp.json"

  if [[ ! -f "$dst" ]]; then
    if [[ -f "$tmp_dir/mcp.supabase.json" ]] && command -v jq &> /dev/null; then
      jq -s '.[0] * .[1]' "$tmp_dir/mcp.json" "$tmp_dir/mcp.supabase.json" > "$dst"
    else
      cp "$tmp_dir/mcp.json" "$dst"
    fi
    success "Created → .mcp.json"
  elif command -v jq &> /dev/null; then
    local merge_src="$tmp_dir/mcp.json"
    if [[ -f "$tmp_dir/mcp.supabase.json" ]]; then
      jq -s '.[0] * .[1]' "$tmp_dir/mcp.json" "$tmp_dir/mcp.supabase.json" > "$tmp_dir/mcp.merged.json"
      merge_src="$tmp_dir/mcp.merged.json"
    fi
    # New servers only fill in missing keys — an existing server config always wins.
    jq -s '.[1].mcpServers as $new | .[0] | .mcpServers = ($new + .mcpServers)' \
      "$dst" "$merge_src" > "$dst.tmp" && mv "$dst.tmp" "$dst"
    success "Merged → .mcp.json (existing server entries were kept as-is)"
  else
    warn ".mcp.json already exists and jq is not installed — skipping merge."
    warn "Merge $tmp_dir/mcp.json into $dst by hand."
    return
  fi

  local settings_local="$TARGET/.claude/settings.local.json"
  mkdir -p "$(dirname "$settings_local")"
  if command -v jq &> /dev/null; then
    local names_json; names_json="$(printf '%s\n' "${server_names[@]}" | jq -R . | jq -s .)"
    if [[ -f "$settings_local" ]]; then
      jq --argjson new "$names_json" \
        '.enabledMcpjsonServers = ((.enabledMcpjsonServers // []) + $new | unique)' \
        "$settings_local" > "$settings_local.tmp" && mv "$settings_local.tmp" "$settings_local"
    else
      jq -n --argjson new "$names_json" '{enabledMcpjsonServers: $new}' > "$settings_local"
    fi
    success "Updated → .claude/settings.local.json (enabledMcpjsonServers)"
  else
    warn "jq is not installed — add these servers to .claude/settings.local.json's enabledMcpjsonServers by hand:"
    printf '    %s\n' "${server_names[@]}"
  fi
}

# --------------- install GitHub Copilot files --------------------------------

install_copilot() {
  echo ""
  info "─── Installing GitHub Copilot files ───"

  copy_or_append_file "$STANDARDS_DIR/copilot/copilot-instructions.md" \
            "$TARGET/.github/copilot-instructions.md"

  copy_dir  "$STANDARDS_DIR/copilot/agents" \
            "$TARGET/.github/agents"

  if [[ "$PROJECT_TYPE" == "mobile" ]]; then
    copy_or_append_file "$STANDARDS_DIR/copilot/instructions/mobile.instructions.md" \
              "$TARGET/.github/instructions/mobile.instructions.md"
    info "Add '# files: **/*.{ts,tsx}' applyTo glob to mobile.instructions.md if needed"
  fi

  if [[ "$PROJECT_TYPE" == "web" ]]; then
    copy_or_append_file "$STANDARDS_DIR/copilot/instructions/web.instructions.md" \
              "$TARGET/.github/instructions/web.instructions.md"
  fi
}

# --------------- generate .claudeignore ---------------------------------------

# Claude Code reads .claudeignore, Copilot does not — this used to live at the
# end of install_copilot, so `-a claude` (the common case) silently never got
# one. It belongs to every install path.
generate_claudeignore() {
  echo ""
  info "─── Generating .claudeignore ───"
  local ignore_file="$TARGET/.claudeignore"
  if [[ ! -f "$ignore_file" ]]; then
    cat > "$ignore_file" << 'EOF'
# generated / vendored build output
dist/
build/
out/
coverage/

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

install_mcp_tool_deps

case "$AI_TOOLS" in
  claude)  install_claude; [[ "$IS_JS" =~ ^[Yy] ]] && install_javascript; install_mcp ;;
  copilot) install_copilot ;;
  both)    install_claude; [[ "$IS_JS" =~ ^[Yy] ]] && install_javascript; install_mcp; install_copilot ;;
esac

generate_claudeignore
[[ "$IS_JS" =~ ^[Yy] ]] && append_js_claudeignore || true

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
