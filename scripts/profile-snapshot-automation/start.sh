#!/bin/bash
# start.sh - Custom startup script for MT5 container
# Replaces the default /Metatrader/start.sh in the base image
# This script runs inside the X11 environment managed by openbox
#
# It handles:
# 1. Copying the base terminal template to the active Wine path
# 2. Injecting credentials from mounted volume
# 3. Launching MT5 in portable mode

set -e

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
BASE_TERMINAL_PATH="/opt/mt5-base-terminal"
CREDENTIALS_PATH="/config/credentials"
MT5_INSTALL_PATH="/config/.wine/drive_c/Program Files/MetaTrader 5"
MT5_EXE="$MT5_INSTALL_PATH/terminal64.exe"

# Wine prefix from environment (set via docker -e WINEPREFIX)
WINEPREFIX="${WINEPREFIX:-/config/.wine}"

# MT5_USER and MT5_WINE_USER_ROOT will be set after discovering actual runtime user

# Get MT5 user UID/GID from current process
# This ensures we always use the actual runtime user, not hardcoded values
get_mt5_user_ids() {
    MT5_UID=$(id -u)
    MT5_GID=$(id -g)
    MT5_USER=$(whoami)
    
    # Set Wine user root based on actual username
    # WINEPREFIX is already set at top level: "${WINEPREFIX:-/config/.wine}"
    MT5_WINE_USER_ROOT="$WINEPREFIX/drive_c/users/$MT5_USER"
}

# Discover TERMINAL_ID from base template
discover_terminal_id() {
    local base_terminal="$1"

    # Check metadata first
    if [ -f "$base_terminal/.metadata" ]; then
        local metadata_id
        metadata_id=$(grep "^TERMINAL_ID=" "$base_terminal/.metadata" 2>/dev/null | cut -d= -f2)
        if [ -n "$metadata_id" ]; then
            echo "$metadata_id"
            return 0
        fi
    fi

    # Find from Terminal directory
    if [ -d "$base_terminal/Terminal" ]; then
        local terminal_ids
        terminal_ids=$(find "$base_terminal/Terminal" -maxdepth 1 -type d -name '[A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9]' 2>/dev/null)

        if [ -n "$terminal_ids" ]; then
            basename "$terminal_ids"
            return 0
        fi
    fi

    return 1
}

# Check if terminal directory is already initialized
is_terminal_initialized() {
    local terminal_path="$1"

    if [ -d "$terminal_path" ] && [ -f "$terminal_path/terminal.ini" ]; then
        # Check for profile data (the critical test)
        if [ -d "$terminal_path/profiles" ] || [ -d "$terminal_path/MQL5" ]; then
            return 0  # Already initialized
        fi
    fi

    return 1  # Not initialized
}

# Initialize and copy base template if needed
# IMPORTANT: Always copy fresh from base template to ensure credentials are not stale
# The .wine prefix may contain old credentials from reference container
init_terminal_directory() {
    local terminal_id="$1"
    local terminal_root="$MT5_WINE_USER_ROOT/AppData/Roaming/MetaQuotes/Terminal"
    local active_terminal_path="$terminal_root/$terminal_id"

    log_info "Initializing terminal directory for TERMINAL_ID=$terminal_id"

    mkdir -p "$terminal_root"

    # Check if base template exists
    if [ ! -d "$BASE_TERMINAL_PATH" ]; then
        if [ -d "$active_terminal_path" ]; then
            log_warning "Base terminal template not found at $BASE_TERMINAL_PATH, but active terminal path already exists. Skipping template copy."
            return 0
        else
            log_error "Base terminal template not found at $BASE_TERMINAL_PATH and active terminal path does not exist."
            return 1
        fi
    fi

    # Always delete and recreate to ensure fresh state if template is present
    # This prevents stale credentials from being reused
    if [ -d "$active_terminal_path" ]; then
        log_info "Removing existing terminal directory for fresh init..."
        rm -rf "$active_terminal_path"
    fi

    if [ ! -d "$BASE_TERMINAL_PATH/Terminal" ]; then
        log_error "Base template Terminal directory not found"
        return 1
    fi

    log_info "Copying base template to $active_terminal_path"
    mkdir -p "$active_terminal_path"
    cp -a "$BASE_TERMINAL_PATH/Terminal/." "$active_terminal_path/"

    if [ -d "$BASE_TERMINAL_PATH/MQL5" ]; then
        log_info "Copying MQL5 files to active terminal path $active_terminal_path/MQL5"
        mkdir -p "$active_terminal_path/MQL5"
        cp -a "$BASE_TERMINAL_PATH/MQL5/." "$active_terminal_path/MQL5/" 2>/dev/null || true
        
        log_info "Copying MQL5 files to install path $MT5_INSTALL_PATH/MQL5"
        mkdir -p "$MT5_INSTALL_PATH/MQL5"
        cp -a "$BASE_TERMINAL_PATH/MQL5/." "$MT5_INSTALL_PATH/MQL5/" 2>/dev/null || true
        
        # Log MQL5/Profiles status
        if [ -d "$active_terminal_path/MQL5/Profiles/Charts" ]; then
            local profiles=$(ls -d "$active_terminal_path/MQL5/Profiles/Charts"/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ', ' | sed 's/,$//')
            log_success "MQL5/Profiles copied. Available profiles: $profiles"
        fi
    fi

    if [ -d "$BASE_TERMINAL_PATH/profiles" ]; then
        log_info "Copying profiles to $active_terminal_path/profiles"
        mkdir -p "$active_terminal_path/profiles"
        cp -a "$BASE_TERMINAL_PATH/profiles/." "$active_terminal_path/profiles/" 2>/dev/null || true
    fi

    if [ -d "$BASE_TERMINAL_PATH/Config" ]; then
        log_info "Copying Config files to active terminal path $active_terminal_path/Config"
        mkdir -p "$active_terminal_path/Config"
        cp -a "$BASE_TERMINAL_PATH/Config/." "$active_terminal_path/Config/" 2>/dev/null || true
        
        log_info "Copying Config files to install path $MT5_INSTALL_PATH/Config"
        mkdir -p "$MT5_INSTALL_PATH/Config"
        cp -a "$BASE_TERMINAL_PATH/Config/." "$MT5_INSTALL_PATH/Config/" 2>/dev/null || true
    fi

    if [ -d "$BASE_TERMINAL_PATH/Profiles" ]; then
        log_info "Copying Profiles (Templates) to active terminal path $active_terminal_path/Profiles"
        mkdir -p "$active_terminal_path/Profiles"
        cp -a "$BASE_TERMINAL_PATH/Profiles/." "$active_terminal_path/Profiles/" 2>/dev/null || true
        
        log_info "Copying Profiles (Templates) to install path $MT5_INSTALL_PATH/Profiles"
        mkdir -p "$MT5_INSTALL_PATH/Profiles"
        cp -a "$BASE_TERMINAL_PATH/Profiles/." "$MT5_INSTALL_PATH/Profiles/" 2>/dev/null || true
    fi

    log_success "Base template copied successfully"
}

# Inject credentials from mounted volume
inject_credentials() {
    local terminal_id="$1"
    local active_terminal_path="$MT5_WINE_USER_ROOT/AppData/Roaming/MetaQuotes/Terminal/$terminal_id"

    # Check if credentials volume is mounted
    if [ ! -f "$CREDENTIALS_PATH/terminal.ini" ]; then
        log_warning "No credentials found at $CREDENTIALS_PATH/terminal.ini"
        return 0
    fi

    log_info "Injecting credentials from volume"

    # CRITICAL: Clear Wine Registry cache to prevent MT5 from using stale credentials
    # Wine stores login info in registry - must wipe it for each container to login correctly
    # Registry location is determined by WINEPREFIX env var
    clear_wine_registry() {
        log_info "Clearing Wine Registry cache for MT5..."
        log_info "Wine Prefix: $WINEPREFIX"

        local userreg="$WINEPREFIX/user.reg"
        local systemreg="$WINEPREFIX/system.reg"

        if [ -f "$userreg" ]; then
            log_info "Clearing MetaQuotes entries from $userreg"
            # Wine registry format: [Software\\MetaQuotes\\Terminal\\...]
            # Each \\\\ in sed matches one literal \ in the file
            # File has \\ (2 backslashes), so we need \\\\ to match it
            
            # Remove Software\\MetaQuotes\\Terminal sections
            # Pattern: [Software\\MetaQuotes\\Terminal matches file [Software\\\\MetaQuotes\\\\Terminal
            sed -i '/\[Software\\\\MetaQuotes\\\\Terminal/d' "$userreg" 2>/dev/null || true
            
            # Remove Software\\MetaQuotes Software sections
            sed -i '/\[Software\\\\MetaQuotes Software/d' "$userreg" 2>/dev/null || true
            
            # Remove standalone MetaQuotes entries
            sed -i '/^"MetaQuotes"/d' "$userreg" 2>/dev/null || true
            
            log_info "Wine user registry cleared"
        fi

        if [ -f "$systemreg" ]; then
            log_info "Clearing MetaQuotes entries from $systemreg"
            sed -i '/\[Software\\\\MetaQuotes\\\\Terminal/d' "$systemreg" 2>/dev/null || true
            sed -i '/\[Software\\\\MetaQuotes Software/d' "$systemreg" 2>/dev/null || true
            log_info "Wine system registry cleared"
        fi

        log_success "Wine Registry cache cleared"
    }
    clear_wine_registry

    # Inject terminal.ini
    log_info "Injecting terminal.ini"
    cp "$CREDENTIALS_PATH/terminal.ini" "$active_terminal_path/terminal.ini"

    # Inject hdd.v2/accounts.ini
    if [ -f "$CREDENTIALS_PATH/hdd.v2/accounts.ini" ]; then
        log_info "Injecting accounts.ini"
        mkdir -p "$active_terminal_path/hdd.v2"
        cp "$CREDENTIALS_PATH/hdd.v2/accounts.ini" "$active_terminal_path/hdd.v2/accounts.ini"
    fi

    # Inject hdd.v2/connections.ini
    if [ -f "$CREDENTIALS_PATH/hdd.v2/connections.ini" ]; then
        log_info "Injecting connections.ini"
        mkdir -p "$active_terminal_path/hdd.v2"
        cp "$CREDENTIALS_PATH/hdd.v2/connections.ini" "$active_terminal_path/hdd.v2/connections.ini"
    fi


    # Inject into nested terminal directory if exists (MT5 portable mode creates nested dir)
    local nested_path="$active_terminal_path/$terminal_id"
    if [ -d "$nested_path" ]; then
        log_info "Injecting credentials into nested terminal directory"
        cp "$CREDENTIALS_PATH/terminal.ini" "$nested_path/terminal.ini"
        if [ -f "$CREDENTIALS_PATH/hdd.v2/accounts.ini" ]; then
            mkdir -p "$nested_path/hdd.v2"
            cp "$CREDENTIALS_PATH/hdd.v2/accounts.ini" "$nested_path/hdd.v2/accounts.ini"
            cp "$CREDENTIALS_PATH/hdd.v2/connections.ini" "$nested_path/hdd.v2/connections.ini" 2>/dev/null || true
        fi
    fi
    log_success "Credentials injected from volume"
}

# Apply proper permissions for MT5 user
fix_permissions() {
    local terminal_id="$1"
    local active_terminal_path="$MT5_WINE_USER_ROOT/AppData/Roaming/MetaQuotes/Terminal/$terminal_id"

    log_info "Fixing permissions for MT5 user ($MT5_UID:$MT5_GID)"

    # Fix terminal directory (including files just copied from base template)
    chown -R "$MT5_UID:$MT5_GID" "$active_terminal_path" 2>/dev/null || true
    find "$active_terminal_path" -type d -exec chmod 755 {} \; 2>/dev/null || true
    find "$active_terminal_path" -type f -exec chmod 644 {} \; 2>/dev/null || true

    # Fix MQL5/Config/Profiles dirs (also copied by init_terminal_directory)
    chown -R "$MT5_UID:$MT5_GID" "$MT5_INSTALL_PATH/MQL5" 2>/dev/null || true
    chown -R "$MT5_UID:$MT5_GID" "$MT5_INSTALL_PATH/Config" 2>/dev/null || true
    chown -R "$MT5_UID:$MT5_GID" "$MT5_INSTALL_PATH/Profiles" 2>/dev/null || true

    # Fix entire /config/.wine to ensure Wine prefix is writable
    # (critical when .wine is copied from reference container on host or restored from backup)
    chown -R "$MT5_UID:$MT5_GID" "$WINEPREFIX" 2>/dev/null || true

    log_success "Permissions fixed"
}

# Disable MT5 LiveUpdate by making WebInstall folder read-only
disable_live_update() {
    local webinstall_dir="$MT5_WINE_USER_ROOT/AppData/Roaming/MetaQuotes/WebInstall"
    log_info "Disabling MT5 LiveUpdate at $webinstall_dir..."
    rm -rf "$webinstall_dir" 2>/dev/null || true
    mkdir -p "$webinstall_dir"
    # Make it read-only for the MT5 user to prevent downloading update packages
    chmod 555 "$webinstall_dir" 2>/dev/null || true
    log_success "MT5 LiveUpdate disabled"
}

# Restore Wine prefix from built-in backup if empty
restore_wine_prefix() {
    if [ ! -d "$WINEPREFIX" ] || [ ! -f "$MT5_EXE" ]; then
        log_info "Wine prefix empty or MT5 not found at $MT5_EXE"
        if [ -d "/opt/mt5-wine" ]; then
            log_info "Restoring Wine prefix from built-in backup /opt/mt5-wine..."
            mkdir -p "$WINEPREFIX"
            # Copy backup to WINEPREFIX
            cp -a /opt/mt5-wine/. "$WINEPREFIX/"
            log_success "Wine prefix restored successfully from /opt/mt5-wine"
        else
            log_warning "No built-in Wine prefix backup found at /opt/mt5-wine"
            return 1
        fi
    fi
    return 0
}

# Main entrypoint
main() {
    echo ""
    echo "=========================================="
    echo "  MT5 Container Startup"
    echo "  Custom start.sh"
    echo "=========================================="
    echo ""

    # Get MT5 user IDs first (this sets MT5_USER, MT5_UID, MT5_GID, MT5_WINE_USER_ROOT)
    get_mt5_user_ids

    # Step 0: Restore Wine prefix if missing
    if ! restore_wine_prefix; then
        log_error "Failed to restore Wine prefix"
        exit 1
    fi

    log_info "Current User: $MT5_USER (UID: $MT5_UID, GID: $MT5_GID)"
    log_info "Wine User Root: $MT5_WINE_USER_ROOT"
    log_info "Base Terminal: $BASE_TERMINAL_PATH"
    log_info "Credentials Path: $CREDENTIALS_PATH"
    echo ""

    # Discover or use provided TERMINAL_ID
    local terminal_id="${TERMINAL_ID:-}"
    if [ -z "$terminal_id" ]; then
        log_info "TERMINAL_ID not set, discovering from base template..."
        terminal_id=$(discover_terminal_id "$BASE_TERMINAL_PATH")
        if [ -z "$terminal_id" ]; then
            log_error "Failed to discover TERMINAL_ID"
            log_error "Please set TERMINAL_ID environment variable"
            exit 1
        fi
    fi

    log_info "Using TERMINAL_ID: $terminal_id"
    echo ""

    # Step 1: Initialize terminal directory with base template
    if ! init_terminal_directory "$terminal_id"; then
        log_error "Failed to initialize terminal directory"
        exit 1
    fi
    echo ""

    # Step 2: Fix permissions BEFORE injecting credentials
    # This ensures abc user can write to terminal.ini
    fix_permissions "$terminal_id"
    echo ""

    # Step 3: Inject credentials if volume is mounted
    inject_credentials "$terminal_id"
    echo ""

    # Step 3.5: Disable MT5 LiveUpdate
    disable_live_update
    echo ""


    # Step 3.6: Copy startup.ini if available to MT5 install directory
    # This ensures MT5 can find it relative to the executable
    if [ -f "$CREDENTIALS_PATH/startup.ini" ]; then
        log_info "Copying startup.ini from credentials volume to MT5 installation path..."
        cp "$CREDENTIALS_PATH/startup.ini" "$MT5_INSTALL_PATH/startup.ini"
        chown "$MT5_UID:$MT5_GID" "$MT5_INSTALL_PATH/startup.ini" 2>/dev/null || true
        chmod 644 "$MT5_INSTALL_PATH/startup.ini" 2>/dev/null || true
    elif [ -f "/config/startup.ini" ]; then
        log_info "Copying startup.ini from config directory to MT5 installation path..."
        cp "/config/startup.ini" "$MT5_INSTALL_PATH/startup.ini"
        chown "$MT5_UID:$MT5_GID" "$MT5_INSTALL_PATH/startup.ini" 2>/dev/null || true
        chmod 644 "$MT5_INSTALL_PATH/startup.ini" 2>/dev/null || true
    fi
    echo ""

    # Step 4: Launch MT5 with startup.ini for auto-login
    log_info "Starting MetaTrader 5..."
    log_info "Executable: $MT5_EXE"
    log_info "User: $MT5_USER ($MT5_UID:$MT5_GID)"
    echo ""

    cd "$MT5_INSTALL_PATH"

    # Use su-exec or gosu to switch to MT5 user (kasm-user or abc)
    if command -v su-exec >/dev/null 2>&1; then
        exec su-exec "$MT5_UID:$MT5_GID" wine terminal64.exe /config:startup.ini
    elif command -v gosu >/dev/null 2>&1; then
        exec gosu "$MT5_UID:$MT5_GID" wine terminal64.exe /config:startup.ini
    elif [ "$(id -u)" = "0" ] && id "$MT5_USER" >/dev/null 2>&1; then
        exec su -c "wine terminal64.exe /config:startup.ini" "$MT5_USER"
    else
        # Already running as correct user
        exec wine terminal64.exe /config:startup.ini
    fi
}

main "$@"
