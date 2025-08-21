# 🔗 Link Forwarder (lnk)

A lightweight Go web server that forwards short URLs to their full destinations. Perfect for creating your own URL shortener service.

## Features

- 🚀 Fast HTTP redirects with 302 status codes
- 🎯 Simple shortcode-to-URL mapping
- 💾 SQLite database storage
- 🌐 Web-based management interface
- 🖥️ Command-line interface for automation
- 📊 List and manage all your links
- 🗑️ Delete links you no longer need

## Quick Start

### 1. Start the Server

```bash
./run.sh
```

Or manually:

```bash
go mod tidy
go run main.go
```

The server will start on port 8080 by default. You can change this with the `PORT` environment variable.

### 2. Access the Service

- **Management Interface**: http://localhost:8080
- **Example Redirect**: http://localhost:8080/google → https://www.google.com

## Usage Examples

### Web Interface

Navigate to http://localhost:8080 in your browser to:
- Add new shortcode → URL mappings
- View all existing links
- Delete unwanted links

### Command Line Interface

Add a new link:
```bash
go run cli.go -add github,github.com
```

List all links:
```bash
go run cli.go -list
```

Delete a link:
```bash
go run cli.go -delete github
```

### API Endpoints

The service provides a RESTful API:

- `GET /api/links` - List all links
- `POST /api/links` - Create a new link
- `DELETE /api/links/{shortcode}` - Delete a link

Example API usage:
```bash
# Add a new link
curl -X POST http://localhost:8080/api/links \
  -H "Content-Type: application/json" \
  -d '{"shortcode":"example","url":"example.com"}'

# Get all links
curl http://localhost:8080/api/links

# Delete a link
curl -X DELETE http://localhost:8080/api/links/example
```

## Configuration

### Environment Variables

- `PORT`: Server port (default: 8080)

### Database

The service uses SQLite and stores data in `.crush/links.db`. The database is created automatically on first run.

## Default Links

The server comes with two pre-configured links for demonstration:
- `/google` → https://www.google.com
- `/github` → https://github.com

## URL Format

When adding URLs, the service automatically adds `https://` if no protocol is specified:
- Input: `google.com` → Stored as: `https://google.com`
- Input: `http://example.com` → Stored as: `http://example.com`

## Development

### Project Structure

```
lnk/
├── main.go          # Main server application
├── cli.go           # Command-line interface
├── go.mod           # Go module definition
├── go.sum           # Go module dependencies
├── run.sh           # Startup script
├── README.md        # This file
└── .crush/          # Data directory
    └── links.db     # SQLite database
```

### Dependencies

- [gorilla/mux](https://github.com/gorilla/mux) - HTTP router
- [mattn/go-sqlite3](https://github.com/mattn/go-sqlite3) - SQLite driver

### Building

To build a standalone binary:

```bash
go build -o lnk main.go
./lnk
```

## Use Cases

- **Development**: Quick access to frequently used URLs
- **Team Sharing**: Share common links with consistent shortcodes
- **Local Development**: Replace external URL shorteners for local testing
- **Documentation**: Create memorable links for internal resources

## Contributing

Feel free to submit issues and pull requests to improve the service.

## License

This project is open source and available under the MIT License.