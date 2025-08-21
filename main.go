package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gorilla/mux"
	_ "github.com/mattn/go-sqlite3"
)

type LinkForwarder struct {
	db *sql.DB
}

type Link struct {
	Shortcode string `json:"shortcode"`
	URL       string `json:"url"`
}

type Response struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

func NewLinkForwarder() (*LinkForwarder, error) {
	// Ensure .crush directory exists
	if err := os.MkdirAll(".crush", 0755); err != nil {
		return nil, fmt.Errorf("failed to create .crush directory: %v", err)
	}

	dbPath := filepath.Join(".crush", "links.db")
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %v", err)
	}

	lf := &LinkForwarder{db: db}
	if err := lf.initDB(); err != nil {
		return nil, fmt.Errorf("failed to initialize database: %v", err)
	}

	return lf, nil
}

func (lf *LinkForwarder) initDB() error {
	query := `
	CREATE TABLE IF NOT EXISTS links (
		shortcode TEXT PRIMARY KEY,
		url TEXT NOT NULL,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);`

	_, err := lf.db.Exec(query)
	return err
}

func (lf *LinkForwarder) Close() error {
	return lf.db.Close()
}

func (lf *LinkForwarder) saveLink(shortcode, url string) error {
	// Ensure URL has protocol
	if !strings.HasPrefix(url, "http://") && !strings.HasPrefix(url, "https://") {
		url = "https://" + url
	}

	query := `INSERT OR REPLACE INTO links (shortcode, url) VALUES (?, ?)`
	_, err := lf.db.Exec(query, shortcode, url)
	return err
}

func (lf *LinkForwarder) getURL(shortcode string) (string, error) {
	var url string
	query := `SELECT url FROM links WHERE shortcode = ?`
	err := lf.db.QueryRow(query, shortcode).Scan(&url)
	if err == sql.ErrNoRows {
		return "", fmt.Errorf("shortcode not found")
	}
	return url, err
}

func (lf *LinkForwarder) getAllLinks() ([]Link, error) {
	query := `SELECT shortcode, url FROM links ORDER BY created_at DESC`
	rows, err := lf.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var links []Link
	for rows.Next() {
		var link Link
		if err := rows.Scan(&link.Shortcode, &link.URL); err != nil {
			return nil, err
		}
		links = append(links, link)
	}
	return links, nil
}

func (lf *LinkForwarder) deleteLink(shortcode string) error {
	query := `DELETE FROM links WHERE shortcode = ?`
	result, err := lf.db.Exec(query, shortcode)
	if err != nil {
		return err
	}

	affected, err := result.RowsAffected()
	if err != nil {
		return err
	}

	if affected == 0 {
		return fmt.Errorf("shortcode not found")
	}

	return nil
}

func (lf *LinkForwarder) handleForward(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	shortcode := vars["shortcode"]

	if shortcode == "" {
		http.Error(w, "Shortcode is required", http.StatusBadRequest)
		return
	}

	url, err := lf.getURL(shortcode)
	if err != nil {
		http.Error(w, "Link not found", http.StatusNotFound)
		return
	}

	log.Printf("Forwarding %s to %s", shortcode, url)
	http.Redirect(w, r, url, http.StatusFound)
}

func (lf *LinkForwarder) handleAPI(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	switch r.Method {
	case "GET":
		links, err := lf.getAllLinks()
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(Response{
				Success: false,
				Message: "Failed to retrieve links",
			})
			return
		}

		json.NewEncoder(w).Encode(Response{
			Success: true,
			Message: "Links retrieved successfully",
			Data:    links,
		})

	case "POST":
		var link Link
		if err := json.NewDecoder(r.Body).Decode(&link); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Success: false,
				Message: "Invalid JSON",
			})
			return
		}

		if link.Shortcode == "" || link.URL == "" {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Success: false,
				Message: "Shortcode and URL are required",
			})
			return
		}

		if err := lf.saveLink(link.Shortcode, link.URL); err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(Response{
				Success: false,
				Message: "Failed to save link",
			})
			return
		}

		json.NewEncoder(w).Encode(Response{
			Success: true,
			Message: "Link saved successfully",
			Data:    link,
		})

	case "DELETE":
		vars := mux.Vars(r)
		shortcode := vars["shortcode"]

		if shortcode == "" {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Success: false,
				Message: "Shortcode is required",
			})
			return
		}

		if err := lf.deleteLink(shortcode); err != nil {
			w.WriteHeader(http.StatusNotFound)
			json.NewEncoder(w).Encode(Response{
				Success: false,
				Message: err.Error(),
			})
			return
		}

		json.NewEncoder(w).Encode(Response{
			Success: true,
			Message: "Link deleted successfully",
		})

	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(Response{
			Success: false,
			Message: "Method not allowed",
		})
	}
}

func (lf *LinkForwarder) handleHome(w http.ResponseWriter, r *http.Request) {
	html := `
<!DOCTYPE html>
<html>
<head>
    <title>Link Forwarder</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .container { background: #f5f5f5; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        input, button { padding: 10px; margin: 5px; border: 1px solid #ddd; border-radius: 4px; }
        button { background: #007bff; color: white; cursor: pointer; }
        button:hover { background: #0056b3; }
        .link-item { background: white; padding: 15px; margin: 10px 0; border-radius: 4px; display: flex; justify-content: space-between; align-items: center; }
        .delete-btn { background: #dc3545; padding: 5px 10px; font-size: 12px; }
        .delete-btn:hover { background: #c82333; }
        .shortcode { font-weight: bold; color: #007bff; }
        .url { color: #666; }
    </style>
</head>
<body>
    <h1>🔗 Link Forwarder</h1>

    <div class="container">
        <h2>Add New Link</h2>
        <form id="addForm">
            <input type="text" id="shortcode" placeholder="Shortcode (e.g., google)" required>
            <input type="text" id="url" placeholder="URL (e.g., www.google.com)" required>
            <button type="submit">Add Link</button>
        </form>
    </div>

    <div class="container">
        <h2>Existing Links</h2>
        <div id="links"></div>
    </div>

    <script>
        function loadLinks() {
            fetch('/api/links')
                .then(response => response.json())
                .then(data => {
                    const linksDiv = document.getElementById('links');
                    if (data.success && data.data) {
                        linksDiv.innerHTML = data.data.map(link =>
                            '<div class="link-item">' +
                            '<div>' +
                            '<div class="shortcode">/' + link.shortcode + '</div>' +
                            '<div class="url">' + link.url + '</div>' +
                            '</div>' +
                            '<button class="delete-btn" onclick="deleteLink(\'' + link.shortcode + '\')">Delete</button>' +
                            '</div>'
                        ).join('');
                    } else {
                        linksDiv.innerHTML = '<p>No links found</p>';
                    }
                });
        }

        function deleteLink(shortcode) {
            if (confirm('Delete link: ' + shortcode + '?')) {
                fetch('/api/links/' + shortcode, { method: 'DELETE' })
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            loadLinks();
                        } else {
                            alert('Error: ' + data.message);
                        }
                    });
            }
        }

        document.getElementById('addForm').addEventListener('submit', function(e) {
            e.preventDefault();
            const shortcode = document.getElementById('shortcode').value;
            const url = document.getElementById('url').value;

            fetch('/api/links', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({shortcode, url})
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    document.getElementById('shortcode').value = '';
                    document.getElementById('url').value = '';
                    loadLinks();
                } else {
                    alert('Error: ' + data.message);
                }
            });
        });

        // Load links on page load
        loadLinks();
    </script>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html")
	w.Write([]byte(html))
}

func main() {
	lf, err := NewLinkForwarder()
	if err != nil {
		log.Fatal("Failed to initialize LinkForwarder:", err)
	}
	defer lf.Close()

	// Add some default links for testing
	lf.saveLink("google", "https://www.google.com")
	lf.saveLink("github", "https://github.com")

	r := mux.NewRouter()

	// Home page with management interface
	r.HandleFunc("/", lf.handleHome).Methods("GET")

	// API endpoints
	r.HandleFunc("/api/links", lf.handleAPI).Methods("GET", "POST")
	r.HandleFunc("/api/links/{shortcode}", lf.handleAPI).Methods("DELETE")

	// Forward shortcodes (this should be last to catch all other routes)
	r.HandleFunc("/{shortcode}", lf.handleForward).Methods("GET")

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Server starting on port %s", port)
	log.Printf("Visit http://localhost:%s to manage links", port)
	log.Printf("Example: http://localhost:%s/google will redirect to https://www.google.com", port)

	log.Fatal(http.ListenAndServe(":"+port, r))
}
