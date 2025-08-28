# Deployment Guide

This guide covers how to deploy the Link Forwarder application with persistent data storage.

## Quick Start with Docker Compose (Recommended)

The easiest way to run the application with persistent data is using Docker Compose:

```bash
# Build and start the application
docker compose up -d

# View logs
docker compose logs -f

# Stop the application
docker compose down
```

This will:
- Build the Docker image
- Create a persistent volume for your data
- Run the application on port 8080
- Automatically restart if it crashes

Your link data will be stored in a Docker volume called `lnk_data` and will persist between container restarts and rebuilds.

## Manual Docker Deployment

### Build the Image

```bash
docker build -t lnk .
```

### Run with Persistent Volume

```bash
# Create a named volume for data persistence
docker volume create lnk_data

# Run the container with the volume mounted
docker run -d \
  --name lnk \
  -p 8080:8080 \
  -v lnk_data:/data \
  -e DATA_DIR=/data \
  lnk
```

### Run with Host Directory Mount

If you prefer to store data in a specific directory on your host:

```bash
# Create the data directory on your host
mkdir -p /path/to/your/data

# Run the container with host directory mounted
docker run -d \
  --name lnk \
  -p 8080:8080 \
  -v /path/to/your/data:/data \
  -e DATA_DIR=/data \
  lnk
```

## Tailscale Deployment

For deployment with Tailscale networking:

```bash
# Build the Tailscale image
docker build -f Dockerfile.tailscale.alpine-fix -t lnk-tailscale .

# Run with both Tailscale state and app data persistence
docker run -d \
  --name lnk-tailscale \
  -p 80:80 \
  -v lnk_data:/data \
  -v tailscale_state:/var/lib/tailscale \
  -e DATA_DIR=/data \
  -e TS_AUTHKEY=your_tailscale_auth_key \
  -e TS_HOSTNAME=myapp \
  lnk-tailscale
```

## Development Mode

For local development without Docker:

```bash
# Run directly with Go (data stored in .crush directory)
PORT=8080 go run -tags server cmd/server/main.go

# Or with explicit development flag
PORT=8080 go run -tags server cmd/server/main.go -dev
```

## Environment Variables

- `PORT`: Port to run the server on (default: 80, Docker default: 8080)
- `DATA_DIR`: Directory to store the SQLite database (default: `.crush`)
- `TS_AUTHKEY`: Tailscale authentication key (Tailscale deployments only)
- `TS_HOSTNAME`: Tailscale hostname (default: `myapp`)
- `TS_EXTRA_ARGS`: Additional Tailscale arguments

## Data Storage

The application stores data in an SQLite database file called `links.db` within the configured data directory:

- **Development**: `.crush/links.db` (relative to working directory)
- **Docker**: `/data/links.db` (inside container, mounted to volume/host directory)

## Backup and Restore

### Backup Data

```bash
# With Docker volumes
docker run --rm -v lnk_data:/data -v $(pwd):/backup alpine tar czf /backup/lnk-backup.tar.gz -C /data .

# With host directory
cp -r /path/to/your/data ./lnk-backup
```

### Restore Data

```bash
# With Docker volumes
docker run --rm -v lnk_data:/data -v $(pwd):/backup alpine tar xzf /backup/lnk-backup.tar.gz -C /data

# With host directory
cp -r ./lnk-backup/* /path/to/your/data/
```

## Upgrading

To upgrade to a new version:

```bash
# With Docker Compose
docker compose pull
docker compose up -d
```

# Manual Docker
docker pull your-registry/lnk:latest
docker stop lnk
docker rm lnk
# Run with same volume mount as before
docker run -d --name lnk -p 8080:8080 -v lnk_data:/data your-registry/lnk:latest
```
```

Your data will be preserved across upgrades as long as you use the same volume or host directory.

## Troubleshooting

### Check Data Directory

```bash
# List contents of data volume
docker run --rm -v lnk_data:/data alpine ls -la /data

# Check database file
docker run --rm -v lnk_data:/data alpine ls -la /data/links.db
```

### View Application Logs

```bash
# Docker Compose
docker compose logs -f

# Manual Docker
docker logs -f lnk
```

### Access Container Shell

```bash
# Docker Compose
docker compose exec lnk sh

# Manual Docker
docker exec -it lnk sh
```
