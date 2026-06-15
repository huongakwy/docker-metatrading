#!/bin/bash
# ============================================================================
# Deploy and Switch MT5 - Combined workflow
# Deploys containers from CSV and automatically switches to correct account
# Usage: ./deploy-and-switch.sh --accounts credentials.csv --reference mt5_01
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

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

# Environment defaults
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
REFERENCE_CONTAINER="${REFERENCE_CONTAINER:-}"
ACCOUNTS_CSV="${ACCOUNTS_CSV:-}"

# MT5 paths inside container
MT5_BASE="/config/.wine/drive_c/Program Files/MetaTrader 5"
MT5_DATA_BASE="/config/.wine/drive_c/users/abc/AppData/Roaming/MetaQuotes/Terminal"

# ============================================================================
# Usage
# ============================================================================
usage() {
    cat << EOF
Usage: $0 [options]

Deploy MT5 containers and auto-switch to correct account from CSV

Options:
    --accounts <csv>          Credentials CSV file (required)
    --reference <container>   Reference container name for snapshot (required)
    --snapshot <dir>          Snapshot directory (default: ./snapshot)
    --image-tag <tag>         Docker image tag (default: mt5-local:working)
    --parallel <n>            Parallel workers (default: 4)
    --stagger <n>             Stagger delay in seconds (default: 10)
    --project-dir <dir>       Project directory
    --help, -h                Show this help

Examples:
    $0 --accounts credentials.csv --reference mt5_01
    $0 --accounts credentials.csv --reference mt5_01 --stagger 5

CSV Format:
    instance_name,mt5_login,mt5_password,mt5_server
    02,413894078,Hoainam0303@,Exness-MT5Trial6
    03,433755587,Hoainam0303@,Exness-MT5Trial7

Note: Container name = mt5_{instance_name}
      mt5_02 will login with account from row instance_name=02
EOF
}

# ============================================================================
# Parse arguments
# ============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --accounts)
                ACCOUNTS_CSV="$2"
                shift 2
                ;;
            --reference)
                REFERENCE_CONTAINER="$2"
                shift 2
                ;;
            --snapshot)
                SNAPSHOT_DIR="$2"
                shift 2
                ;;
            --image-tag)
                IMAGE_TAG="$2"
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

    if [ -z "$ACCOUNTS_CSV" ]; then
        log_error "--accounts is required"
        usage
        exit 1
    fi

    if [ -z "$REFERENCE_CONTAINER" ]; then
        log_error "--reference is required"
        usage
        exit 1
    fi
}

# ============================================================================
# Resolve defaults from snapshot metadata
# ============================================================================
resolve_defaults() {
    echo "[DEBUG] resolve_defaults: START" >&2
    
    if [ -f "$SNAPSHOT_DIR/.metadata" ]; then
        log_info "Reading metadata from snapshot..."

        if [ -z "$BASE_IMAGE" ]; then
            BASE_IMAGE=$(grep "^REFERENCE_IMAGE=" "$SNAPSHOT_DIR/.metadata" 2>/dev/null | cut -d= -f2)
        fi

        if [ -z "$IMAGE_TAG" ]; then
            IMAGE_TAG=$(grep "^IMAGE_TAG=" "$SNAPSHOT_DIR/.metadata" 2>/dev/null | cut -d= -f2)
            [ -z "$IMAGE_TAG" ] && IMAGE_TAG="mt5-local:working"
        fi

        if [ -z "$TERMINAL_ID" ]; then
            TERMINAL_ID=$(grep "^TERMINAL_ID=" "$SNAPSHOT_DIR/.metadata" 2>/dev/null | cut -d= -f2)
        fi

        log_info "Resolved: BASE_IMAGE=$BASE_IMAGE, IMAGE_TAG=$IMAGE_TAG"
        log_info "Resolved: TERMINAL_ID=$TERMINAL_ID, REFERENCE_CONTAINER=$REFERENCE_CONTAINER"
    fi

    [ -z "$IMAGE_TAG" ] && IMAGE_TAG="mt5-local:working"
    
    echo "[DEBUG] resolve_defaults: END" >&2
}

# ============================================================================
# Find available port
# ============================================================================
find_available_port() {
    local port=$1
    local max_attempts=100
    local attempt=0
    local quiet=$2

    if [ "$quiet" != "quiet" ]; then
        log_info "Finding available port starting from $port..."
    fi

    while [ $attempt -lt $max_attempts ]; do
        # Quick check using docker ps instead of netstat/ss
        if ! docker ps --format '{{.Ports}}' | grep -q "0\.0\.0\.0:$port->" && \
           ! docker ps --format '{{.Ports}}' | grep -q ":$port->"; then
            if [ "$quiet" != "quiet" ]; then
                log_info "Found available port: $port"
            fi
            break
        fi
        if [ "$quiet" != "quiet" ]; then
            log_info "Port $port in use, trying next..."
        fi
        port=$((port + 1))
        attempt=$((attempt + 1))
    done

    if [ $attempt -ge $max_attempts ]; then
        if [ "$quiet" != "quiet" ]; then
            log_error "Could not find available port after $max_attempts attempts"
        fi
        return 1
    fi

    echo "$port"
}

# ============================================================================
# Get account info from CSV by instance_name
# ============================================================================
get_account_from_csv() {
    local instance_name="$1"

    # Skip header
    if [ "$instance_name" = "instance_name" ]; then
        return 1
    fi

    # Find the row with matching instance_name
    local row=$(grep "^$instance_name," "$ACCOUNTS_CSV" 2>/dev/null | head -1)

    if [ -z "$row" ]; then
        log_error "Account '$instance_name' not found in $ACCOUNTS_CSV"
        return 1
    fi

    # Parse CSV - handle potential spaces after comma
    LOGIN=$(echo "$row" | sed 's/.*,\([0-9]*\),.*/\1/' | head -1)
    SERVER=$(echo "$row" | sed 's/.*,\([0-9]*\),\([^,]*\),.*/\2/' | head -1)

    # Better parsing using awk
    LOGIN=$(echo "$row" | awk -F',' '{gsub(/"/, "", $2); print $2}')
    PASSWORD=$(echo "$row" | awk -F',' '{gsub(/"/, "", $3); print $3}')
    SERVER=$(echo "$row" | awk -F',' '{gsub(/"/, "", $4); print $4}')

    log_info "Found account: $instance_name -> Login: $LOGIN, Server: $SERVER"
}

# ============================================================================
# Deploy single container
# ============================================================================
deploy_container() {
    local instance_name="$1"
    local count="$2"

    local CONTAINER="mt5_${instance_name}"

    log_step "=== DEPLOYING $CONTAINER ==="

    local stagger_delay=$((RANDOM % STAGGER))
    if [ $count -gt 1 ]; then
        log_info "Staggering startup by ${stagger_delay}s..."
        sleep "$stagger_delay"
    fi

    # Find available ports - pass "quiet" to suppress detailed logs
    local vnc_port=$(find_available_port $((3000 + count - 1)) quiet)
    local rpc_port=$(find_available_port $((8001 + count - 1)) quiet)
    local bridge_port=$(find_available_port $((8080 + count - 1)) quiet)

    if [ -z "$vnc_port" ] || [ -z "$rpc_port" ] || [ -z "$bridge_port" ]; then
        log_error "Failed to find available ports for: $instance_name"
        return 1
    fi

    log_info "  Allocated ports: VNC=$vnc_port, RPC=$rpc_port, Bridge=$bridge_port"

    local volume_name="$VOLUME_PREFIX-$instance_name"
    local config_dir="$PROJECT_DIR/configs/$instance_name"
    local logs_dir="$PROJECT_DIR/logs/$instance_name"

    # Find reference config dir
    local reference_config_dir=""
    if docker ps -a --format '{{.Names}}' | grep -q "^${REFERENCE_CONTAINER}$"; then
        reference_config_dir=$(docker inspect "$REFERENCE_CONTAINER" --format '{{ range .Mounts }}{{ if eq .Destination "/config" }}{{ .Source }}{{ end }}{{ end }}')
    fi
    if [ -z "$reference_config_dir" ] || [ ! -d "$reference_config_dir" ]; then
        reference_config_dir="$PROJECT_DIR/configs/account_01"
    fi

    mkdir -p "$config_dir" "$logs_dir"

    # Remove existing .wine directory for fresh start
    if [ -d "$config_dir/.wine" ]; then
        log_info "Removing existing .wine directory for fresh Wine prefix..."
        docker run --rm -v "$config_dir:/data" alpine sh -c "
            chown -R 1000:1002 /data 2>/dev/null || true
            rm -rf /data/.wine
        "
    fi

    # Copy .wine from reference container
    if [ ! -d "$config_dir/.wine" ] && [ -d "$reference_config_dir/.wine" ]; then
        log_info "Copying Wine prefix from reference container..."
        cp -a "$reference_config_dir/.wine" "$config_dir/.wine"
    fi

    # Clean MT5 logs
    log_info "Cleaning MT5 logs..."
    docker run --rm -v "$config_dir:/config" alpine sh -c "
        find /config/.wine/drive_c/Program\ Files/MetaTrader\ 5/logs -name '*.log' -type f 2>/dev/null | while read logfile; do
            > \"\$logfile\"
        done
        find /config/.wine/drive_c/Program\ Files/MetaTrader\ 5/MQL5/logs -name '*.log' -type f 2>/dev/null | while read logfile; do
            > \"\$logfile\"
        done
        rm -rf /config/.wine/drive_c/users/abc/AppData/Local/Temp/* 2>/dev/null || true
        rm -rf /config/.wine/drive_c/users/abc/Temp/* 2>/dev/null || true
    "

    # Get terminal ID for this container
    local container_terminal_id=""
    if [ -n "$TERMINAL_ID" ]; then
        container_terminal_id="$TERMINAL_ID"
    else
        # Use reference terminal ID if available
        container_terminal_id="D0E8209F77C8CF37AD8BF550E51FF075"
    fi

    log_info "Using Terminal ID: $container_terminal_id"
    local MT5_DATA="$MT5_DATA_BASE/$container_terminal_id"

    # Create initial terminal.ini for the container (will be updated by switch_account)
    log_info "Creating initial terminal.ini..."
    docker run --rm -v "$config_dir:/config" alpine sh -c "
        mkdir -p '$MT5_DATA'
        printf '[Common]
Login=0
LastLogin=0
Server=
ProfileLast=Default
' > '$MT5_DATA/terminal.ini'
    "

    # Fix ownership of all files (including the newly created terminal.ini and directories)
    log_info "Fixing ownership to kasm-user (1000:1002)..."
    docker run --rm -v "$config_dir:/data" alpine sh -c "
        chown -R 1000:1002 /data
        find /data -type d -exec chmod 755 {} +
        find /data -type f -exec chmod 644 {} +
    "


    # Create credential volume
    if ! docker volume ls --format '{{.Name}}' | grep -q "^${volume_name}$"; then
        log_info "Creating credential volume: $volume_name"
        docker volume create "$volume_name" >/dev/null 2>&1 || true
    fi

    touch "$config_dir/.initialized-from-snapshot"

    log_info "Deploying container: $CONTAINER"
    log_info "  Ports: VNC=$vnc_port, RPC=$rpc_port, Bridge=$bridge_port"

    # Remove existing container if any
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        log_warning "Container $CONTAINER already exists, removing..."
        docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    fi

    # Deploy container
    docker run -d \
        --name "$CONTAINER" \
        --entrypoint "/init" \
        -p "${vnc_port}:3000" \
        -p "${rpc_port}:8001" \
        -p "${bridge_port}:8080" \
        -v "$config_dir:/config" \
        -v "$logs_dir:/logs" \
        -v "$volume_name:/config/credentials" \
        -e PUID=1000 \
        -e PGID=1002 \
        -e WINEPREFIX="/config/.wine" \
        -e MT5_INSTALL_PATH="/config/.wine/drive_c/Program Files/MetaTrader 5" \
        -e TERMINAL_ID="$container_terminal_id" \
        -e MT5_UID=1000 \
        -e MT5_GID=1002 \
        -e TZ="Asia/Ho_Chi_Minh" \
        --restart unless-stopped \
        --network mt5-network \
        "$IMAGE_TAG"

    log_success "Container $CONTAINER deployed"
    echo ""
}

# ============================================================================
# Wait for MT5 to start
# ============================================================================
wait_for_mt5() {
    local container="$1"
    local timeout="${2:-60}"

    log_info "Waiting for MT5 to start (timeout: ${timeout}s)..."

    for i in $(seq 1 $timeout); do
        if docker exec "$container" pgrep -f terminal64.exe >/dev/null 2>&1; then
            log_success "MT5 is running"
            return 0
        fi
        # Also check if container is still running
        if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            log_error "Container $container is not running"
            return 1
        fi
        sleep 1
    done

    log_warning "MT5 did not start within ${timeout}s"
    return 1
}

# ============================================================================
# Switch account in container
# ============================================================================
switch_account() {
    local container="$1"
    local login="$2"
    local password="$3"
    local server="$4"

    log_step "=== SWITCHING ACCOUNT FOR $container ==="
    log_info "Account: $login @ $server"

    # Get terminal ID
    local terminal_id=""
    if [ -n "$TERMINAL_ID" ]; then
        terminal_id="$TERMINAL_ID"
    else
        terminal_id="D0E8209F77C8CF37AD8BF550E51FF075"
    fi

    local MT5_DATA="$MT5_DATA_BASE/$terminal_id"

    # Stop MT5
    log_info "[1/5] Stopping MT5..."
    docker exec "$container" pkill -9 -f terminal64.exe 2>/dev/null || true
    sleep 3
    log_success "MT5 stopped"
    echo ""

    # Update terminal.ini
    log_info "[2/5] Updating terminal.ini..."
    docker exec "$container" python3 -c "
import os

login = '''$login'''
password = '''$password'''
server = '''$server'''

content = '''[Common]
Login=%s
LastLogin=%s
Password=%s
PasswordInvestor=%s
Server=%s
ProfileLast=Default
AllowDllImport=1
AllowAlgoTrading=1

[Charts]
LeftChart=300,50,1920,1040
RightChart=300,50,1920,1040

[News]
Allow=0
AutoUpdate=1
Filter=
Language=en

[Trade]
AllowLiveTrading=1
ConfirmDiscretDeal=1
ConfirmClose=1
ConfirmModify=1
''' % (login, login, password, password, server)

os.makedirs('$MT5_DATA', exist_ok=True)
with open('$MT5_DATA/terminal.ini', 'w') as f:
    f.write(content)
print('terminal.ini updated')
"
    log_success "terminal.ini updated"
    echo ""

    # Update accounts.ini
    log_info "[3/5] Updating accounts.ini..."
    docker exec "$container" python3 -c "
import os

login = '''$login'''

content = '''[Accounts]
Count=1
Default=%s
''' % login

accounts_path = '$MT5_DATA/hdd.v2/accounts.ini'
os.makedirs(os.path.dirname(accounts_path), exist_ok=True)
with open(accounts_path, 'w') as f:
    f.write(content)
print('accounts.ini updated')
"
    log_success "accounts.ini updated"
    echo ""

    # Update connections.ini
    log_info "[4/5] Updating connections.ini..."
    docker exec "$container" python3 -c "
import os

login = '''$login'''
server = '''$server'''

content = '''[%s]
Server=%s
Login=%s
LastLogin=%s
''' % (login, server, login, login)

connections_path = '$MT5_DATA/hdd.v2/connections.ini'
os.makedirs(os.path.dirname(connections_path), exist_ok=True)
with open(connections_path, 'w') as f:
    f.write(content)
print('connections.ini updated')
"
    log_success "connections.ini updated"
    echo ""

    # Update startup.ini
    log_info "[5/5] Updating startup.ini and starting MT5..."
    docker exec "$container" python3 -c "
import os

login = '''$login'''
password = '''$password'''
server = '''$server'''

content = '''[Common]
Login=%s
Password=%s
Server=%s

[Charts]
ProfileLast=AutoBridge
''' % (login, password, server)

startup_path = '/config/startup.ini'
with open(startup_path, 'w') as f:
    f.write(content)

if not os.path.exists('/startup.ini'):
    os.symlink('/config/startup.ini', '/startup.ini')
print('startup.ini created')
"
    log_success "startup.ini updated"
    echo ""

    # Start MT5 with auto-login
    log_info "Starting MT5 with profile AutoBridge..."
    docker exec -d -u abc "$container" bash -c \
        "DISPLAY=:1 wine '$MT5_BASE/terminal64.exe' /config:startup.ini /profile:AutoBridge &" 2>/dev/null

    # Wait for MT5 to start
    for i in {1..30}; do
        if docker exec "$container" pgrep -f terminal64.exe >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    log_success "MT5 started with account $login @ $server"
}

# ============================================================================
# Get container URL
# ============================================================================
get_container_url() {
    local container="$1"

    local host_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo "localhost")
    local ports=$(docker ps --filter "name=$container" --format '{{.Ports}}')

    local port=""
    local port_entry=$(echo "$ports" | grep -oE '0\.0\.0\.0:[0-9]+->3000/tcp' 2>/dev/null | head -1)
    if [ -n "$port_entry" ]; then
        port=$(echo "$port_entry" | sed 's/0\.0\.0\.0://' | sed 's/->3000\/tcp//')
    fi

    if [ -n "$port" ]; then
        echo "http://$host_ip:$port"
    else
        echo "http://$host_ip:3000"
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   MT5 Deploy and Switch${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""

    parse_args "$@"

    if [ ! -f "$ACCOUNTS_CSV" ]; then
        log_error "Accounts CSV not found: $ACCOUNTS_CSV"
        exit 1
    fi

    resolve_defaults

    echo ""
    log_info "After resolve_defaults - testing echo"
    echo "[DEBUG] After resolve_defaults" >&2
    log_info "Reference Container: $REFERENCE_CONTAINER"
    log_info "Image: $IMAGE_TAG"
    log_info "Stagger delay: ${STAGGER}s"
    echo ""

    echo "[DEBUG] About to read CSV..." >&2
    log_info "About to read CSV..."
    log_info "Reading CSV file..."
    
    # Use simpler method that works reliably
    CSV_LINES=()
    while IFS=',' read -r inst login pass srv; do
        [ "$inst" = "instance_name" ] && continue
        [ -z "$inst" ] && continue
        # Remove any carriage returns
        inst=$(echo "$inst" | tr -d '\r')
        login=$(echo "$login" | tr -d '\r')
        pass=$(echo "$pass" | tr -d '\r')
        srv=$(echo "$srv" | tr -d '\r')
        CSV_LINES+=("$inst,$login,$pass,$srv")
    done < "$ACCOUNTS_CSV"
    
    local count=${#CSV_LINES[@]}
    log_info "Read $count lines from CSV"
    log_info "CSV lines: ${CSV_LINES[*]}"

    if [ "$count" -eq 0 ]; then
        log_error "No accounts found in CSV"
        log_error "CSV contents:"
        cat "$ACCOUNTS_CSV" >&2
        exit 1
    fi

    log_info "Found $count accounts to deploy"
    echo ""

    local deployed=0
    local instance_count=0

    for csv_row in "${CSV_LINES[@]}"; do
        # Parse CSV row
        instance_name=$(echo "$csv_row" | awk -F',' '{gsub(/"/, "", $1); print $1}')
        login=$(echo "$csv_row" | awk -F',' '{gsub(/"/, "", $2); print $2}')
        password=$(echo "$csv_row" | awk -F',' '{gsub(/"/, "", $3); print $3}')
        server=$(echo "$csv_row" | awk -F',' '{gsub(/"/, "", $4); print $4}')

        [ -z "$instance_name" ] && continue
        instance_count=$((instance_count + 1))

        CONTAINER="mt5_${instance_name}"
        log_info "Processing: $CONTAINER ($login @ $server)"

        # Phase 1: Deploy container
        if ! deploy_container "$instance_name" "$instance_count"; then
            log_error "Failed to deploy $CONTAINER"
            continue
        fi

        # Phase 2: Wait for MT5 to start
        wait_for_mt5 "$CONTAINER" 60

        # Phase 3: Switch to correct account
        if ! switch_account "$CONTAINER" "$login" "$password" "$server"; then
            log_error "Failed to switch account for $CONTAINER"
        fi

        # Show container URL
        local url=$(get_container_url "$CONTAINER")
        log_info "Access: $url"
        echo ""

        deployed=$((deployed + 1))

    done

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Deployment Complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo ""
    log_info "Deployed: $deployed containers"
    echo ""
    log_info "Containers:"
    docker ps --filter "name=mt5_" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
}

main "$@"
