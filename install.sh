#!/usr/bin/env bash
# =============================================================================
# dsh-enhance-tool — one-command installer for DeepSeek Harness (dsh) web
#
#   Standard install: adds the plugin via the official `dsh plugin` (pnpm) path,
#   then links the @deepseek-ai/dsh-session-title-llm dependency (which pnpm
#   cannot resolve on its own — it lives inside the global dsh package).
#
#   Usage:  bash install.sh            (uses ~/.dsh, auto-detects global dsh)
#           DSH_HOME=... bash install.sh
#
#   Requires: dsh (>= 0.1.0-rc.7) installed via npm -g
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR"

# ---- 1. Locate the dsh web profile -----------------------------------------
if [[ -n "${DSH_HOME:-}" ]]; then
  DSH_ROOT="$DSH_HOME"
else
  DSH_ROOT="${HOME}/.dsh"
fi
PROFILE="$DSH_ROOT/profiles/web"
NM="$PROFILE/node_modules"
if [[ ! -d "$PROFILE" ]]; then
  echo "error: dsh web profile not found at $PROFILE" >&2
  echo "  start 'dsh web' once to create it, or set DSH_HOME" >&2
  exit 1
fi

# ---- 2. Locate the global dsh package (for the session-title dep) ----------
GLOBAL_DSH="$(node -e 'try{process.stdout.write(require.resolve("@deepseek-ai/dsh/package.json",{paths:[require("os").homedir()+"/.nvm/versions/node"]}))}catch(e){process.stdout.write("")}' 2>/dev/null || true)"
if [[ -z "$GLOBAL_DSH" || ! -f "$GLOBAL_DSH" ]]; then
  # Fallback: search common global node_modules locations
  for base in \
    "$(npm root -g 2>/dev/null || true)" \
    "${NVM_DIR:-$HOME/.nvm}/versions/node/"*/lib/node_modules \
    /usr/local/lib/node_modules; do
    if [[ -f "$base/@deepseek-ai/dsh/package.json" ]]; then
      GLOBAL_DSH="$base/@deepseek-ai/dsh/package.json"
      break
    fi
  done
fi
if [[ -z "$GLOBAL_DSH" || ! -f "$GLOBAL_DSH" ]]; then
  echo "error: global @deepseek-ai/dsh package not found" >&2
  echo "  install it first:  npm install -g @deepseek-ai/dsh" >&2
  exit 1
fi
DSH_GLOBAL="$(dirname "$GLOBAL_DSH")"
# The session-title packages live inside the dsh package's own node_modules.
DSH_DEPS="$DSH_GLOBAL/node_modules/@deepseek-ai"

# ---- 3. Install the plugin (official pnpm path) ----------------------------
echo "[1/4] installing plugin via dsh plugin (pnpm)..."
if command -v dsh >/dev/null 2>&1; then
  dsh plugin --profile web add "$SCRIPT_DIR" 2>&1 || dsh plugin --profile web add "github:dcrzsy/dsh-enhance-tool" 2>&1
else
  # Fallback: manual copy (works without the dsh CLI)
  echo "  dsh CLI not found — copying plugin files directly"
  mkdir -p "$NM/dsh-enhance-tool"
  cp -f "$PLUGIN_DIR/package.json"      "$NM/dsh-enhance-tool/package.json"
  cp -f "$PLUGIN_DIR/cordis.patch.yml"  "$NM/dsh-enhance-tool/cordis.patch.yml"
  mkdir -p "$NM/dsh-enhance-tool/lib"
  cp -f "$PLUGIN_DIR/lib/index.js"         "$NM/dsh-enhance-tool/lib/index.js"
  cp -f "$PLUGIN_DIR/lib/client.js"        "$NM/dsh-enhance-tool/lib/client.js"
  cp -f "$PLUGIN_DIR/lib/polish-routes.js" "$NM/dsh-enhance-tool/lib/polish-routes.js"
fi

# ---- 4. Link the session-title dependency -----------------------------------
echo "[2/4] linking @deepseek-ai/dsh-session-title-llm..."
mkdir -p "$NM/@deepseek-ai"
for pkg in dsh-session-title dsh-session-title-llm; do
  if [[ -d "$DSH_DEPS/$pkg" ]]; then
    ln -sfn "$DSH_DEPS/$pkg" "$NM/@deepseek-ai/$pkg"
    echo "  linked $pkg"
  else
    echo "  warn: $pkg not found in global dsh — skipping" >&2
  fi
done

# ---- 5. Syntax check --------------------------------------------------------
echo "[3/4] verifying plugin files..."
for f in "$NM/dsh-enhance-tool/lib/index.js" "$NM/dsh-enhance-tool/lib/polish-routes.js" "$NM/dsh-enhance-tool/lib/client.js"; do
  node --check "$f"
done
echo "  all files parse OK"

# ---- 6. Done ---------------------------------------------------------------
echo "[4/4] done."
echo ""
echo "Next steps:"
echo "  1. restart dsh web:   fuser -k 3080/tcp; nohup dsh web &   (or the dsh restart command)"
echo "  2. hard-refresh the browser (Ctrl+Shift+R)"
echo ""
echo "Notes:"
echo "  - Plugin patches mount automatically via its own cordis.patch.yml (bundle.patch)."
echo "  - Uninstall: delete $NM/dsh-enhance-tool and restart dsh web."
