#!/bin/bash
# profile-snapshot-orchestrator.sh - Orchestrator for profile snapshot workflow
# Handles extract, build, and deploy phases

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${MAGENTA}[STEP]${NC} $1"; }

# Environment variables with defaults
PARALLEL="${PARALLEL:-4}"
STAGGER="${STAGGER:-10}"
TIMEOUT="${TIMEOUT:-90}"
BASE_IMAGE="${BASE_IMAGE:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
VOLUME_PREFIX="${VOLUME_PREFIX:-mt5-creds}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-./snapshot}"
TERMINAL_ID="${TERMINAL_ID:-}"
REFERENCE_MT5_USER="${REFERENCE_MT5_USER:-kasm-user}"
REFERENCE_MT5_UID="${REFERENCE_MT5_UID:-1000}"
REFERENCE_MT5_GID="${REFERENCE_MT5_GID:-1002}"

# Reference container (must be specified)
REFERENCE_CONTAINER="${REFERENCE_CONTAINER:-}"

# Account CSV file
ACCOUNTS_CSV="${ACCOUNTS_CSV:-}"

# Project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Show usage
usage() {
    cat << EOF
Usage: $0 <mode> [options]

Profile Snapshot Automation Orchestrator

Modes:
    extract     Extract profile snapshot from reference container
    build       Build base Docker image from snapshot
    deploy      Deploy containers from credentials CSV
    full        Run full pipeline (extract, build, deploy)

Options:
    --reference <container>   Reference container name for extraction
    --snapshot <dir>          Snapshot directory (default: ./snapshot)
    --base-image <image>      Base Docker image for build
    --image-tag <tag>         Tag for built image
    --accounts <csv>          Credentials CSV file for deployment
    --parallel <n>            Parallel workers for build (default: 4)
    --stagger <n>             Stagger delay in seconds (default: 10)
    --terminal-id <id>        Terminal ID for all containers
    --project-dir <dir>       Project directory (default: parent of scripts)

Examples:
    # Full pipeline
    $0 full --reference mt5_01 --accounts credentials.csv

    # Extract only
    $0 extract --reference mt5_01 --snapshot ./snapshot

    # Build only
    $0 build --snapshot ./snapshot --image-tag mt5-local:working

    # Deploy only
    $0 deploy --accounts credentials.csv

Environment Variables:
    SNAPSHOT_DIR         Snapshot directory (default: ./snapshot)
    BASE_IMAGE           Base image for build
    IMAGE_TAG            Tag for built image
    TERMINAL_ID          Terminal ID to use
    REFERENCE_CONTAINER  Reference container name

EOF
}

# Parse command line arguments
parse_args() {
    MODE=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            extract|build|deploy|full)
                MODE="$1"
                shift
                ;;
            --reference)
                REFERENCE_CONTAINER="$2"
                shift 2
                ;;
            --snapshot)
                SNAPSHOT_DIR="$2"
                shift 2
                ;;
            --base-image)
                BASE_IMAGE="$2"
                shift 2
                ;;
            --image-tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --accounts)
                ACCOUNTS_CSV="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL="$2"
                shift 2
                ;;
            --stagger)
                STAGGER="$2"
                shift 2
                ;;
            --terminal-id)
                TERMINAL_ID="$2"
                shift 2
                ;;
            --project-dir)
                PROJECT_DIR="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    if [ -z "$MODE" ]; then
        log_error "Mode not specified"
        usage
        exit 1
    fi
}

# Resolve defaults based on snapshot metadata
resolve_defaults() {
    if [ -f "$SNAPSHOT_DIR/.metadata" ]; then
        log_info "Reading metadata from snapshot..."
        
        if [ -z "$BASE_IMAGE" ]; then
            BASE_IMAGE=$(grep "^REFERENCE_IMAGE=" "$SNAPSHOT_DIR/.metadata" 2>/dev/null | cut -d= -f2)
        fi
        
        if [ -z "$IMAGE_TAG" ]; then
            IMAGE_TAG="mt5-local:working"
        fi
        
        if [ -z "$TERMINAL_ID" ]; then
            TERMINAL_ID=$(grep "^TERMINAL_ID=" "$SNAPSHOT_DIR/.metadata" 2>/dev/null | cut -d= -f2)
        fi
        
        if [ -z "$REFERENCE_CONTAINER" ]; then
            REFERENCE_CONTAINER=$(grep "^REFERENCE_CONTAINER=" "$SNAPSHOT_DIR/.metadata" 2>/dev/null | cut -d= -f2)
        fi
        
        log_info "Resolved: BASE_IMAGE=$BASE_IMAGE, IMAGE_TAG=$IMAGE_TAG"
        log_info "Resolved: TERMINAL_ID=$TERMINAL_ID, REFERENCE_CONTAINER=$REFERENCE_CONTAINER"
    fi
}

# Extract profile snapshot from reference container
do_extract() {
    log_step "=== EXTRACTION PHASE ==="
    
    if [ -z "$REFERENCE_CONTAINER" ]; then
        log_error "Reference container not specified (--reference)"
        exit 1
    fi
    
    log_info "Reference container: $REFERENCE_CONTAINER"
    log_info "Snapshot directory: $SNAPSHOT_DIR"
    echo ""
    
    local extract_script="$PROJECT_DIR/scripts/profile-snapshot-automation/extract-profile-snapshot.sh"
    
    if [ ! -f "$extract_script" ]; then
        log_error "Extract script not found: $extract_script"
        exit 1
    fi
    
    SNAPSHOT_DIR="$SNAPSHOT_DIR" REFERENCE_CONTAINER="$REFERENCE_CONTAINER" bash "$extract_script"
    
    log_success "Extraction completed"
}

# Build base Docker image from snapshot
do_build() {
    log_step "=== BUILD PHASE ==="
    
    resolve_defaults
    
    if [ -z "$BASE_IMAGE" ]; then
        log_error "Base image not specified (--base-image or metadata)"
        exit 1
    fi
    
    if [ -z "$IMAGE_TAG" ]; then
        IMAGE_TAG="mt5-local:working"
    fi
    
    log_info "Base image: $BASE_IMAGE"
    log_info "Image tag: $IMAGE_TAG"
    log_info "Snapshot directory: $SNAPSHOT_DIR"
    echo ""
    
    local build_script="$PROJECT_DIR/scripts/profile-snapshot-automation/build-profile-base.sh"
    
    if [ ! -f "$build_script" ]; then
        log_error "Build script not found: $build_script"
        exit 1
    fi
    
    BASE_IMAGE="$BASE_IMAGE" IMAGE_TAG="$IMAGE_TAG" SNAPSHOT_DIR="$SNAPSHOT_DIR" bash "$build_script"
    
    log_success "Build completed"
}

# Find available port
find_available_port() {
    local port=$1
    local max_attempts=100
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ! netstat -tuln 2>/dev/null | grep -q ":$port " && \
           ! ss -tuln 2>/dev/null | grep -q ":$port "; then
            break
        fi
        port=$((port + 1))
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -ge $max_attempts ]; then
        log_error "Could not find available port after $max_attempts attempts"
        return 1
    fi
    
    echo "$port"
}

# Deploy containers
do_deploy() {
    log_step "=== DEPLOYMENT PHASE ==="
    
    if [ -z "$ACCOUNTS_CSV" ]; then
        log_error "Accounts CSV not specified"
        exit 2
    fi

    resolve_defaults
    
    log_info "Reading accounts from: $ACCOUNTS_CSV"
    log_info "Image: $IMAGE_TAG"
    log_info "Base image: $BASE_IMAGE"
    log_info "MT5 runtime user: kasm-user (1000:1002)"
    log_info "Stagger delay: ${STAGGER}s"
    log_info "Note: Container will use base image /init entrypoint"
    echo ""
    
    local count=0
    tail -n +2 "$ACCOUNTS_CSV" | while IFS=, read -r account_id login password server; do
        account_id=$(echo "$account_id" | tr -d '"')
        login=$(echo "$login" | tr -d '"')
        server=$(echo "$server" | tr -d '"')
        
        if [ -z "$account_id" ]; then
            continue
        fi
        
        count=$((count + 1))
        
        local stagger_delay=$((RANDOM % STAGGER))
        if [ $count -gt 1 ]; then
            log_info "Staggering startup by ${stagger_delay}s..."
            sleep "$stagger_delay"
        fi
        
        local vnc_port=$(find_available_port $((3000 + count - 1)))
        local rpc_port=$(find_available_port $((8001 + count - 1)))
        local bridge_port=$(find_available_port $((8080 + count - 1)))
        
        if [ -z "$vnc_port" ] || [ -z "$rpc_port" ] || [ -z "$bridge_port" ]; then
            log_error "Failed to find available ports for: $account_id"
            continue
        fi
        
        local volume_name="$VOLUME_PREFIX-$account_id"
        local config_dir="$PROJECT_DIR/configs/$account_id"
        local logs_dir="$PROJECT_DIR/logs/$account_id"
        
        # Dynamically discover reference config dir from mounts
        local reference_config_dir=""
        if docker ps -a --format '{{.Names}}' | grep -q "^${REFERENCE_CONTAINER}$"; then
            reference_config_dir=$(docker inspect "$REFERENCE_CONTAINER" --format '{{ range .Mounts }}{{ if eq .Destination "/config" }}{{ .Source }}{{ end }}{{ end }}')
        fi
        if [ -z "$reference_config_dir" ] || [ ! -d "$reference_config_dir" ]; then
            reference_config_dir="$PROJECT_DIR/configs/account_01"
        fi
        
        mkdir -p "$config_dir" "$logs_dir"

        # Remove existing .wine directory for fresh Wine prefix
        # This ensures container starts with clean state
        if [ -d "$config_dir/.wine" ]; then
            log_info "Removing existing .wine directory for fresh Wine prefix..."
            # Use docker run with alpine to remove with correct permissions (1000:1002)
            docker run --rm -v "$config_dir:/data" alpine sh -c "
                chown -R 1000:1002 /data 2>/dev/null || true
                rm -rf /data/.wine
            "
        fi

        # Copy .wine from reference container if not exists (Wine needs pre-initialized prefix)
        if [ ! -d "$config_dir/.wine" ] && [ -d "$reference_config_dir/.wine" ]; then
            log_info "Copying Wine prefix from reference container..."
            cp -a "$reference_config_dir/.wine" "$config_dir/.wine"
        fi

        # Clean MT5 logs to start fresh
        log_info "Cleaning MT5 logs..."
        docker run --rm -v "$config_dir:/config" alpine sh -c "
            # Clean MT5 terminal logs
            find /config/.wine/drive_c/Program\ Files/MetaTrader\ 5/logs -name '*.log' -type f 2>/dev/null | while read logfile; do
                echo \"Cleaning: \$logfile\"
                > \"\$logfile\"
            done
            # Clean MQL5 logs
            find /config/.wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/logs -name '*.log' -type f 2>/dev/null | while read logfile; do
                echo \"Cleaning: \$logfile\"
                > \"\$logfile\"
            done
            # Clean Wine logs
            rm -rf /config/.wine/drive_c/users/abc/AppData/Local/Temp/* 2>/dev/null || true
            rm -rf /config/.wine/drive_c/users/abc/Temp/* 2>/dev/null || true
            echo \"MT5 logs cleaned successfully\"
        "

        # ALWAYS update Wine Terminal data with correct account info from credentials volume
        # This ensures each container uses its own account, not the reference account
        log_info "Updating Wine Terminal data with correct account credentials..."
        
        # Extract credentials for use in the docker run command
        if [ -f "$PROJECT_DIR/configs/$VOLUME_PREFIX-$account_id/credentials/terminal.ini" ]; then
            local cred_login=$(grep '^Login=' "$PROJECT_DIR/configs/$VOLUME_PREFIX-$account_id/credentials/terminal.ini" 2>/dev/null | cut -d= -f2)
            local cred_server=$(grep '^Server=' "$PROJECT_DIR/configs/$VOLUME_PREFIX-$account_id/credentials/terminal.ini" 2>/dev/null | cut -d= -f2)
            local cred_password=$(grep '^Password=' "$PROJECT_DIR/configs/$VOLUME_PREFIX-$account_id/credentials/terminal.ini" 2>/dev/null | cut -d= -f2)
            
            docker run --rm \
                -v "$config_dir:/config" \
                alpine sh -c "
                    set -e
                    MT5_USER_DIR=\"/config/.wine/drive_c/users/abc/AppData/Roaming/MetaQuotes/Terminal\"
                    LOGIN='$cred_login'
                    SERVER='$cred_server'
                    PASSWORD='$cred_password'
                    
                    # Update each Terminal subdirectory
                    for TERMINAL_DIR in \$(ls -d \$MT5_USER_DIR/*/ 2>/dev/null); do
                        echo \"Updating Terminal directory: \$TERMINAL_DIR\"
                        
                        # Update terminal.ini
                        if [ -f \"\$MT5_USER_DIR/terminal.ini\" ]; then
                            cp \"\$MT5_USER_DIR/terminal.ini\" \"\$TERMINAL_DIR/terminal.ini\"
                        fi
                        
                        # Create hdd.v2 directory and files
                        mkdir -p \"\$TERMINAL_DIR/hdd.v2\"
                        
                        printf '[Accounts]\nCount=1\nDefault=%s\n' \"\$LOGIN\" > \"\$TERMINAL_DIR/hdd.v2/accounts.ini\"
                        echo \"  - Created accounts.ini (login: \$LOGIN)\"
                        
                        printf '[%s]\nServer=%s\nLogin=%s\nLastLogin=%s\n' \"\$LOGIN\" \"\$SERVER\" \"\$LOGIN\" \"\$LOGIN\" > \"\$TERMINAL_DIR/hdd.v2/connections.ini\"
                        echo \"  - Created connections.ini (server: \$SERVER)\"
                    done
                    
                    # Generate startup.ini for auto-login
                    printf '[Common]\nLogin=%s\nPassword=%s\nServer=%s\n' \"\$LOGIN\" \"\$PASSWORD\" \"\$SERVER\" > /config/startup.ini
                    echo \"Generated startup.ini for auto-login\"
                "
        else
            log_warning "No credentials found at $PROJECT_DIR/configs/$VOLUME_PREFIX-$account_id/credentials/terminal.ini"
            log_info "Generating startup.ini without credentials..."
            docker run --rm \
                -v "$config_dir:/config" \
                alpine sh -c "
                    printf '[Common]\nLogin=0\nPassword=\nServer=\n' > /config/startup.ini
                    echo \"Created empty startup.ini\"
                "
        fi

        touch "$config_dir/.initialized-from-snapshot"

        # Fix ownership BEFORE container starts (use kasm-user 1000:1002)
        # MUST run after all files (startup.ini, credentials, templates, etc.) are written
        log_info "Fixing ownership for $config_dir to kasm-user (1000:1002)..."
        docker run --rm -v "$config_dir:/data" alpine sh -c "
            chown -R 1000:1002 /data
            find /data -type d -exec chmod 755 {} +
            find /data -type f -exec chmod 644 {} +
        "

        
        log_info "Deploying container: mt5_${account_id}"
        log_info "  Ports: VNC=$vnc_port, RPC=$rpc_port, Bridge=$bridge_port"
        log_info "  Config: $config_dir -> /config"
        log_info "  Logs: $logs_dir -> /logs"
        log_info "  Credentials volume: $volume_name -> /config/credentials"
        log_info "  Terminal ID: ${TERMINAL_ID:-auto-detect from snapshot}"
        log_info "  Runtime user: kasm-user (1000:1002 - LSIO default)"

        if docker ps -a --format '{{.Names}}' | grep -q "^mt5_${account_id}$"; then
            log_warning "Container mt5_${account_id} already exists, removing old container first"
            docker rm -f "mt5_${account_id}" >/dev/null 2>&1 || true
        fi
        
        docker run -d \
            --name "mt5_${account_id}" \
            --entrypoint "/init" \
            -p "${vnc_port}:3000" \
            -p "${rpc_port}:8001" \
            -p "${bridge_port}:8080" \
            -v "$config_dir:/config" \
            -v "$logs_dir:/logs" \
            -v "$volume_name:/config/credentials" \
            -v "$SCRIPT_DIR/start.sh:/Metatrader/start.sh:ro" \
            -e PUID=1000 \
            -e PGID=1002 \
            -e WINEPREFIX="/config/.wine" \
            -e MT5_INSTALL_PATH="/config/.wine/drive_c/Program Files/MetaTrader 5" \
            -e TERMINAL_ID=${TERMINAL_ID} \
            -e MT5_UID=1000 \
            -e MT5_GID=1002 \
            -e TZ="Asia/Ho_Chi_Minh" \
            --restart unless-stopped \
            --network mt5-network \
            "$IMAGE_TAG"
        
        log_success "Container mt5_${account_id} deployed"
        
    done
    
    echo ""
    log_success "Deployment completed"
    echo ""
    log_info "Containers deployed:"
    docker ps --filter "name=mt5_" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Run full pipeline
do_full() {
    log_step "=== FULL PIPELINE ==="
    
    if [ -z "$REFERENCE_CONTAINER" ] || [ -z "$ACCOUNTS_CSV" ]; then
        log_error "Both --reference and --accounts required for full pipeline"
        exit 1
    fi
    
    do_extract
    echo ""
    
    do_build
    echo ""
    
    do_deploy
    echo ""
    
    log_success "Full pipeline completed!"
}

# Main
main() {
    parse_args "$@"
    
    case $MODE in
        extract)
            do_extract
            ;;
        build)
            do_build
            ;;
        deploy)
            do_deploy
            ;;
        full)
            do_full
            ;;
        *)
            log_error "Unknown mode: $MODE"
            usage
            exit 1
            ;;
    esac
}

main "$@"
