#!/bin/bash
# create-credential-volume.sh - Create and manage per-account credential volumes
# Usage: ./create-credential-volume.sh <account_id> <login> <password> <server>
#
# This script creates a Docker volume for storing MT5 credentials separately from
# the base image. Credentials are NOT baked into images for security.
#
# Exit Codes:
#   0 - Success
#   1 - Invalid credentials
#   2 - Volume creation failed
#   3 - Credential file generation failed

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
VOLUME_PREFIX="${VOLUME_PREFIX:-mt5-creds}"
TERMINAL_ID="${TERMINAL_ID:-D0E8209F77C8CF37AD8BF550E51FF075}"

# Show usage
usage() {
    cat << EOF
Usage: $0 <account_id> <login> <password> <server>

Create a credential volume for MT5 auto-login.

Arguments:
  account_id  Unique account identifier (e.g., account01, 111222, acc_001)
  login      MT5 account login number
  password   MT5 account password
  server     MT5 broker server name (e.g., Exness-MT5Trial14)

Environment Variables:
  VOLUME_PREFIX   Volume name prefix (default: mt5-creds)
  TERMINAL_ID     Terminal ID hash (default: D0E8209F77C8CF37AD8BF550E51FF075)

Examples:
  $0 account01 111222 mypassword Exness-MT5Trial14
  VOLUME_PREFIX=my-creds $0 account01 111222 mypassword Exness-MT5Trial14

Note:
  Credentials are stored in a Docker volume, NOT in the container image.
  This provides security benefits:
  - Credentials are not exposed in image layers
  - Credentials can be updated without rebuilding the image
  - Easy credential rotation

EOF
    exit 0
}

# Validate arguments
validate_args() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        log_error "Missing required arguments"
        usage
    fi
    
    ACCOUNT_ID="$1"
    LOGIN="$2"
    PASSWORD="$3"
    SERVER="$4"
    
    # Validate login is numeric
    if ! [[ "$LOGIN" =~ ^[0-9]+$ ]]; then
        log_error "Login must be numeric: $LOGIN"
        exit 1
    fi
    
    # Basic validation
    if [ ${#LOGIN} -lt 5 ]; then
        log_warning "Login seems too short: $LOGIN"
    fi
    
    log_info "Account ID: $ACCOUNT_ID"
    log_info "Login: $LOGIN"
    log_info "Server: $SERVER"
}

# Generate terminal.ini content
generate_terminal_ini() {
    local login="$1"
    local password="$2"
    local server="$3"
    
    # Convert password to hex for storage (simple obfuscation)
    local password_hex
    password_hex=$(printf '%s' "$password" | xxd -p | tr -d '\n')
    
    cat << EOF
[Common]
Login=$login
LastLogin=$login
Password=$password
PasswordInvestor=$password
Server=$server
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
EOF
}

# Generate accounts.ini content
generate_accounts_ini() {
    local login="$1"
    
    cat << EOF
[Accounts]
Count=1
Default=$login
EOF
}

# Generate connections.ini content
generate_connections_ini() {
    local login="$1"
    local server="$2"
    
    cat << EOF
[$login]
Server=$server
Login=$login
LastLogin=$login
EOF
}

# Create credential volume
create_volume() {
    local volume_name="$VOLUME_PREFIX-$ACCOUNT_ID"
    
    log_info "Creating credential volume: $volume_name"
    
    # Check if volume already exists
    if docker volume ls --format '{{.Name}}' | grep -q "^${volume_name}$"; then
        log_warning "Volume '$volume_name' already exists"
        REPLY="y"
        docker volume rm "$volume_name" 2>/dev/null || true
    fi
    
    # Create volume
    if ! docker volume create "$volume_name" > /dev/null 2>&1; then
        log_error "Failed to create volume: $volume_name"
        exit 2
    fi
    
    log_success "Volume created: $volume_name"
}

# Populate credential volume
populate_volume() {
    local volume_name="$VOLUME_PREFIX-$ACCOUNT_ID"
    local mount_point="/tmp/mt5-creds-$$"
    
    log_info "Populating credential files..."
    
    # Create temp directory
    mkdir -p "$mount_point"
    
    # Flatten structure: credentials stored directly at volume root
    # (no Terminal/{TERMINAL_ID}/ prefix - terminal ID is in the base image)
    
    # Generate terminal.ini directly at root
    generate_terminal_ini "$LOGIN" "$PASSWORD" "$SERVER" > "$mount_point/terminal.ini"
    
    # Create hdd.v2 directory for accounts
    mkdir -p "$mount_point/hdd.v2"
    generate_accounts_ini "$LOGIN" > "$mount_point/hdd.v2/accounts.ini"
    generate_connections_ini "$LOGIN" "$SERVER" > "$mount_point/hdd.v2/connections.ini"
    
    # Generate startup.ini for auto-login (MT5 uses /config:startup.ini)
    cat << EOF > "$mount_point/startup.ini"
[Common]
Login=$LOGIN
Password=$PASSWORD
Server=$SERVER
EOF
    echo "Generated startup.ini for auto-login"
    
    # Copy files to volume using temporary container with proper permissions
    local container_name="mt5-creds-populator-$$"
    
    # Get the UID/GID that MT5 container runs as (abc user with UID 1000)
    local MT5_UID="${MT5_UID:-1000}"
    local MT5_GID="${MT5_GID:-1000}"
    
    # Use busybox which is more reliable for permission operations
    docker run --rm \
        -v "$volume_name":/data \
        -v "$mount_point":/source \
        busybox:1.36 \
        sh -c "
            cd /source
            # Create hdd.v2 directory
            mkdir -p /data/hdd.v2
            # Copy all files
            cp -rp ./* /data/
            # Fix ownership for MT5 user (abc:abc = UID 1000:GID 1000)
            chown -R $MT5_UID:$MT5_GID /data/
            # Fix permissions: 755 for directories, 644 for files
            find /data -type d -exec chmod 755 {} \;
            find /data -type f -exec chmod 644 {} \;
        " 2>/dev/null || {
        # Fallback: direct copy if docker-in-docker
        cp -rP "$mount_point"/* "/var/lib/docker/volumes/$volume_name/_data/" 2>/dev/null || true
        chmod -R 755 "/var/lib/docker/volumes/$volume_name/_data/" 2>/dev/null || true
    }
    
    # Cleanup
    rm -rf "$mount_point"
    
    # Verify files were created
    if docker run --rm \
        -v "$volume_name":/data \
        busybox:1.36 \
        sh -c "test -f /data/terminal.ini && test -f /data/hdd.v2/accounts.ini"; then
        log_success "Credential files created in volume with proper permissions"
    else
        log_error "Failed to create credential files in volume"
        exit 3
    fi
}

# Show volume info
show_volume_info() {
    local volume_name="$VOLUME_PREFIX-$ACCOUNT_ID"
    
    echo ""
    echo "=== Credential Volume Created ==="
    echo "  Volume Name: $volume_name"
    echo "  Account ID: $ACCOUNT_ID"
    echo "  Login: $LOGIN"
    echo "  Server: $SERVER"
    echo ""
    echo "Volume contents (flat structure):"
    echo "  /terminal.ini"
    echo "  /hdd.v2/accounts.ini"
    echo "  /hdd.v2/connections.ini"
    echo ""
    echo "To use this volume with a container:"
    echo "  docker run -v $volume_name:/config/credentials -e TERMINAL_ID=$TERMINAL_ID ..."
    echo ""
}

# Update existing volume credentials
update_credentials() {
    local volume_name="$VOLUME_PREFIX-$ACCOUNT_ID"
    
    log_info "Updating credentials in existing volume: $volume_name"
    
    # Check if volume exists
    if ! docker volume ls --format '{{.Name}}' | grep -q "^${volume_name}$"; then
        log_error "Volume '$volume_name' does not exist"
        log_info "Use '$0 create' to create a new volume"
        exit 2
    fi
    
    # Create temp directory (flattened structure)
    local mount_point="/tmp/mt5-creds-update-$$"
    mkdir -p "$mount_point/hdd.v2"
    
    # Generate new credential files
    generate_terminal_ini "$LOGIN" "$PASSWORD" "$SERVER" > "$mount_point/terminal.ini"
    generate_accounts_ini "$LOGIN" > "$mount_point/hdd.v2/accounts.ini"
    generate_connections_ini "$LOGIN" "$SERVER" > "$mount_point/hdd.v2/connections.ini"
    
    # Copy files to volume with proper permissions
    docker run --rm \
        -v "$volume_name":/data \
        -v "$mount_point":/source \
        busybox:1.36 \
        sh -c "
            cp -rp /source/* /data/
            chown -R 1000:1000 /data/
            find /data -type d -exec chmod 755 {} \;
            find /data -type f -exec chmod 644 {} \;
        "
    
    rm -rf "$mount_point"
    log_success "Credentials updated with proper permissions"
}

# Main execution
main() {
    local command="${1:-create}"
    
    if [ "$command" == "-h" ] || [ "$command" == "--help" ]; then
        usage
    fi
    
    if [ "$command" == "create" ]; then
        shift
        validate_args "$@"
        create_volume
        populate_volume
        show_volume_info
    elif [ "$command" == "update" ]; then
        shift
        validate_args "$@"
        update_credentials
    else
        log_error "Unknown command: $command"
        log_info "Available commands: create, update"
        exit 1
    fi
}

main "$@"
