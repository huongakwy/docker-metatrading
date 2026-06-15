#!/bin/bash
# build-profile-base.sh - Build MT5 base image with parallel build support
# Usage: ./build-profile-base.sh <snapshot_dir> [image_tag]
#
# This script builds the MT5 base image with optimizations for parallel execution
# and scale to 100+ containers.
#
# Exit Codes:
#   0 - Build successful
#   1 - Snapshot validation failed
#   2 - Docker build failed
#   3 - Image push failed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
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
log_build() { echo -e "${CYAN}[BUILD]${NC} $1"; }

# Environment variables with defaults
BATCH_SIZE="${BATCH_SIZE:-4}"
DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-1}"
BUILD_JOBS="${BUILD_JOBS:-4}"
CACHE_FROM="${CACHE_FROM:-}"

# Show usage
usage() {
    cat << EOF
Usage: $0 <snapshot_dir> [image_tag]

Build MT5 base image with parallel build support.

Arguments:
  snapshot_dir  Path to snapshot directory
  image_tag    Image tag (default: mt5-base:latest)

Environment Variables:
  BATCH_SIZE      Number of parallel builds (default: 4)
  DOCKER_BUILDKIT Enable Docker BuildKit (default: 1)
  BUILD_JOBS      BuildKit parallel jobs (default: 4)
  CACHE_FROM      Cache from image (default: none)

Examples:
  $0 ./snapshot
  $0 ./snapshot mt5-base:v1.0
  BATCH_SIZE=8 BUILD_JOBS=8 $0 ./snapshot

Build Optimizations:
  - Docker BuildKit for parallel layer builds
  - Layer caching for better cache hit rate
  - Build cache optimization

EOF
    exit 0
}

# Check arguments
if [ -z "$1" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
fi

SNAPSHOT_DIR="$1"
IMAGE_TAG="${2:-mt5-base:latest}"

# Validate snapshot directory
validate_for_build() {
    log_info "Validating snapshot for build..."
    
    if [ ! -d "$SNAPSHOT_DIR" ]; then
        log_error "Snapshot directory not found: $SNAPSHOT_DIR"
        exit 1
    fi
    
    # Run validation script if available
    local validate_script="$SCRIPT_DIR/validate-snapshot.sh"
    if [ -f "$validate_script" ]; then
        if ! bash "$validate_script" "$SNAPSHOT_DIR"; then
            log_error "Snapshot validation failed"
            exit 1
        fi
    fi
    
    # Check for Dockerfile
    if [ ! -f "$SNAPSHOT_DIR/Dockerfile" ]; then
        log_info "Dockerfile not found, generating..."
        local gen_script="$SCRIPT_DIR/generate-base-dockerfile.sh"
        if [ -f "$gen_script" ]; then
            bash "$gen_script" "$SNAPSHOT_DIR"
        else
            log_error "Dockerfile not found and generator script not available"
            exit 1
        fi
    fi
    
    log_success "Snapshot validated for build"
}

# Build the image
build_image() {
    local snapshot_dir="$1"
    local image_tag="$2"
    local start_time=$(date +%s)
    
    log_build "Building Docker image: $image_tag"
    log_info "Snapshot: $snapshot_dir"
    log_info "BuildKit: $DOCKER_BUILDKIT"
    log_info "Parallel jobs: $BUILD_JOBS"
    echo ""
    
    # Build arguments
    local build_args=()
    
    # Enable BuildKit
    if [ "$DOCKER_BUILDKIT" = "1" ]; then
        export DOCKER_BUILDKIT=1
        build_args+=("--build-arg" "BUILDKIT_INLINE_CACHE=1")
        
        # Add cache-from if specified
        if [ -n "$CACHE_FROM" ]; then
            build_args+=("--cache-from" "$CACHE_FROM")
            log_info "Using cache from: $CACHE_FROM"
        fi
    fi
    
    # Build command
    local build_cmd="docker build"
    for arg in "${build_args[@]}"; do
        build_cmd="$build_cmd $arg"
    done
    
    # Add BuildKit options
    if [ "$DOCKER_BUILDKIT" = "1" ]; then
        # Add jobs for parallel layer building
        build_cmd="$build_cmd --build-arg BUILDKIT_CLI_ARGS=--jobs=$BUILD_JOBS"
    fi
    
    # Add tag and path
    build_cmd="$build_cmd -t $image_tag -f $snapshot_dir/Dockerfile $snapshot_dir"
    
    log_build "Command: $build_cmd"
    echo ""
    
    # Execute build
    if eval "$build_cmd"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_success "Build completed in ${duration}s"
        log_success "Image: $image_tag"
        
        # Print image info
        echo ""
        docker images "$image_tag" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
        
        return 0
    else
        log_error "Build failed"
        return 2
    fi
}

# Push image to registry (if specified)
push_image() {
    local image_tag="$1"
    local registry="${REGISTRY:-}"
    
    if [ -z "$registry" ]; then
        log_info "No registry specified, skipping push"
        return 0
    fi
    
    log_info "Pushing image to registry: $registry"
    
    if docker tag "$image_tag" "$registry/$image_tag" && \
       docker push "$registry/$image_tag"; then
        log_success "Image pushed to $registry"
    else
        log_error "Failed to push image"
        return 3
    fi
}

# Show build cache info
show_cache_info() {
    echo ""
    echo "=== Build Cache Info ==="
    if [ "$DOCKER_BUILDKIT" = "1" ]; then
        log_info "BuildKit enabled - layers are cached automatically"
        log_info "To prune cache: docker builder prune"
    else
        log_warning "BuildKit disabled - enable for faster builds"
        log_info "Run: export DOCKER_BUILDKIT=1"
    fi
    echo ""
}

# Main build
main() {
    echo ""
    echo "=========================================="
    echo "  MT5 Base Image Build"
    echo "=========================================="
    echo ""
    
    # Validate
    validate_for_build
    
    # Build
    build_image "$SNAPSHOT_DIR" "$IMAGE_TAG"
    local build_result=$?
    
    if [ $build_result -ne 0 ]; then
        exit $build_result
    fi
    
    # Push (optional)
    push_image "$IMAGE_TAG"
    
    # Show cache info
    show_cache_info
    
    echo ""
    echo "=== Build Complete ==="
    echo "  Image: $IMAGE_TAG"
    echo ""
    log_success "Run container with:"
    echo "  docker run -v mt5-creds-{account}:/config/credentials:ro -e TERMINAL_ID=... $IMAGE_TAG"
    echo ""
    log_info "Container startup flow:"
    echo "  1. /init (s6-overlay) starts X11/VNC/openbox"
    echo "  2. openbox calls /Metatrader/start.sh"
    echo "  3. start.sh copies base template and injects credentials"
    echo "  4. MT5 launches with auto-login"
}

main "$@"
