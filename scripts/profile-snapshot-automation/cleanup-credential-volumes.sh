#!/bin/bash
# cleanup-credential-volumes.sh - Manage credential volume lifecycle
# Usage: ./cleanup-credential-volumes.sh [--dry-run] [--keep-days N] [--prefix PREFIX]
#
# This script cleans up orphaned credential volumes that are no longer in use.
# It can show what would be deleted (dry-run) or actually delete volumes.
#
# Exit Codes:
#   0 - Success
#   1 - Error

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

# Default values
DRY_RUN="${DRY_RUN:-false}"
KEEP_DAYS="${KEEP_DAYS:-30}"
VOLUME_PREFIX="${VOLUME_PREFIX:-mt5-creds}"

# Show usage
usage() {
    cat << EOF
Usage: $0 [options]

Manage credential volume lifecycle.

Options:
  --dry-run     Show what would be deleted without actually deleting
  --keep-days N Keep volumes newer than N days (default: 30)
  --prefix P   Volume prefix to clean (default: mt5-creds)

Environment Variables:
  DRY_RUN       Set to 'true' for dry-run mode
  KEEP_DAYS     Days to keep volumes (default: 30)
  VOLUME_PREFIX Volume prefix (default: mt5-creds)

Examples:
  # Dry run - show what would be deleted
  $0 --dry-run

  # Delete volumes older than 30 days
  $0 --keep-days 30

  # Delete volumes older than 7 days
  $0 --keep-days 7

  # Use custom prefix
  $0 --prefix my-creds

EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --keep-days)
                KEEP_DAYS="$2"
                shift 2
                ;;
            --prefix)
                VOLUME_PREFIX="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                shift
                ;;
        esac
    done
}

# Get volume age in days
get_volume_age() {
    local volume_name="$1"
    local created_at
    created_at=$(docker volume inspect "$volume_name" --format '{{.CreatedAt}}' 2>/dev/null)
    
    if [ -z "$created_at" ]; then
        echo "-1"
        return
    fi
    
    # Convert to timestamp
    local created_timestamp
    created_timestamp=$(date -d "$created_at" +%s 2>/dev/null || echo "0")
    local now_timestamp
    now_timestamp=$(date +%s)
    
    # Calculate days
    local age_seconds=$((now_timestamp - created_timestamp))
    local age_days=$((age_seconds / 86400))
    
    echo "$age_days"
}

# List volumes to clean
list_volumes_to_clean() {
    local prefix="$1"
    local keep_days="$2"
    
    log_info "Scanning volumes with prefix: $prefix"
    log_info "Keeping volumes newer than: $keep_days days"
    echo ""
    
    local count=0
    local total_size=0
    local volumes_to_delete=()
    
    # Get all volumes matching prefix
    while IFS= read -r volume_name; do
        if [ -z "$volume_name" ]; then
            continue
        fi
        
        local age_days
        age_days=$(get_volume_age "$volume_name")
        
        if [ "$age_days" -ge "$keep_days" ] || [ "$age_days" -eq -1 ]; then
            # Get volume size
            local size
            size=$(docker volume inspect "$volume_name" --format '{{.Size}}' 2>/dev/null | grep -oE '[0-9.]+' | head -1 || echo "0")
            
            # Get mountpoint for more info
            local mountpoint
            mountpoint=$(docker volume inspect "$volume_name" --format '{{.Mountpoint}}' 2>/dev/null || echo "unknown")
            
            volumes_to_delete+=("$volume_name|$age_days|$size")
            count=$((count + 1))
            total_size=$(echo "$total_size + $size" | bc 2>/dev/null || echo "$total_size")
        fi
    done < <(docker volume ls --format '{{.Name}}' | grep "^${prefix}-" || true)
    
    # Print volumes to delete
    if [ $count -eq 0 ]; then
        log_info "No volumes found to clean"
        return 0
    fi
    
    echo "=========================================="
    echo "  Volumes to Clean ($count found)"
    echo "=========================================="
    echo ""
    printf "%-40s %10s %15s\n" "Volume Name" "Age (days)" "Size"
    echo "------------------------------------------------------------------------"
    
    for entry in "${volumes_to_delete[@]}"; do
        IFS='|' read -r vol age size <<< "$entry"
        local size_str
        size_str=$(docker volume inspect "$vol" --format '{{.Size}}' 2>/dev/null || echo "unknown")
        printf "%-40s %10s %15s\n" "$vol" "$age days" "$size_str"
    done
    
    echo ""
    echo "Total volumes: $count"
    echo ""
    
    # Dry run check
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN MODE - No volumes will be deleted"
        return 0
    fi
    
    # Confirm deletion
    echo ""
    read -p "Delete these $count volumes? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted"
        return 0
    fi
    
    # Delete volumes
    log_info "Deleting volumes..."
    local deleted=0
    local failed=0
    
    for entry in "${volumes_to_delete[@]}"; do
        IFS='|' read -r vol age size <<< "$entry"
        
        if docker volume rm "$vol" 2>/dev/null; then
            log_success "Deleted: $vol"
            deleted=$((deleted + 1))
        else
            log_error "Failed to delete: $vol (may be in use)"
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    echo "=========================================="
    echo "  Cleanup Complete"
    echo "=========================================="
    echo "  Deleted: $deleted"
    echo "  Failed: $failed"
    echo ""
}

# List all credential volumes
list_all_volumes() {
    local prefix="$1"
    
    log_info "All volumes with prefix: $prefix"
    echo ""
    
    local count=0
    while IFS= read -r volume_name; do
        if [ -z "$volume_name" ]; then
            continue
        fi
        
        local age_days
        age_days=$(get_volume_age "$volume_name")
        local size
        size=$(docker volume inspect "$volume_name" --format '{{.Size}}' 2>/dev/null || echo "unknown")
        
        printf "%-40s %10s %15s\n" "$volume_name" "$age_days days" "$size"
        count=$((count + 1))
    done < <(docker volume ls --format '{{.Name}}' | grep "^${prefix}-" || true)
    
    echo ""
    log_info "Total volumes: $count"
}

# Main
main() {
    parse_args "$@"
    
    echo ""
    echo "=========================================="
    echo "  Credential Volume Cleanup"
    echo "=========================================="
    echo ""
    
    log_info "Mode: $([ "$DRY_RUN" = "true" ] && echo "DRY RUN" || echo "LIVE")"
    log_info "Keep days: $KEEP_DAYS"
    log_info "Volume prefix: $VOLUME_PREFIX"
    echo ""
    
    list_volumes_to_clean "$VOLUME_PREFIX" "$KEEP_DAYS"
}

main "$@"
