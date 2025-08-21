package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"os"
	"strings"
	"text/tabwriter"
)

const defaultServerURL = "http://localhost:8080"

type CLIResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

func main() {
	var (
		serverURL = flag.String("server", defaultServerURL, "Server URL")
		add       = flag.String("add", "", "Add a new link (format: shortcode,url)")
		list      = flag.Bool("list", false, "List all links")
		del       = flag.String("delete", "", "Delete a link by shortcode")
		help      = flag.Bool("help", false, "Show help")
	)
	flag.Parse()

	if *help {
		showHelp()
		return
	}

	if *add != "" {
		handleAdd(*serverURL, *add)
	} else if *list {
		handleList(*serverURL)
	} else if *del != "" {
		handleDelete(*serverURL, *del)
	} else {
		showHelp()
	}
}

func showHelp() {
	fmt.Println("Link Forwarder CLI")
	fmt.Println()
	fmt.Println("Usage:")
	fmt.Println("  go run cli.go -add shortcode,url    Add a new link")
	fmt.Println("  go run cli.go -list                 List all links")
	fmt.Println("  go run cli.go -delete shortcode     Delete a link")
	fmt.Println("  go run cli.go -help                 Show this help")
	fmt.Println()
	fmt.Println("Examples:")
	fmt.Println("  go run cli.go -add google,www.google.com")
	fmt.Println("  go run cli.go -add gh,github.com")
	fmt.Println("  go run cli.go -list")
	fmt.Println("  go run cli.go -delete google")
	fmt.Println()
	fmt.Println("Options:")
	fmt.Println("  -server string    Server URL (default: http://localhost:8080)")
}

func handleAdd(serverURL, addArg string) {
	parts := strings.Split(addArg, ",")
	if len(parts) != 2 {
		fmt.Println("Error: Invalid format. Use: shortcode,url")
		return
	}

	shortcode := strings.TrimSpace(parts[0])
	url := strings.TrimSpace(parts[1])

	if shortcode == "" || url == "" {
		fmt.Println("Error: Both shortcode and URL are required")
		return
	}

	payload := map[string]string{
		"shortcode": shortcode,
		"url":       url,
	}

	jsonData, err := json.Marshal(payload)
	if err != nil {
		fmt.Printf("Error: Failed to encode JSON: %v\n", err)
		return
	}

	resp, err := http.Post(serverURL+"/api/links", "application/json", strings.NewReader(string(jsonData)))
	if err != nil {
		fmt.Printf("Error: Failed to connect to server: %v\n", err)
		return
	}
	defer resp.Body.Close()

	var response CLIResponse
	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		fmt.Printf("Error: Failed to decode response: %v\n", err)
		return
	}

	if response.Success {
		fmt.Printf("✓ Link added: %s -> %s\n", shortcode, url)
	} else {
		fmt.Printf("Error: %s\n", response.Message)
	}
}

func handleList(serverURL string) {
	resp, err := http.Get(serverURL + "/api/links")
	if err != nil {
		fmt.Printf("Error: Failed to connect to server: %v\n", err)
		return
	}
	defer resp.Body.Close()

	var response CLIResponse
	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		fmt.Printf("Error: Failed to decode response: %v\n", err)
		return
	}

	if !response.Success {
		fmt.Printf("Error: %s\n", response.Message)
		return
	}

	data, ok := response.Data.([]interface{})
	if !ok || len(data) == 0 {
		fmt.Println("No links found")
		return
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
	fmt.Fprintln(w, "SHORTCODE\tURL")
	fmt.Fprintln(w, "---------\t---")

	for _, item := range data {
		link, ok := item.(map[string]interface{})
		if !ok {
			continue
		}

		shortcode := getString(link, "shortcode")
		url := getString(link, "url")

		fmt.Fprintf(w, "%s\t%s\n", shortcode, url)
	}

	w.Flush()
}

func handleDelete(serverURL, shortcode string) {
	if shortcode == "" {
		fmt.Println("Error: Shortcode is required")
		return
	}

	client := &http.Client{}
	req, err := http.NewRequest("DELETE", serverURL+"/api/links/"+shortcode, nil)
	if err != nil {
		fmt.Printf("Error: Failed to create request: %v\n", err)
		return
	}

	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("Error: Failed to connect to server: %v\n", err)
		return
	}
	defer resp.Body.Close()

	var response CLIResponse
	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		fmt.Printf("Error: Failed to decode response: %v\n", err)
		return
	}

	if response.Success {
		fmt.Printf("✓ Link deleted: %s\n", shortcode)
	} else {
		fmt.Printf("Error: %s\n", response.Message)
	}
}

func getString(m map[string]interface{}, key string) string {
	if val, ok := m[key]; ok {
		if str, ok := val.(string); ok {
			return str
		}
	}
	return ""
}
