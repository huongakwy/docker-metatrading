#!/bin/bash
# extract-profile-snapshot.sh - Extract profile snapshots from a reference MT5 container
# Usage: ./extract-profile-snapshot.sh <reference_container_id> [output_dir]
#
# This script extracts the full Terminal directory structure from a running MT5 container
# Because MT5 generates random Terminal_ID on each installation, we must copy the full
# Terminal directory to preserve all profile and configuration data.
#
# Exit Codes:
#   0 - Success
#   1 - Reference container not found
#   2 - Terminal_ID discovery failed
#   3 - Required files missing from container
#   4 - Copy operation failed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default output directory
OUTPUT_DIR="${2:-./snapshot}"

REFERENCE_IMAGE=""
REFERENCE_MOUNT_USER=""
REFERENCE_MOUNT_GROUP=""
REFERENCE_MT5_USER=""
REFERENCE_MT5_UID=""
REFERENCE_MT5_GID=""
REFERENCE_TERMINAL_ROOT=""
REFERENCE_TERMINAL_PARENT=""
REFERENCE_MT5_INSTALL_PATH="/config/.wine/drive_c/Program Files/MetaTrader 5"

# Show usage
usage() {
    cat << EOF
Usage: $0 <reference_container_id> [output_dir]

Extract profile snapshots, EA/DLL files, and full Terminal directory from a reference MT5 container.

Arguments:
  reference_container_id  Docker container ID or name (e.g., mt5_01, account_01)
  output_dir            Target directory for snapshot (default: ./snapshot)

Examples:
  $0 mt5_01                          # Extract to ./snapshot
  $0 account_01 ./my-snapshot         # Extract to ./my-snapshot

Note:
  MT5 generates a random Terminal_ID on each installation, so this script
  copies the FULL Terminal directory structure, not just individual files.

EOF
    exit 0
}

# Check arguments
if [ -z "$1" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
fi

REFERENCE_CONTAINER="$1"

# Validate container exists and is running
validate_container() {
    log_info "Validating reference container: $REFERENCE_CONTAINER"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${REFERENCE_CONTAINER}$"; then
        log_error "Container '$REFERENCE_CONTAINER' is not running"
        log_error "Available running containers:"
        docker ps --format '  - {{.Names}} ({{.Status}})'
        exit 1
    fi

    REFERENCE_IMAGE=$(docker inspect "$REFERENCE_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null || true)

    local user_group_info
    user_group_info=$(docker exec "$REFERENCE_CONTAINER" sh -lc '
        terminal_path=$(find /config/.wine/drive_c/users -path "*MetaQuotes/Terminal" -type d 2>/dev/null | head -1)
        terminal_parent=$(dirname "$terminal_path")
        mt5_user=$(basename "$(dirname "$(dirname "$(dirname "$terminal_parent")")")")
        mount_user=$(stat -c "%U" /config 2>/dev/null || echo "abc")
        mount_group=$(stat -c "%G" /config 2>/dev/null || echo "users")
        mount_uid=$(stat -c "%u" /config 2>/dev/null || echo "1000")
        mount_gid=$(stat -c "%g" /config 2>/dev/null || echo "1000")
        printf "%s|%s|%s|%s|%s|%s|%s\n" "$mount_user" "$mount_group" "$mount_uid" "$mount_gid" "$mt5_user" "$terminal_path" "/config/.wine/drive_c/Program Files/MetaTrader 5"
    ' 2>/dev/null || true)

    if [ -z "$user_group_info" ]; then
        REFERENCE_MOUNT_USER="abc"
        REFERENCE_MOUNT_GROUP="users"
        REFERENCE_MT5_UID="1000"
        REFERENCE_MT5_GID="1000"
        REFERENCE_MT5_USER="abc"
        REFERENCE_TERMINAL_ROOT="/config/.wine/drive_c/users/abc/AppData/Roaming/MetaQuotes/Terminal"
    else
        IFS='|' read -r REFERENCE_MOUNT_USER REFERENCE_MOUNT_GROUP REFERENCE_MT5_UID REFERENCE_MT5_GID REFERENCE_MT5_USER REFERENCE_TERMINAL_ROOT REFERENCE_MT5_INSTALL_PATH <<< "$user_group_info"
    fi

    if [ -z "$REFERENCE_IMAGE" ]; then
        REFERENCE_IMAGE="gmag11/metatrader5_vnc:1.0"
    fi

    if [ -z "$REFERENCE_MT5_USER" ]; then
        REFERENCE_MT5_USER="abc"
    fi

    if [ -z "$REFERENCE_TERMINAL_ROOT" ]; then
        REFERENCE_TERMINAL_ROOT="/config/.wine/drive_c/users/$REFERENCE_MT5_USER/AppData/Roaming/MetaQuotes/Terminal"
    fi

    REFERENCE_TERMINAL_PARENT=$(dirname "$REFERENCE_TERMINAL_ROOT")
    
    log_success "Container '$REFERENCE_CONTAINER' is running"
    log_info "Reference image: $REFERENCE_IMAGE"
    log_info "Reference MT5 user: $REFERENCE_MT5_USER (${REFERENCE_MT5_UID:-1000}:${REFERENCE_MT5_GID:-1000})"
    log_info "Reference mount ownership: ${REFERENCE_MOUNT_USER:-abc}:${REFERENCE_MOUNT_GROUP:-users}"
}

# Discover Terminal_ID from container
discover_terminal_id() {
    # Search for terminal.ini in Wine directory structure
    # Pattern: .../MetaQuotes/Terminal/{32-char-hex}/terminal.ini
    local terminal_ini_path
    terminal_ini_path=$(docker exec "$REFERENCE_CONTAINER" sh -lc '
        terminal_root="$1"
        find "$terminal_root" -name "terminal.ini" -path "*MetaQuotes/Terminal/*" 2>/dev/null | head -1
    ' sh "$REFERENCE_TERMINAL_ROOT" 2>/dev/null)
    
    if [ -z "$terminal_ini_path" ]; then
        log_error "No terminal.ini found in container"
        log_error "Container may not have MT5 properly installed"
        exit 2
    fi
    
    # Extract Terminal_ID from path
    local terminal_id
    terminal_id=$(echo "$terminal_ini_path" | grep -oE '[A-F0-9]{32}' | head -1)
    
    if [ -z "$terminal_id" ] || [ ${#terminal_id} -ne 32 ]; then
        log_error "Failed to extract valid Terminal_ID from path: $terminal_ini_path"
        exit 2
    fi
    
    echo "$terminal_id"
}

# Construct source paths
get_source_paths() {
    local terminal_id="$1"
    
    # Wine paths in container
    echo "/config/.wine"
}

# Copy full Terminal directory
copy_terminal_directory() {
    local terminal_id="$1"
    
    log_info "Copying FULL Terminal directory (required because Terminal_ID is random per install)..."
    
    mkdir -p "$OUTPUT_DIR/Terminal"
    
    local source_path="$REFERENCE_TERMINAL_ROOT"
    
    if docker exec "$REFERENCE_CONTAINER" tar -cf - -C "$source_path" "$terminal_id" 2>/dev/null | tar -xf - -C "$OUTPUT_DIR/Terminal/"; then
        log_success "Terminal directory copied"
    else
        log_error "Failed to copy Terminal directory"
        log_error "Trying alternate method..."
        
        docker cp "$REFERENCE_CONTAINER:${source_path}/${terminal_id}" "$OUTPUT_DIR/Terminal/" 2>/dev/null || {
            log_error "All copy methods failed"
            exit 4
        }
        log_success "Terminal directory copied (fallback method)"
    fi
}

# Copy EA and DLL files
copy_experts_and_libraries() {
    local source_base="/config/.wine/drive_c/Program Files/MetaTrader 5"
    
    log_info "Copying Experts and Libraries directories..."
    
    # Create destination directories
    mkdir -p "$OUTPUT_DIR/Experts"
    mkdir -p "$OUTPUT_DIR/Libraries"
    
    # Copy MQL5/Experts using tar (more reliable)
    local mql5_path="/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5"
    
    # Copy Experts
    if docker exec "$REFERENCE_CONTAINER" tar -cf - -C "$mql5_path" "Experts" 2>/dev/null | tar -xf - -C "$OUTPUT_DIR/"; then
        log_success "Experts directory copied"
    else
        log_warning "No Experts directory found (this is OK if no EAs are installed)"
    fi
    
    # Copy Libraries
    if docker exec "$REFERENCE_CONTAINER" tar -cf - -C "$mql5_path" "Libraries" 2>/dev/null | tar -xf - -C "$OUTPUT_DIR/"; then
        log_success "Libraries directory copied"
    else
        log_warning "No Libraries directory found (this is OK if no DLLs are used)"
    fi
}

# Copy MQL5 Profiles (Charts with .chr files - required for EA attachment)
copy_mql5_profiles() {
    local source_base="/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5"
    
    log_info "Copying MQL5 Profiles directory..."
    
    mkdir -p "$OUTPUT_DIR/MQL5/Profiles"
    
    # Copy entire MQL5/Profiles directory using tar
    if docker exec "$REFERENCE_CONTAINER" tar -cf - -C "$source_base" "Profiles" 2>/dev/null | tar -xf - -C "$OUTPUT_DIR/MQL5/"; then
        log_success "MQL5/Profiles directory copied (including Charts/AutoTrading)"
        
        # Count copied files
        local chr_count=$(find "$OUTPUT_DIR/MQL5/Profiles" -name "*.chr" 2>/dev/null | wc -l)
        log_info "Found $chr_count chart file(s) (.chr)"
        
        # List available profiles
        if [ -d "$OUTPUT_DIR/MQL5/Profiles/Charts" ]; then
            local profiles=$(ls -d "$OUTPUT_DIR/MQL5/Profiles/Charts"/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ', ' | sed 's/,$//')
            log_info "Available profiles: $profiles"
        fi
    else
        log_warning "No MQL5/Profiles directory found in source"
    fi
}

# Copy profile templates (legacy - for compatibility)
copy_profiles() {
    log_info "Copying Profiles templates..."
    
    # Also copy from the MQL5/Profiles we just copied
    if [ -d "$OUTPUT_DIR/MQL5/Profiles/Templates" ]; then
        mkdir -p "$OUTPUT_DIR/profiles/Templates"
        cp -a "$OUTPUT_DIR/MQL5/Profiles/Templates/." "$OUTPUT_DIR/profiles/Templates/" 2>/dev/null || true
    fi
    
    # Copy SymbolSets
    if [ -d "$OUTPUT_DIR/MQL5/Profiles/Symbolsets" ]; then
        mkdir -p "$OUTPUT_DIR/profiles/SymbolSets"
        cp -a "$OUTPUT_DIR/MQL5/Profiles/Symbolsets/." "$OUTPUT_DIR/profiles/SymbolSets/" 2>/dev/null || true
    fi
    
    log_success "Profiles templates copied"
}

# Copy Config directory
copy_config() {
    local source_base="/config/.wine/drive_c/Program Files/MetaTrader 5"
    
    log_info "Copying Config directory..."
    
    mkdir -p "$OUTPUT_DIR/Config"
    
    # Copy Config directory using tar
    if docker exec "$REFERENCE_CONTAINER" tar -cf - -C "$source_base" "Config" 2>/dev/null | tar -xf - -C "$OUTPUT_DIR/"; then
        log_success "Config directory copied"
    else
        log_warning "No Config directory found"
    fi
}

# Write metadata file
write_metadata() {
    local terminal_id="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    log_info "Writing metadata file..."
    
    cat > "$OUTPUT_DIR/.metadata" << EOF
# Profile Snapshot Metadata
# Generated by extract-profile-snapshot.sh

TERMINAL_ID=$terminal_id
EXTRACTION_TIMESTAMP=$timestamp
REFERENCE_CONTAINER=$REFERENCE_CONTAINER
REFERENCE_IMAGE=$REFERENCE_IMAGE
REFERENCE_MT5_USER=$REFERENCE_MT5_USER
REFERENCE_MT5_UID=${REFERENCE_MT5_UID:-1000}
REFERENCE_MT5_GID=${REFERENCE_MT5_GID:-1000}
REFERENCE_MOUNT_USER=${REFERENCE_MOUNT_USER:-abc}
REFERENCE_MOUNT_GROUP=${REFERENCE_MOUNT_GROUP:-users}

# Paths
TERMINAL_PATH=$REFERENCE_TERMINAL_ROOT/$terminal_id
TERMINAL_ROOT=$REFERENCE_TERMINAL_ROOT
TERMINAL_PARENT=$REFERENCE_TERMINAL_PARENT
MT5_INSTALL_PATH=$REFERENCE_MT5_INSTALL_PATH

# Note: MT5 generates random Terminal_ID on each installation
# Full Terminal directory is copied to preserve all configuration
EOF
    
    log_success "Metadata file written"
}

# Validate extracted snapshot
validate_extraction() {
    log_info "Validating extracted snapshot..."
    
    local errors=0
    
    # Check Terminal directory
    if [ ! -d "$OUTPUT_DIR/Terminal" ]; then
        log_error "Terminal directory is missing"
        ((errors++))
    elif [ -z "$(ls -A "$OUTPUT_DIR/Terminal" 2>/dev/null)" ]; then
        log_error "Terminal directory is empty"
        ((errors++))
    else
        log_success "Terminal directory validated"
    fi
    
    # Check for terminal.ini in Terminal directory
    if ! find "$OUTPUT_DIR/Terminal" -name "terminal.ini" | grep -q .; then
        log_error "terminal.ini not found in Terminal directory"
        ((errors++))
    else
        log_success "terminal.ini found"
    fi
    
    # Count files for summary
    local ea_count=$(find "$OUTPUT_DIR/Experts" -name "*.ex5" 2>/dev/null | wc -l)
    local dll_count=$(find "$OUTPUT_DIR/Libraries" -name "*.dll" 2>/dev/null | wc -l)
    local chr_count=$(find "$OUTPUT_DIR/MQL5/Profiles" -name "*.chr" 2>/dev/null | wc -l)
    local mql5_profiles_count=$(find "$OUTPUT_DIR/MQL5/Profiles/Charts" -maxdepth 1 -type d 2>/dev/null | wc -l)
    ((mql5_profiles_count=mql5_profiles_count-1))  # subtract Charts itself
    
    echo ""
    echo "=== Extraction Summary ==="
    echo "  Terminal directory: OK"
    echo "  EA files (.ex5): $ea_count"
    echo "  DLL files (.dll): $dll_count"
    echo "  Chart files (.chr): $chr_count"
    echo "  MQL5 Profiles: $mql5_profiles_count"
    echo "  Output directory: $OUTPUT_DIR"
    echo ""
    
    if [ $errors -gt 0 ]; then
        log_error "Validation failed with $errors error(s)"
        exit 3
    fi
    
    log_success "Snapshot extraction completed successfully"
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  Profile Snapshot Extraction"
    echo "=========================================="
    echo ""
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Validate container
    validate_container
    
    # Discover Terminal_ID
    local terminal_id
    terminal_id=$(discover_terminal_id)
    
    # Extract components
    copy_terminal_directory "$terminal_id"
    copy_experts_and_libraries
    copy_mql5_profiles      # Copy MQL5/Profiles/Charts including AutoTrading
    copy_profiles           # Copy Templates, SymbolSets
    copy_config
    
    # Write metadata
    write_metadata "$terminal_id"
    
    # Validate
    validate_extraction
    
    echo ""
    log_success "All done! Snapshot extracted to: $OUTPUT_DIR"
}

main "$@"
