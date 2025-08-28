//go:build server

package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
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
	// Get data directory from environment variable, default to .crush
	dataDir := os.Getenv("DATA_DIR")
	if dataDir == "" {
		dataDir = ".crush"
	}

	// Ensure data directory exists
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create data directory %s: %v", dataDir, err)
	}

	dbPath := filepath.Join(dataDir, "links.db")
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
		// Redirect to home page with shortcode and error message
		redirectURL := fmt.Sprintf("/?shortcode=%s&error=not_found", shortcode)
		log.Printf("Link not found for shortcode: %s, redirecting to home", shortcode)
		http.Redirect(w, r, redirectURL, http.StatusFound)
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

type TemplateData struct {
	Shortcode    string
	ErrorMessage string
}

func (lf *LinkForwarder) handleHome(w http.ResponseWriter, r *http.Request) {
	// Determine template path based on development mode
	templatePath := "templates/home.html"
	if isDevelopment() {
		templatePath = "cmd/server/templates/home.html"
	}

	tmpl, err := template.ParseFiles(templatePath)
	if err != nil {
		http.Error(w, "Failed to load template", http.StatusInternalServerError)
		log.Printf("Template error: %v (tried path: %s)", err, templatePath)
		return
	}

	// Get query parameters
	shortcode := r.URL.Query().Get("shortcode")
	errorType := r.URL.Query().Get("error")

	var errorMessage string
	if errorType == "not_found" {
		errorMessage = fmt.Sprintf("Link '/%s' doesn't exist yet. You can create it below!", shortcode)
	}

	data := TemplateData{
		Shortcode:    shortcode,
		ErrorMessage: errorMessage,
	}

	w.Header().Set("Content-Type", "text/html")
	if err := tmpl.Execute(w, data); err != nil {
		http.Error(w, "Failed to execute template", http.StatusInternalServerError)
		log.Printf("Template execution error: %v", err)
		return
	}
}

var devMode bool

func init() {
	flag.BoolVar(&devMode, "dev", false, "Enable development mode")
}

func isDevelopment() bool {
	// Check if explicitly set via flag
	if devMode {
		return true
	}

	// Auto-detect development mode by checking if we're running from source
	if _, err := os.Stat("cmd/server/templates/home.html"); err == nil {
		return true
	}

	return false
}

func main() {
	flag.Parse()
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
		port = "80"
	}

	log.Printf("Server starting on port %s", port)
	log.Printf("Visit http://localhost:%s to manage links", port)
	log.Printf("Example: http://localhost:%s/google will redirect to https://www.google.com", port)

	log.Fatal(http.ListenAndServe(":"+port, r))
}
