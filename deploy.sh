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
    exit 1
}

# Load configuration
CONFIG_FILE="deploy.env"
if [[ -f "$CONFIG_FILE" ]]; then
    log "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
else
    error "Configuration file $CONFIG_FILE not found. Please create it from deploy.env"
fi

# Validate required variables
required_vars=("REMOTE_HOST" "REMOTE_USER" "REMOTE_DIR" "TS_AUTHKEY")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        error "Required variable $var is not set in $CONFIG_FILE"
    fi
done

# Command line argument handling
COMMAND="${1:-help}"

show_help() {
    echo "🚀 Link Forwarder Deployment Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  deploy     - Full deployment (files + run)"
    echo "  files      - Deploy files only"
    echo "  run        - Build and run on remote (requires files)"
    echo "  status     - Check remote status"
    echo "  logs       - View remote logs"
    echo "  restart    - Restart remote containers"
    echo "  backup     - Create remote backup"
    echo "  tailscale  - Check Tailscale status"
    echo "  stop       - Stop remote containers"
    echo "  clean      - Clean up remote containers and images"
    echo "  help       - Show this help"
    echo ""
    echo "Configuration:"
    echo "  Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR"
    echo "  App Port: ${APP_PORT:-80}"
    echo "  Tailscale: ${TS_HOSTNAME:-lnk-server}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if ssh is available
    if ! command -v ssh &> /dev/null; then
        error "ssh command not found. Please install OpenSSH client."
    fi

    # Check if rsync is available
    if ! command -v rsync &> /dev/null; then
        error "rsync command not found. Please install rsync."
    fi

    # Test SSH connection
    log "Testing SSH connection to $REMOTE_USER@$REMOTE_HOST..."
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection successful'" &>/dev/null; then
        error "Cannot connect to $REMOTE_USER@$REMOTE_HOST. Please check your SSH configuration."
    fi

    success "Prerequisites check passed"
}

# Deploy files to remote server
deploy_files() {
    log "Deploying files to remote server..."

    # Create remote directory
    ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_DIR"

    # Create .env file on remote with current configuration
    log "Creating .env file on remote server..."
    cat > /tmp/remote.env << EOF
# Tailscale Configuration
TS_AUTHKEY=$TS_AUTHKEY
TS_HOSTNAME=${TS_HOSTNAME:-lnk-server}
TS_EXTRA_ARGS=${TS_EXTRA_ARGS:---ssh --accept-dns=false}
TS_TUN_MODE=${TS_TUN_MODE:-userspace-networking}

# Application Configuration
APP_PORT=${APP_PORT:-80}
DATA_DIR=/data

# Environment
ENVIRONMENT=${ENVIRONMENT:-production}
EOF

    scp /tmp/remote.env "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/.env"
    rm /tmp/remote.env

    # Sync project files
    log "Syncing project files..."
    rsync -avz --delete \
        --exclude='.git' \
        --exclude='backups' \
        --exclude='.crush' \
        --exclude='*.log' \
        --exclude='node_modules' \
        --exclude='deploy.env' \
        --exclude='.env' \
        ./ "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"

    success "Files deployed successfully"
}

# Build and run on remote server
deploy_run() {
    log "Building and running on remote server..."

    ssh "$REMOTE_USER@$REMOTE_HOST" << EOF
        cd $REMOTE_DIR
        echo "🛑 Stopping existing containers..."
        docker compose down 2>/dev/null || true

        echo "🏗️ Building application..."
        COMPOSE_BAKE=true docker compose build

        echo "🚀 Starting application..."
        COMPOSE_BAKE=true docker compose up -d

        echo "⏳ Waiting for application to start..."
        sleep 5

        echo "📊 Container status:"
        docker compose ps
EOF

    success "Application deployed and running"
}

# Check status
check_status() {
    log "Checking remote application status..."

    ssh "$REMOTE_USER@$REMOTE_HOST" << EOF
        cd $REMOTE_DIR
        echo "📊 Container Status:"
        docker compose ps
        echo ""
        echo "🔗 Tailscale Status:"
        docker compose exec -T lnk tailscale status 2>/dev/null || echo "Tailscale not available"
        echo ""
        echo "🌐 Tailscale IP:"
        docker compose exec -T lnk tailscale ip -4 2>/dev/null || echo "Tailscale not available"
EOF
}

# View logs
view_logs() {
    log "Viewing remote logs (Press Ctrl+C to exit)..."
    ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && docker compose logs -f"
}

# Restart containers
restart_containers() {
    log "Restarting remote containers..."

    ssh "$REMOTE_USER@$REMOTE_HOST" << EOF
        cd $REMOTE_DIR
        docker compose restart
        sleep 3
        docker compose ps
EOF

    success "Containers restarted"
}

# Create backup
create_backup() {
    log "Creating remote backup..."

    ssh "$REMOTE_USER@$REMOTE_HOST" << EOF
        cd $REMOTE_DIR
        mkdir -p backups
        docker run --rm -v lnk_data:/data -v \$(pwd)/backups:/backup alpine \
            tar czf /backup/lnk-backup-\$(date +%Y%m%d-%H%M%S).tar.gz -C /data .
        echo "📂 Available backups:"
        ls -la backups/lnk-backup-*.tar.gz 2>/dev/null || echo "No backups found"
EOF

    success "Backup created"
}

# Check Tailscale status
check_tailscale() {
    log "Checking Tailscale status..."

    ssh "$REMOTE_USER@$REMOTE_HOST" << EOF
        cd $REMOTE_DIR
        echo "🔗 Tailscale Status:"
        docker compose exec -T lnk tailscale status 2>/dev/null || echo "Container not running or Tailscale not available"
        echo ""
        echo "🌐 Tailscale IP:"
        docker compose exec -T lnk tailscale ip -4 2>/dev/null || echo "Container not running or Tailscale not available"
        echo ""
        echo "📋 Recent Tailscale logs:"
        docker compose logs --tail=10 lnk 2>/dev/null | grep -i tailscale || echo "No Tailscale logs found"
EOF
}

# Stop containers
stop_containers() {
    log "Stopping remote containers..."

    ssh "$REMOTE_USER@$REMOTE_HOST" << EOF
        cd $REMOTE_DIR
        docker compose down
        echo "Containers stopped"
EOF

    success "Containers stopped"
}

# Clean up
clean_remote() {
    log "Cleaning up remote containers and images..."

    ssh "$REMOTE_USER@$REMOTE_HOST" << EOF
        cd $REMOTE_DIR
        docker compose down -v
        docker system prune -f
        echo "Cleanup completed"
EOF

    success "Remote cleanup completed"
}

# Main command handler
case "$COMMAND" in
    "deploy")
        check_prerequisites
        deploy_files
        deploy_run
        check_status
        success "Full deployment completed! 🎉"
        ;;
    "files")
        check_prerequisites
        deploy_files
        ;;
    "run")
        deploy_run
        check_status
        ;;
    "status")
        check_status
        ;;
    "logs")
        view_logs
        ;;
    "restart")
        restart_containers
        ;;
    "backup")
        create_backup
        ;;
    "tailscale")
        check_tailscale
        ;;
    "stop")
        stop_containers
        ;;
    "clean")
        clean_remote
        ;;
    "help")
        show_help
        ;;
    *)
        warning "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac
