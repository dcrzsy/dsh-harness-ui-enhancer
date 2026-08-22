#!/usr/bin/env bash
# =============================================================================
# harness-ui-enhancer — one-command installer for DeepSeek Harness (dsh) web
#
#   Installs the plugin into the active dsh web profile, links the session-title
#   dependency from the global dsh package, and verifies every file parses.
#
#   Usage:  bash install.sh            (uses ~/.dsh, auto-detects global dsh)
#           DSH_HOME=... bash install.sh
#
#   Requires: dsh (>= 0.1.0-rc.7) installed via npm -g
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$SCRIPT_DIR/harness-ui-enhancer"

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

# ---- 3. Copy the plugin -----------------------------------------------------
echo "[1/4] installing plugin into $PROFILE/..."
mkdir -p "$NM/harness-ui-enhancer"
cp -f "$PLUGIN_DIR/package.json"   "$NM/harness-ui-enhancer/package.json"
cp -f "$PLUGIN_DIR/cordis.patch.yml" "$NM/harness-ui-enhancer/cordis.patch.yml"
mkdir -p "$NM/harness-ui-enhancer/lib"
cp -f "$PLUGIN_DIR/lib/index.js"        "$NM/harness-ui-enhancer/lib/index.js"
cp -f "$PLUGIN_DIR/lib/client.js"       "$NM/harness-ui-enhancer/lib/client.js"
cp -f "$PLUGIN_DIR/lib/polish-routes.js" "$NM/harness-ui-enhancer/lib/polish-routes.js"

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
for f in "$NM/harness-ui-enhancer/lib/index.js" "$NM/harness-ui-enhancer/lib/polish-routes.js" "$NM/harness-ui-enhancer/lib/client.js"; do
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
echo "  - Uninstall: delete $NM/harness-ui-enhancer and restart dsh web."
