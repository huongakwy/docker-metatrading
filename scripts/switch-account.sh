#!/bin/bash
# ============================================================================
# MT5 Account Switcher - Login to specific account from CSV
# Usage: ./switch-account.sh [container_name] [instance_name]
# Example: 
#   ./switch-account.sh          # Interactive: select container, then account
#   ./switch-account.sh mt5_04    # Switch container mt5_04, select account interactively
#   ./switch-account.sh mt5_04 04 # Switch mt5_04 to account 04
# 
# After login, MT5 will automatically load the "AutoBridge" profile
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CSV_FILE="$PROJECT_DIR/credentials.csv"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# MT5 paths inside container
MT5_BASE="/config/.wine/drive_c/Program Files/MetaTrader 5"
TERMINAL_ID="D0E8209F77C8CF37AD8BF550E51FF075"
MT5_DATA="/config/.wine/drive_c/users/abc/AppData/Roaming/MetaQuotes/Terminal/$TERMINAL_ID"

# List available MT5 containers
list_containers() {
    # Get host IP
    local host_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo "localhost")
    
    echo -e "${CYAN}Available MT5 containers:${NC}"
    echo ""
    
    # Get all running containers with mt5 in name
    local containers=$(docker ps --format '{{.Names}}' | grep -E '^mt5_' | sort)
    
    if [ -z "$containers" ]; then
        log_error "No MT5 containers found"
        exit 1
    fi
    
    local count=1
    local container_array=()
    
    while IFS= read -r container; do
        container_array+=("$container")
        
        # Get all ports for this container
        local ports=$(docker ps --filter "name=$container" --format '{{.Ports}}')
        
        # Extract port mapping for 3000 (VNC)
        local port=""
        local port_entry=$(echo "$ports" | grep -oE '0\.0\.0\.0:[0-9]+->3000/tcp' 2>/dev/null | head -1)
        if [ -n "$port_entry" ]; then
            port=$(echo "$port_entry" | sed 's/0\.0\.0\.0://' | sed 's/->3000\/tcp//')
        fi
        
        if [ -n "$port" ]; then
            echo -e "  ${GREEN}$count)${NC} $container  ${CYAN}(http://$host_ip:$port)${NC}"
        else
            echo -e "  ${GREEN}$count)${NC} $container  ${YELLOW}(no port mapped)${NC}"
        fi
        
        ((count++))
    done <<< "$containers"
    
    echo ""
    echo "$count) Cancel"
    echo ""
    
    # Return array for selection
    CONTAINERS_ARRAY="${container_array[@]}"
}

# Select container interactively
select_container() {
    list_containers
    
    echo -n "Select container (number): "
    read -r selection
    
    if [ "$selection" == "$count" ] || [ "$selection" == "cancel" ] || [ "$selection" == "c" ]; then
        echo "Cancelled."
        exit 0
    fi
    
    local idx=$((selection - 1))
    local container_array=($CONTAINERS_ARRAY)
    
    if [ "$selection" -lt 1 ] || [ "$selection" -gt ${#container_array[@]} ]; then
        log_error "Invalid selection"
        exit 1
    fi
    
    CONTAINER="${container_array[$idx]}"
    log_info "Selected container: $CONTAINER"
}

# List available accounts from CSV
list_accounts() {
    echo -e "${CYAN}Available accounts in credentials.csv:${NC}"
    echo ""
    
    local count=1
    local account_array=()
    
    # Skip header, read each account
    while IFS=',' read -r instance login password server; do
        if [ "$instance" != "instance_name" ]; then
            account_array+=("$instance")
            echo -e "  ${GREEN}$count)${NC} $instance  ${CYAN}($login @ $server)${NC}"
            ((count++))
        fi
    done < "$CSV_FILE"
    
    echo ""
    echo "$count) Cancel"
    echo ""
    
    ACCOUNTS_ARRAY="${account_array[@]}"
}

# Select account interactively
select_account() {
    list_accounts
    
    echo -n "Select account (number): "
    read -r selection
    
    if [ "$selection" == "$count" ] || [ "$selection" == "cancel" ] || [ "$selection" == "c" ]; then
        echo "Cancelled."
        exit 0
    fi
    
    local idx=$((selection - 1))
    local account_array=($ACCOUNTS_ARRAY)
    
    if [ "$selection" -lt 1 ] || [ "$selection" -gt ${#account_array[@]} ]; then
        log_error "Invalid selection"
        exit 1
    fi
    
    INSTANCE_NAME="${account_array[$idx]}"
    log_info "Selected account: $INSTANCE_NAME"
}

# Get account from CSV by instance_name
get_account_from_csv() {
    local instance_name="$1"
    
    # Read CSV header to get column indices
    local header=$(head -1 "$CSV_FILE")
    
    # Find column indices (1-based)
    local col_instance=$(echo "$header" | awk -F',' '{for(i=1;i<=NF;i++) if($i=="instance_name") print i}')
    local col_login=$(echo "$header" | awk -F',' '{for(i=1;i<=NF;i++) if($i=="mt5_login") print i}')
    local col_password=$(echo "$header" | awk -F',' '{for(i=1;i<=NF;i++) if($i=="mt5_password") print i}')
    local col_server=$(echo "$header" | awk -F',' '{for(i=1;i<=NF;i++) if($i=="mt5_server") print i}')
    
    # Find the row with matching instance_name
    local row=$(grep "^$instance_name," "$CSV_FILE" | head -1)
    
    if [ -z "$row" ]; then
        log_error "Account '$instance_name' not found in $CSV_FILE"
        return 1
    fi
    
    # Extract fields
    LOGIN=$(echo "$row" | awk -F',' -vcol="$col_login" '{print $col}')
    PASSWORD=$(echo "$row" | awk -F',' -vcol="$col_password" '{print $col}')
    SERVER=$(echo "$row" | awk -F',' -vcol="$col_server" '{print $col}')
    
    log_info "Found account: $instance_name"
    log_info "  Login: $LOGIN"
    log_info "  Server: $SERVER"
}

# Get host URL for container
get_container_url() {
    local container="$1"
    
    # Get host IP
    local host_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo "localhost")
    
    # Get all ports for this container
    local ports=$(docker ps --filter "name=$container" --format '{{.Ports}}')
    
    # Extract port mapping for 3000 (VNC)
    local port=""
    local port_entry=$(echo "$ports" | grep -oE '0\.0\.0\.0:[0-9]+->3000/tcp' 2>/dev/null | head -1)
    if [ -n "$port_entry" ]; then
        port=$(echo "$port_entry" | sed 's/0\.0\.0\.0://' | sed 's/->3000\/tcp//')
    fi
    
    if [ -z "$port" ]; then
        echo "http://$host_ip:3000"
    else
        echo "http://$host_ip:$port"
    fi
}

# Validate container exists
validate_container() {
    local container="$1"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log_error "Container '$container' not found or not running"
        echo ""
        list_containers
        exit 1
    fi
}

# Stop MT5
stop_mt5() {
    log_info "[1/6] Stopping MT5..."
    docker exec "$CONTAINER" pkill -9 -f terminal64.exe 2>/dev/null || true
    sleep 2
    log_success "MT5 stopped"
}

# Update terminal.ini with new credentials
update_terminal_ini() {
    log_info "[2/6] Updating terminal.ini..."
    
    docker exec "$CONTAINER" python3 -c "
import os

login = '''$LOGIN'''
password = '''$PASSWORD'''
server = '''$SERVER'''

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
LastDate=0
UpdateDate=0

[Mail]
Enabled=0

[Notifications]
Email=
SoundEnabled=1
SoundFile=
PopupEnabled=1
EnableMail=0
EnablePush=0

[Trade]
AllowLiveTrading=1
ConfirmDiscretDeal=1
ConfirmClose=1
ConfirmModify=1
''' % (login, login, password, password, server)

terminal_ini_path = '$MT5_DATA/terminal.ini'
os.makedirs(os.path.dirname(terminal_ini_path), exist_ok=True)
with open(terminal_ini_path, 'w') as f:
    f.write(content)
print('terminal.ini updated')
"
    log_success "terminal.ini updated"
}

# Update accounts.ini
update_accounts_ini() {
    log_info "[3/6] Updating accounts.ini..."
    
    docker exec "$CONTAINER" python3 -c "
import os
login = '''$LOGIN'''

content = '''[Accounts]
Count=1
Default=%s
''' % login

accounts_ini_path = '$MT5_DATA/hdd.v2/accounts.ini'
os.makedirs(os.path.dirname(accounts_ini_path), exist_ok=True)
with open(accounts_ini_path, 'w') as f:
    f.write(content)
print('accounts.ini updated')
"
    log_success "accounts.ini updated"
}

# Update connections.ini
update_connections_ini() {
    log_info "[4/6] Updating connections.ini..."
    
    docker exec "$CONTAINER" python3 -c "
import os
login = '''$LOGIN'''
server = '''$SERVER'''

content = '''[%s]
Server=%s
Login=%s
LastLogin=%s
''' % (login, server, login, login)

connections_ini_path = '$MT5_DATA/hdd.v2/connections.ini'
os.makedirs(os.path.dirname(connections_ini_path), exist_ok=True)
with open(connections_ini_path, 'w') as f:
    f.write(content)
print('connections.ini updated')
"
    log_success "connections.ini updated"
}

# Update startup.ini and create symlink
update_startup_ini() {
    log_info "[5/6] Updating startup.ini and creating symlink..."
    
    docker exec "$CONTAINER" python3 -c "
import os

login = '''$LOGIN'''
password = '''$PASSWORD'''
server = '''$SERVER'''

# Write startup.ini to /config (mapped to Wine Z:)
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

# Create symlink for Wine Z: drive access (Wine maps Z: to /)
if not os.path.exists('/startup.ini'):
    os.symlink('/config/startup.ini', '/startup.ini')

print('startup.ini created and symlinked')
"
    log_success "startup.ini updated and symlinked"
}

# Start MT5 with auto-login
start_mt5() {
    log_info "[6/6] Starting MT5 with profile AutoBridge..."
    
    # Launch MT5 with startup.ini for auto-login AND load AutoBridge profile
    docker exec -d -u abc "$CONTAINER" bash -c \
        "DISPLAY=:1 wine '$MT5_BASE/terminal64.exe' /config:startup.ini /profile:AutoBridge &" 2>/dev/null
    
    # Wait for MT5 to start
    for i in {1..30}; do
        if docker exec "$CONTAINER" pgrep -f terminal64.exe >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    log_success "MT5 started with profile AutoBridge"
}

# Main
main() {
    local arg_container="${1:-}"
    local arg_instance="${2:-}"
    
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   MT5 Account Switcher${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Check CSV file exists
    if [ ! -f "$CSV_FILE" ]; then
        log_error "CSV file not found: $CSV_FILE"
        exit 1
    fi
    
    # Select container
    if [ -n "$arg_container" ]; then
        CONTAINER="$arg_container"
        validate_container "$CONTAINER"
        log_info "Using container: $CONTAINER"
    else
        select_container
    fi
    
    echo ""
    
    # Select account
    if [ -n "$arg_instance" ]; then
        INSTANCE_NAME="$arg_instance"
        log_info "Using account: $INSTANCE_NAME"
    else
        select_account
    fi
    
    echo ""
    
    # Get account info from CSV
    get_account_from_csv "$INSTANCE_NAME"
    
    # Get container URL
    local container_url=$(get_container_url "$CONTAINER")
    
    echo ""
    
    # Stop MT5
    stop_mt5
    echo ""
    
    # Update credentials
    update_terminal_ini
    echo ""
    update_accounts_ini
    echo ""
    update_connections_ini
    echo ""
    update_startup_ini
    echo ""
    
    # Start MT5
    start_mt5
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Done!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Account: $LOGIN"
    echo "Server: $SERVER"
    echo "Container: $CONTAINER"
    echo "Access: $container_url"
    echo ""
}

main "$@"
