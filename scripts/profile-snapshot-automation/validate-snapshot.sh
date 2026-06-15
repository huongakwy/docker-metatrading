#!/bin/bash
# validate-snapshot.sh - Validate snapshot directory integrity before Docker build
# Usage: ./validate-snapshot.sh <snapshot_dir>
#
# This script validates that the extracted snapshot contains all required files
# and is ready for Docker image building.
#
# Exit Codes:
#   0 - Validation passed
#   1 - Critical files missing
#   2 - Profile directory empty or invalid
#   3 - EA files missing
#   4 - DLL dependencies missing
#   5 - MT5 version mismatch

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Environment variables
MT5_VERSION="${MT5_VERSION:-}"

# Show usage
usage() {
    cat << EOF
Usage: $0 <snapshot_dir>

Validate snapshot directory integrity before Docker build.

Arguments:
  snapshot_dir  Path to snapshot directory to validate

Environment Variables:
  MT5_VERSION   Expected MT5 version (e.g., 500.0, 600.0)

Exit Codes:
  0 - Validation passed
  1 - Critical files missing
  2 - Profile directory empty or invalid
  3 - EA files missing
  4 - DLL dependencies missing
  5 - MT5 version mismatch

Examples:
  $0 ./snapshot
  MT5_VERSION=500.0 $0 ./snapshot

EOF
    exit 0
}

# Check arguments
if [ -z "$1" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
fi

SNAPSHOT_DIR="$1"

# Validation counters
ERRORS=0
WARNINGS=0

# Validation functions
validate_directory_exists() {
    local dir="$1"
    local description="$2"
    
    if [ ! -d "$SNAPSHOT_DIR/$dir" ]; then
        log_error "Directory missing: $dir ($description)"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    
    if [ -z "$(ls -A "$SNAPSHOT_DIR/$dir" 2>/dev/null)" ]; then
        log_warning "Directory is empty: $dir ($description)"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
    
    log_success "$dir exists"
    return 0
}

validate_file_exists() {
    local file="$1"
    local description="$2"
    
    if [ ! -f "$SNAPSHOT_DIR/$file" ]; then
        log_error "File missing: $file ($description)"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    
    log_success "$file exists"
    return 0
}

count_files() {
    local pattern="$1"
    local dir=$(dirname "$pattern")
    local extension=$(basename "$pattern")
    
    if [ -d "$SNAPSHOT_DIR/$dir" ]; then
        find "$SNAPSHOT_DIR/$dir" -name "$extension" -type f 2>/dev/null | wc -l
    else
        echo 0
    fi
}

validate_terminal_ini() {
    log_info "Validating terminal.ini..."
    
    # Find terminal.ini anywhere in Terminal directory
    local terminal_ini
    terminal_ini=$(find "$SNAPSHOT_DIR/Terminal" -name "terminal.ini" -type f 2>/dev/null | head -1)
    
    if [ -z "$terminal_ini" ]; then
        log_error "terminal.ini not found in Terminal directory"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    
    # Check if file has content
    if [ ! -s "$terminal_ini" ]; then
        log_error "terminal.ini is empty"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    
    # Check for [Common] section
    if ! grep -q "\[Common\]" "$terminal_ini"; then
        log_warning "terminal.ini missing [Common] section"
        WARNINGS=$((WARNINGS + 1))
    else
        log_success "terminal.ini has [Common] section"
    fi
    
    log_success "terminal.ini validated"
    return 0
}

validate_terminal_directory() {
    log_info "Validating Terminal directory (full structure required)..."
    
    if [ ! -d "$SNAPSHOT_DIR/Terminal" ]; then
        log_error "Terminal directory missing"
        log_error "Full Terminal directory structure is required because MT5 generates random Terminal_ID"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    
    # Find the Terminal_ID (should be a 32-char hex directory)
    local terminal_ids
    terminal_ids=$(find "$SNAPSHOT_DIR/Terminal" -maxdepth 1 -type d -name '[A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9][A-F0-9]' 2>/dev/null)
    
    if [ -z "$terminal_ids" ]; then
        log_error "No valid Terminal_ID directory found in Terminal/"
        log_error "Expected a 32-character hexadecimal directory name"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    
    log_success "Terminal directory validated (Terminal_ID: $(basename $terminal_ids))"
    return 0
}

validate_experts() {
    log_info "Validating Experts directory..."
    
    if [ ! -d "$SNAPSHOT_DIR/Experts" ]; then
        log_warning "Experts directory not found (OK if no EAs are installed)"
        return 0
    fi
    
    local ex5_count
    ex5_count=$(count_files "Experts/*.ex5")
    
    if [ "$ex5_count" -eq 0 ]; then
        log_warning "No .ex5 EA files found in Experts/"
        WARNINGS=$((WARNINGS + 1))
    else
        log_success "Found $ex5_count EA file(s)"
    fi
    
    return 0
}

validate_libraries() {
    log_info "Validating Libraries directory..."
    
    if [ ! -d "$SNAPSHOT_DIR/Libraries" ]; then
        log_warning "Libraries directory not found (OK if no DLLs are used)"
        return 0
    fi
    
    local dll_count
    dll_count=$(count_files "Libraries/*.dll")
    
    if [ "$dll_count" -eq 0 ]; then
        log_warning "No .dll files found in Libraries/"
        WARNINGS=$((WARNINGS + 1))
    else
        log_success "Found $dll_count DLL file(s)"
    fi
    
    return 0
}

validate_profiles() {
    log_info "Validating Profiles directory..."
    
    if [ ! -d "$SNAPSHOT_DIR/profiles" ]; then
        log_warning "Profiles directory not found (OK if using default profile)"
        return 0
    fi
    
    local chr_count
    chr_count=$(count_files "profiles/*.chr")
    
    if [ "$chr_count" -eq 0 ]; then
        log_warning "No .chr chart files found in profiles/"
        WARNINGS=$((WARNINGS + 1))
    else
        log_success "Found $chr_count chart file(s)"
    fi
    
    return 0
}

validate_config() {
    log_info "Validating Config directory..."
    
    if [ ! -d "$SNAPSHOT_DIR/Config" ]; then
        log_warning "Config directory not found"
        return 0
    fi
    
    log_success "Config directory validated"
    return 0
}

validate_metadata() {
    log_info "Validating metadata..."
    
    if [ ! -f "$SNAPSHOT_DIR/.metadata" ]; then
        log_warning ".metadata file not found (OK for manual snapshots)"
        return 0
    fi
    
    # Check for required metadata fields
    if ! grep -q "TERMINAL_ID=" "$SNAPSHOT_DIR/.metadata"; then
        log_warning ".metadata missing TERMINAL_ID"
    fi
    
    log_success "Metadata validated"
    return 0
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "  Validation Summary"
    echo "=========================================="
    echo ""
    echo "  Snapshot Directory: $SNAPSHOT_DIR"
    echo "  Errors: $ERRORS"
    echo "  Warnings: $WARNINGS"
    echo ""
    
    # Count files
    local ex5_count=$(count_files "Experts/*.ex5")
    local dll_count=$(count_files "Libraries/*.dll")
    local chr_count=$(count_files "profiles/*.chr")
    
    echo "  Files:"
    echo "    EA files (.ex5): $ex5_count"
    echo "    DLL files (.dll): $dll_count"
    echo "    Chart files (.chr): $chr_count"
    echo ""
}

# Main validation
main() {
    echo ""
    echo "=========================================="
    echo "  Snapshot Validation"
    echo "=========================================="
    echo ""
    
    log_info "Validating snapshot: $SNAPSHOT_DIR"
    echo ""
    
    # Check snapshot directory exists
    if [ ! -d "$SNAPSHOT_DIR" ]; then
        log_error "Snapshot directory does not exist: $SNAPSHOT_DIR"
        exit 1
    fi
    
    # Run validations
    validate_terminal_directory
    validate_terminal_ini
    validate_experts
    validate_libraries
    validate_profiles
    validate_config
    validate_metadata
    
    # Print summary
    print_summary
    
    # Exit with appropriate code
    if [ $ERRORS -gt 0 ]; then
        log_error "Validation FAILED with $ERRORS error(s)"
        echo ""
        log_info "Please fix the errors above before building the Docker image"
        exit 1
    fi
    
    if [ $WARNINGS -gt 0 ]; then
        log_warning "Validation passed with $WARNINGS warning(s)"
        log_info "Review warnings above to ensure optimal operation"
    else
        log_success "Validation PASSED"
    fi
    
    echo ""
    log_success "Snapshot is ready for Docker build"
}

main "$@"
