#!/usr/bin/env bash
# =============================================================================
# jenkins_install_plugins.sh — Install Vandelay Jenkins plugins from manifest
#
# Reads jenkins_plugins.txt and installs every listed plugin via the
# Jenkins Plugin CLI (jenkins-plugin-cli), which ships with Jenkins LTS 2.361+.
#
# Usage:
#   # Run on the Jenkins EC2 (via SSM or SSH):
#   sudo bash jenkins_install_plugins.sh
#
#   # Dry run — print what would be installed without touching Jenkins:
#   DRY_RUN=true bash jenkins_install_plugins.sh
#
#   # Point at a different manifest:
#   PLUGINS_FILE=/path/to/plugins.txt bash jenkins_install_plugins.sh
#
# What it does:
#   1. Resolves jenkins-plugin-cli path (bundled at /usr/bin or /usr/local/bin)
#   2. Reads PLUGINS_FILE, strips comments and blank lines
#   3. Calls jenkins-plugin-cli --plugins <list> to install/upgrade all plugins
#   4. Restarts Jenkins so new plugins are active
#
# Prerequisites:
#   - Jenkins LTS installed (jenkins_user_data.sh handles this)
#   - Run as root or a user with sudo
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_FILE="${PLUGINS_FILE:-$SCRIPT_DIR/jenkins_plugins.txt}"
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"
DRY_RUN="${DRY_RUN:-false}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  OK${NC}  $*"; }
err()  { echo -e "${RED} ERR${NC}  $*" >&2; }
warn() { echo -e "${YELLOW}WARN${NC}  $*"; }
info() { echo "INFO  $*"; }

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Vandelay Jenkins Plugin Installer"
echo "=============================================="
echo ""

if [[ ! -f "$PLUGINS_FILE" ]]; then
  err "Plugin manifest not found: $PLUGINS_FILE"
  exit 1
fi

# Locate jenkins-plugin-cli (bundled inside the Jenkins war on AL2023)
PLUGIN_CLI=""
for candidate in \
  /usr/bin/jenkins-plugin-cli \
  /usr/local/bin/jenkins-plugin-cli \
  "$(find /usr/lib/jenkins -name 'jenkins-plugin-cli' 2>/dev/null | head -1)"; do
  if [[ -x "$candidate" ]]; then
    PLUGIN_CLI="$candidate"
    break
  fi
done

# Fall back: extract from jenkins.war if CLI not on PATH
if [[ -z "$PLUGIN_CLI" ]]; then
  JENKINS_WAR="$(find /usr/lib/jenkins /usr/share/jenkins -name 'jenkins.war' 2>/dev/null | head -1 || true)"
  if [[ -n "$JENKINS_WAR" ]]; then
    warn "jenkins-plugin-cli not on PATH — using embedded jar via java -jar"
    PLUGIN_CLI="java -jar $JENKINS_WAR"
  else
    err "Cannot find jenkins-plugin-cli or jenkins.war. Is Jenkins installed?"
    exit 1
  fi
fi

ok "Plugin CLI : $PLUGIN_CLI"
ok "Manifest   : $PLUGINS_FILE"
ok "Jenkins home: $JENKINS_HOME"

# ---------------------------------------------------------------------------
# 2. Parse manifest — strip comments and blank lines
# ---------------------------------------------------------------------------
mapfile -t PLUGINS < <(grep -v '^\s*#' "$PLUGINS_FILE" | grep -v '^\s*$' | awk '{print $1}')

if [[ ${#PLUGINS[@]} -eq 0 ]]; then
  warn "No plugins found in $PLUGINS_FILE — nothing to install."
  exit 0
fi

echo ""
info "Plugins to install/verify (${#PLUGINS[@]} total):"
for p in "${PLUGINS[@]}"; do
  echo "    $p"
done
echo ""

# ---------------------------------------------------------------------------
# 3. Install
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
  warn "DRY_RUN=true — skipping actual install."
  exit 0
fi

info "Running jenkins-plugin-cli..."
$PLUGIN_CLI \
  --jenkins-home "$JENKINS_HOME" \
  --plugins "${PLUGINS[@]}" \
  --verbose

ok "Plugin installation complete."

# ---------------------------------------------------------------------------
# 4. Restart Jenkins to activate new plugins
# ---------------------------------------------------------------------------
info "Restarting Jenkins to activate plugins..."
if systemctl is-active --quiet jenkins; then
  systemctl restart jenkins
  ok "Jenkins restarted."

  # Wait for Jenkins to come back
  echo ""
  info "Waiting for Jenkins to be ready (up to 2 min)..."
  for i in $(seq 1 24); do
    if curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 5 \
        "http://localhost:8080/" 2>/dev/null | grep -qE "^[23]|403"; then
      ok "Jenkins is back online."
      break
    fi
    echo "  ... attempt $i/24"
    sleep 5
  done
else
  warn "Jenkins service not active — skipping restart. Start it with: systemctl start jenkins"
fi

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
ok "Done. ${#PLUGINS[@]} plugins installed from $PLUGINS_FILE"
echo ""
echo "  Next steps:"
echo "  1. Open Jenkins UI: http://<jenkins-ip>:8080"
echo "  2. Add credential 'vandelay-db-password' (Secret Text)"
echo "     Manage Jenkins → Credentials → System → Global → Add Credential"
echo "  3. Create a Pipeline job pointing at this repo's Jenkinsfile"
echo "  4. Run the pipeline with AUTO_APPROVE=false for your first deploy"
echo "=============================================="
echo ""
