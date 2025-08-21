#!/bin/bash

# Link Forwarder Server Startup Script

set -e

echo "🔗 Link Forwarder Server"
echo "======================="

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "Error: Go is not installed. Please install Go first."
    exit 1
fi

# Initialize Go module if go.sum doesn't exist
if [ ! -f "go.sum" ]; then
    echo "📦 Installing dependencies..."
    go mod tidy
fi

# Set default port if not specified
PORT=${PORT:-8080}

echo "🚀 Starting server on port $PORT"
echo "📱 Management interface: http://localhost:$PORT"
echo "🔗 Example redirect: http://localhost:$PORT/google"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Run the server
export PORT=$PORT
go run main.go
