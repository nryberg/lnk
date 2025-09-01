.PHONY: help build run dev stop clean logs shell backup restore deploy deploy-files deploy-run status-remote logs-remote restart-remote tailscale-status

# Configuration for remote deployment
REMOTE_HOST ?= your-server.com
REMOTE_USER ?= lnkuser
REMOTE_DIR ?= ~/lnk

# Default target
help:
	@echo "🔗 Link Forwarder - Available Commands:"
	@echo ""
	@echo "Development:"
	@echo "  dev        - Run in development mode"
	@echo "  test       - Run tests"
	@echo ""
	@echo "Local Docker:"
	@echo "  build      - Build Docker image"
	@echo "  run        - Start with Docker Compose"
	@echo "  stop       - Stop Docker containers"
	@echo "  restart    - Restart Docker containers"
	@echo "  logs       - View logs"
	@echo "  shell      - Access container shell"
	@echo ""
	@echo "Remote Deployment:"
	@echo "  deploy     - Full deploy to remote server (files + run)"
	@echo "  deploy-files - Copy files to remote server"
	@echo "  deploy-run - Build and run on remote server"
	@echo "  status-remote - Check remote container status"
	@echo "  logs-remote - View remote logs"
	@echo "  restart-remote - Restart remote containers"
	@echo ""
	@echo "Tailscale:"
	@echo "  tailscale-status - Show Tailscale status"
	@echo ""
	@echo "Data Management:"
	@echo "  backup     - Backup data volume"
	@echo "  restore    - Restore data from backup"
	@echo "  clean      - Clean up containers and images"
	@echo ""
	@echo "Configuration:"
	@echo "  REMOTE_HOST=$(REMOTE_HOST)"
	@echo "  REMOTE_USER=$(REMOTE_USER)"
	@echo "  REMOTE_DIR=$(REMOTE_DIR)"
	@echo ""

# Development
dev:
	@echo "🚀 Starting development server..."
	PORT=8080 go run -tags server cmd/server/main.go -dev

test:
	@echo "🧪 Running tests..."
	go test ./...

# Docker operations
build:
	@echo "🏗️ Building Docker image..."
	COMPOSE_BAKE=true docker compose build

run:
	@echo "🚀 Starting Link Forwarder with Docker Compose..."
	COMPOSE_BAKE=true docker compose up -d
	@echo "✅ Started! Visit http://localhost:80"

stop:
	@echo "🛑 Stopping containers..."
	docker compose down

restart: stop run

logs:
	@echo "📋 Showing logs (Ctrl+C to exit)..."
	docker compose logs -f

shell:
	@echo "🐚 Accessing container shell..."
	docker compose exec lnk sh

# Data management
backup:
	@echo "💾 Creating backup..."
	@mkdir -p backups
	docker run --rm -v lnk_data:/data -v $(PWD)/backups:/backup alpine tar czf /backup/lnk-backup-$(shell date +%Y%m%d-%H%M%S).tar.gz -C /data .
	@echo "✅ Backup created in ./backups/"

restore:
	@echo "📂 Available backups:"
	@ls -la backups/lnk-backup-*.tar.gz 2>/dev/null || echo "No backups found"
	@echo ""
	@echo "To restore, run: docker run --rm -v lnk_data:/data -v \$$(PWD)/backups:/backup alpine tar xzf /backup/BACKUP_FILE.tar.gz -C /data"

# Cleanup
clean:
	@echo "🧹 Cleaning up..."
	docker compose down -v
	docker system prune -f
	@echo "✅ Cleanup complete"

# Remote deployment
deploy: deploy-files deploy-run
	@echo "🚀 Full deployment complete!"

deploy-files:
	@echo "📂 Copying files to remote server..."
	@echo "Creating remote directory..."
	@ssh $(REMOTE_USER)@$(REMOTE_HOST) "mkdir -p $(REMOTE_DIR)"
	@echo "Copying project files..."
	@rsync -avz --exclude='.git' --exclude='backups' --exclude='.crush' \
		--exclude='*.log' --exclude='node_modules' \
		./ $(REMOTE_USER)@$(REMOTE_HOST):$(REMOTE_DIR)/
	@echo "✅ Files deployed to $(REMOTE_USER)@$(REMOTE_HOST):$(REMOTE_DIR)"

deploy-run:
	@echo "🏗️ Building and running on remote server..."
	@ssh $(REMOTE_USER)@$(REMOTE_HOST) "cd $(REMOTE_DIR) && make stop && make run"
	@echo "✅ Application deployed and running!"
	@echo "Check status with: make status-remote"

status-remote:
	@echo "📊 Remote Container Status:"
	@ssh $(REMOTE_USER)@$(REMOTE_HOST) "cd $(REMOTE_DIR) && docker compose ps"

logs-remote:
	@echo "📋 Remote logs (Ctrl+C to exit)..."
	@ssh $(REMOTE_USER)@$(REMOTE_HOST) "cd $(REMOTE_DIR) && docker compose logs -f"

restart-remote:
	@echo "🔄 Restarting remote containers..."
	@ssh $(REMOTE_USER)@$(REMOTE_HOST) "cd $(REMOTE_DIR) && docker compose restart"

# Tailscale management
tailscale-status:
	@echo "🔗 Tailscale Status:"
	@docker compose exec -T lnk tailscale status 2>/dev/null || echo "Container not running or Tailscale not available"
	@echo ""
	@echo "🌐 Tailscale IP:"
	@docker compose exec -T lnk tailscale ip -4 2>/dev/null || echo "Container not running or Tailscale not available"

# Quick status check
status:
	@echo "📊 Local Container Status:"
	@docker compose ps
	@echo ""
	@echo "💾 Volume Info:"
	@docker volume ls | grep lnk || echo "No volumes found"
	@echo ""
	@make tailscale-status
