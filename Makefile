.PHONY: help build run dev stop clean logs shell backup restore

# Default target
help:
	@echo "🔗 Link Forwarder - Available Commands:"
	@echo ""
	@echo "Development:"
	@echo "  dev        - Run in development mode"
	@echo "  test       - Run tests"
	@echo ""
	@echo "Docker:"
	@echo "  build      - Build Docker image"
	@echo "  run        - Start with Docker Compose"
	@echo "  stop       - Stop Docker containers"
	@echo "  restart    - Restart Docker containers"
	@echo "  logs       - View logs"
	@echo "  shell      - Access container shell"
	@echo ""
	@echo "Data Management:"
	@echo "  backup     - Backup data volume"
	@echo "  restore    - Restore data from backup"
	@echo "  clean      - Clean up containers and images"
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

# Quick status check
status:
	@echo "📊 Container Status:"
	@docker compose ps
	@echo ""
	@echo "💾 Volume Info:"
	@docker volume ls | grep lnk || echo "No volumes found"
