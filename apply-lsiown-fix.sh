#!/bin/bash
# apply-lsiown-fix.sh - Apply lsiown fix and redeploy containers
# This script fixes the "lsiown: command not found" error that prevents MT5 from starting

set -e

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
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "=========================================="
echo "  Apply lsiown Fix"
echo "=========================================="
echo ""

# Step 1: Verify Dockerfile has the fix
log_step "Step 1: Verifying Dockerfile has lsiown fix..."
if grep -q "RUN printf.*lsiown" snapshot/Dockerfile; then
    log_success "lsiown fix found in Dockerfile"
else
    log_error "lsiown fix NOT found in Dockerfile"
    log_info "Please ensure snapshot/Dockerfile contains:"
    echo ""
    echo "RUN printf '#!/bin/sh\\nexec chown \"\$@\"\\n' > /usr/bin/lsiown \\"
    echo "    && chmod +x /usr/bin/lsiown"
    echo ""
    exit 1
fi

# Step 2: Rebuild image
log_step "Step 2: Rebuilding image mt5-local:working..."
echo ""
docker build -t mt5-local:working -f ./snapshot/Dockerfile ./snapshot
echo ""
log_success "Image rebuilt successfully"

# Step 3: Verify lsiown in image
log_step "Step 3: Verifying lsiown command in built image..."
if docker run --rm mt5-local:working test -x /usr/bin/lsiown; then
    log_success "lsiown command exists and is executable"
else
    log_error "lsiown command not found in image"
    exit 1
fi

# Step 4: Stop and remove existing containers
log_step "Step 4: Stopping existing containers..."
CONTAINERS=$(docker ps -a --format '{{.Names}}' | grep '^mt5_' || true)
if [ -n "$CONTAINERS" ]; then
    echo "$CONTAINERS" | while read -r container; do
        log_info "Removing container: $container"
        docker rm -f "$container" >/dev/null 2>&1 || true
    done
    log_success "Existing containers removed"
else
    log_info "No existing containers to remove"
fi

# Step 5: Redeploy containers
log_step "Step 5: Redeploying containers..."
echo ""

if [ ! -f "credentials.csv" ]; then
    log_warning "credentials.csv not found"
    log_info "Skipping redeployment"
    log_info "To manually deploy, run:"
    echo "  ./scripts/profile-snapshot-automation/profile-snapshot-orchestrator.sh deploy --accounts credentials.csv"
else
    ./scripts/profile-snapshot-automation/profile-snapshot-orchestrator.sh deploy \
        --accounts credentials.csv
fi

echo ""
log_step "Step 6: Waiting for containers to initialize (30s)..."
sleep 30

# Step 7: Verify containers
log_step "Step 7: Verifying container status..."
echo ""

CONTAINERS=$(docker ps --format '{{.Names}}' | grep '^mt5_' || true)
if [ -z "$CONTAINERS" ]; then
    log_warning "No running mt5 containers found"
    exit 0
fi

echo "$CONTAINERS" | while read -r container; do
    log_info "Checking $container..."
    
    # Check for lsiown error
    if docker logs "$container" 2>&1 | grep -q "lsiown: command not found"; then
        log_error "$container still has lsiown error"
        continue
    fi
    
    # Check for correct UID/GID
    if docker logs "$container" 2>&1 | grep -q "User UID:    1000"; then
        log_success "$container has correct UID (1000)"
    else
        log_warning "$container may have incorrect UID"
    fi
    
    # Check for MT5 process
    if docker exec "$container" pgrep -x terminal64.exe >/dev/null 2>&1; then
        log_success "$container - MT5 process is running"
    else
        log_warning "$container - MT5 process not detected yet (may still be starting)"
    fi
done

echo ""
echo "=========================================="
echo "  Fix Applied Successfully"
echo "=========================================="
echo ""
log_success "lsiown fix has been applied and containers redeployed"
log_info "Monitor container logs with: docker logs -f mt5_02"
log_info "Check MT5 process with: docker exec mt5_02 pgrep -af terminal64"
echo ""
log_info "For detailed verification, run:"
echo "  ./scripts/profile-snapshot-automation/profile-snapshot-orchestrator.sh verify --accounts credentials.csv"
echo ""
