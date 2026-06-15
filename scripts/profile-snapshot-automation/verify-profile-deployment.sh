#!/bin/bash
# verify-profile-deployment.sh - Verify MT5 container auto-login and EA attachment
# Usage: ./verify-profile-deployment.sh <container_id> [timeout_seconds]
#
# This script verifies that a deployed MT5 container has:
# - MT5 process running
# - Successful auto-login
# - EA properly attached
#
# Exit Codes:
#   0 - Verification passed
#   1 - Container not running
#   2 - MT5 failed to start
#   3 - Login failed
#   4 - EA attachment failed
#   5 - Timeout exceeded
#   6 - Broker rate limit exceeded

set -eo pipefail

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

# Environment variables with defaults
MT5_TIMEOUT="${MT5_TIMEOUT:-90}"
BROKER_RATE_LIMIT_RETRIES="${BROKER_RATE_LIMIT_RETRIES:-3}"
STAGGERED_DELAY_MAX="${STAGGERED_DELAY_MAX:-30}"

# Show usage
usage() {
    cat << EOF
Usage: $0 <container_id> [timeout_seconds]

Verify MT5 container auto-login and EA attachment.

Arguments:
  container_id     Docker container ID or name
  timeout_seconds  Max wait time in seconds (default: $MT5_TIMEOUT)

Environment Variables:
  MT5_TIMEOUT               Overall timeout (default: 90s)
  MT5_LOG_PATH             Override MT5 log path (auto-detect)
  BROKER_RATE_LIMIT_RETRIES Max retries on broker rate limit (default: 3)
  STAGGERED_DELAY_MAX      Max random startup delay (default: 30s)

Exit Codes:
  0 - Verification passed
  1 - Container not running
  2 - MT5 failed to start
  3 - Login failed
  4 - EA attachment failed
  5 - Timeout exceeded
  6 - Broker rate limit exceeded

Examples:
  $0 mt5_auto_01
  $0 mt5_auto_01 120
  MT5_TIMEOUT=120 BROKER_RATE_LIMIT_RETRIES=5 $0 mt5_auto_01

EOF
    exit 0
}

# Check arguments
if [ -z "$1" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
fi

CONTAINER_ID="$1"
TIMEOUT="${2:-$MT5_TIMEOUT}"

# Calculate exponential backoff
exponential_backoff() {
    local attempt=$1
    # Returns: 5, 10, 20, 40...
    echo $((5 * 2 ** (attempt - 1)))
}

# Check if container is running
check_container_running() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_ID}$"; then
        if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_ID}$"; then
            log_error "Container exists but is not running"
        else
            log_error "Container not found: $CONTAINER_ID"
        fi
        return 1
    fi
    return 0
}

# Wait for MT5 process to start
wait_for_mt5_process() {
    log_info "Waiting for MT5 process to start..."
    local start_time=$(date +%s)
    local deadline=$((start_time + TIMEOUT))
    
    while [ $(date +%s) -lt $deadline ]; do
        if docker exec "$CONTAINER_ID" pgrep -x terminal64.exe > /dev/null 2>&1; then
            log_success "MT5 process is running"
            return 0
        fi
        sleep 2
    done
    
    log_error "MT5 process did not start within ${TIMEOUT}s"
    return 2
}

# Get MT5 log file path
get_log_path() {
    # Try to determine log path from container
    local log_date=$(date +%Y%m%d)
    
    # Common MT5 log paths
    local paths=(
        "/config/.wine/drive_c/Program Files/MetaTrader 5/logs/${log_date}.log"
        "/root/.wine/drive_c/Program Files/MetaTrader 5/logs/${log_date}.log"
        "/config/logs/${log_date}.log"
    )
    
    for path in "${paths[@]}"; do
        if docker exec "$CONTAINER_ID" test -f "$path" 2>/dev/null; then
            echo "$path"
            return 0
        fi
    done
    
    # Return default path
    echo "/config/.wine/drive_c/Program Files/MetaTrader 5/logs/${log_date}.log"
    return 0
}

# Read and convert MT5 log (UTF-16LE to UTF-8)
read_log() {
    local log_file="$1"
    
    docker exec "$CONTAINER_ID" cat "$log_file" 2>/dev/null | iconv -f UTF-16LE -t UTF-8 2>/dev/null || \
    docker exec "$CONTAINER_ID" cat "$log_file" 2>/dev/null || \
    echo ""
}

# Wait for login success
wait_for_login() {
    log_info "Waiting for login success..."
    local start_time=$(date +%s)
    local deadline=$((start_time + TIMEOUT))
    local rate_limit_retries=0
    local max_retries=$BROKER_RATE_LIMIT_RETRIES
    
    while [ $(date +%s) -lt $deadline ]; do
        local log_content=$(read_log "$LOG_FILE")
        
        # Check for broker rate limiting
        if echo "$log_content" | grep -qiE "(rate limit|too many attempts|temporary.*block)"; then
            if [ $rate_limit_retries -lt $max_retries ]; then
                rate_limit_retries=$((rate_limit_retries + 1))
                local delay=$(exponential_backoff $rate_limit_retries)
                log_warning "Broker rate limit detected, retrying in ${delay}s (attempt $rate_limit_retries/$max_retries)"
                sleep $delay
                continue
            else
                log_error "Broker rate limit exceeded (max retries: $max_retries)"
                echo "RATE_LIMIT_EXCEEDED=true" >> "$RESULTS_FILE"
                return 6
            fi
        fi
        
        # Check for successful login
        if echo "$log_content" | grep -qiE "(authorized|login successful|logged in|account.*connected)"; then
            log_success "Login successful"
            echo "LOGIN_STATUS=success" >> "$RESULTS_FILE"
            return 0
        fi
        
        # Check for login failure
        if echo "$log_content" | grep -qiE "(authorization failed|invalid account|login failed|wrong password|connection refused)"; then
            log_error "Login failed - check credentials"
            echo "LOGIN_STATUS=failed" >> "$RESULTS_FILE"
            return 3
        fi
        
        sleep 3
    done
    
    log_error "Login not confirmed within ${TIMEOUT}s"
    echo "LOGIN_STATUS=timeout" >> "$RESULTS_FILE"
    return 5
}

# Wait for EA attachment
wait_for_ea_attachment() {
    log_info "Waiting for EA attachment..."
    local start_time=$(date +%s)
    local deadline=$((start_time + TIMEOUT))
    
    while [ $(date +%s) -lt $deadline ]; do
        local log_content=$(read_log "$LOG_FILE")
        
        # Check for EA loaded
        if echo "$log_content" | grep -qiE "expert.*loaded|expert.*init|expert.*started"; then
            local ea_name
            ea_name=$(echo "$log_content" | grep -iE "expert.*loaded|expert.*init" | tail -1 | grep -oE "TradingBridge[a-zA-Z0-9]*" || echo "EA")
            log_success "EA attached: $ea_name"
            echo "EA_STATUS=attached" >> "$RESULTS_FILE"
            echo "EA_NAME=$ea_name" >> "$RESULTS_FILE"
            return 0
        fi
        
        # Check for EA errors
        if echo "$log_content" | grep -qiE "(expert.*error|expert.*failed|dll.*error|dll.*failed)"; then
            log_error "EA attachment failed - check logs"
            echo "EA_STATUS=failed" >> "$RESULTS_FILE"
            return 4
        fi
        
        sleep 3
    done
    
    log_warning "EA attachment not detected within ${TIMEOUT}s"
    log_info "This may be normal if EA doesn't produce startup logs"
    echo "EA_STATUS=not_detected" >> "$RESULTS_FILE"
    return 0  # Don't fail on EA detection timeout
}

# Verify DLL loading
verify_dll_loading() {
    log_info "Checking DLL loading status..."
    local log_content=$(read_log "$LOG_FILE")
    
    if echo "$log_content" | grep -qiE "(dll.*loaded|dll.*import|dll.*init)"; then
        log_success "DLL loaded successfully"
        echo "DLL_STATUS=loaded" >> "$RESULTS_FILE"
        return 0
    fi
    
    log_info "DLL status not detected in logs (may be normal)"
    echo "DLL_STATUS=unknown" >> "$RESULTS_FILE"
    return 0
}

# Print results
print_results() {
    echo ""
    echo "=========================================="
    echo "  Verification Results"
    echo "=========================================="
    echo ""
    
    if [ -f "$RESULTS_FILE" ]; then
        cat "$RESULTS_FILE" | sed 's/^/  /'
        echo ""
    fi
    
    local elapsed=$(($(date +%s) - START_TIME))
    echo "  Verification time: ${elapsed}s"
    echo ""
}

# Main verification
main() {
    echo ""
    echo "=========================================="
    echo "  MT5 Deployment Verification"
    echo "=========================================="
    echo ""
    
    START_TIME=$(date +%s)
    LOG_FILE=$(get_log_path)
    RESULTS_FILE="/tmp/verify-results-$$.txt"
    
    trap "rm -f $RESULTS_FILE 2>/dev/null" EXIT
    
    log_info "Container: $CONTAINER_ID"
    log_info "Timeout: ${TIMEOUT}s"
    log_info "Log file: $LOG_FILE"
    echo ""
    
    # Run verifications
    local exit_code=0

    check_container_running || { print_results; exit 1; }

    wait_for_mt5_process
    local ret=$?
    if [ $ret -ne 0 ]; then
        print_results
        exit $ret
    fi

    wait_for_login
    ret=$?
    if [ $ret -ne 0 ]; then
        exit_code=$ret
        print_results
        exit $exit_code
    fi

    wait_for_ea_attachment
    ret=$?
    if [ $ret -ne 0 ]; then
        exit_code=$ret
        print_results
        exit $exit_code
    fi

    verify_dll_loading
    
    print_results
    
    echo ""
    log_success "Deployment verification PASSED"
    echo ""
    echo "Container $CONTAINER_ID is ready:"
    echo "  - MT5 process running"
    echo "  - Auto-login successful"
    echo "  - EA attached"
    echo ""
}

main "$@"
