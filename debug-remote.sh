#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Configuration - update these for your server
REMOTE_HOST="${REMOTE_HOST:-your-server.com}"
REMOTE_USER="${REMOTE_USER:-lnkuser}"
REMOTE_DIR="${REMOTE_DIR:-~/lnk}"

# Check if we can connect
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" "echo 'Connected'" &>/dev/null; then
    error "Cannot connect to $REMOTE_USER@$REMOTE_HOST"
    echo "Please ensure:"
    echo "1. SSH keys are set up"
    echo "2. REMOTE_HOST, REMOTE_USER are correct"
    echo "3. Server is accessible"
    exit 1
fi

log "🔍 Debugging remote database issues on $REMOTE_HOST"

# Function to run commands on remote server
remote_exec() {
    ssh "$REMOTE_USER@$REMOTE_HOST" "$1"
}

# Check container status
log "📊 Checking container status..."
remote_exec "cd $REMOTE_DIR && docker compose ps"

# Check if container is running
if ! remote_exec "cd $REMOTE_DIR && docker compose ps | grep -q Up"; then
    warning "Container is not running. Starting it..."
    remote_exec "cd $REMOTE_DIR && docker compose up -d"
    sleep 5
fi

# Check data directory permissions
log "📂 Checking data directory permissions..."
remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk ls -la /data/"

# Check what user the app is running as
log "👤 Checking app user..."
remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk id"

# Check process list
log "🔄 Checking running processes..."
remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk ps aux"

# Test database connectivity
log "💾 Testing database operations..."

# Try to read existing links
log "📖 Attempting to read existing links..."
if remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk curl -s http://localhost/api/links | jq ."; then
    success "Database read successful"
else
    warning "Database read failed or jq not available"
    remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk curl -s http://localhost/api/links"
fi

# Try to add a test link
log "➕ Attempting to add test link..."
TEST_RESULT=$(remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk curl -s -X POST -H 'Content-Type: application/json' -d '{\"shortcode\":\"debug-$(date +%s)\",\"url\":\"https://debug.example.com\"}' http://localhost/api/links")

echo "Response: $TEST_RESULT"

if echo "$TEST_RESULT" | grep -q '"success":true'; then
    success "Database write successful!"
else
    error "Database write failed!"

    # Additional debugging
    log "🔧 Running additional diagnostics..."

    # Check database file permissions in detail
    log "📋 Database file details:"
    remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk stat /data/links.db" || warning "Database file not found"

    # Check if database directory is writable
    log "✍️  Testing write permissions:"
    remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk touch /data/test-write && rm /data/test-write && echo 'Write test successful'" || warning "Cannot write to /data directory"

    # Check recent logs
    log "📋 Recent container logs:"
    remote_exec "cd $REMOTE_DIR && docker compose logs --tail=20 lnk"

    # Fix permissions
    log "🔧 Attempting to fix database permissions..."
    remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk chown -R appuser:appuser /data"

    # Try restarting the container
    log "🔄 Restarting container to reset database connections..."
    remote_exec "cd $REMOTE_DIR && docker compose restart"

    # Wait a bit
    sleep 5

    # Test again
    log "🔁 Testing again after restart..."
    TEST_RESULT2=$(remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk curl -s -X POST -H 'Content-Type: application/json' -d '{\"shortcode\":\"debug-after-restart-$(date +%s)\",\"url\":\"https://debug2.example.com\"}' http://localhost/api/links")

    echo "Response after restart: $TEST_RESULT2"

    if echo "$TEST_RESULT2" | grep -q '"success":true'; then
        success "Database write successful after restart!"
    else
        error "Database write still failing after restart"

        # Show final diagnostics
        log "🔍 Final diagnostics:"
        remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk ls -la /data/"
        remote_exec "cd $REMOTE_DIR && docker compose logs --tail=10 lnk"
    fi
fi

# Check Tailscale status
log "🔗 Checking Tailscale status..."
remote_exec "cd $REMOTE_DIR && docker compose exec -T lnk tailscale status" || warning "Tailscale not available"

# Show final status
log "📊 Final container status:"
remote_exec "cd $REMOTE_DIR && docker compose ps"

success "Debug complete!"

echo ""
echo "💡 If the database write is still failing, try:"
echo "   1. ./debug-remote.sh  # Run this script again"
echo "   2. ssh $REMOTE_USER@$REMOTE_HOST 'cd $REMOTE_DIR && docker compose down -v && docker compose up -d'  # Reset volumes"
echo "   3. Check if SELinux is blocking access: sestatus"
echo "   4. Check disk space: df -h"
