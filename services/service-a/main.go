package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	version := os.Getenv("VERSION")
	if version == "" {
		version = "v1"
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Reuse a single HTTP client for connection pooling
	httpClient := &http.Client{Timeout: 10 * time.Second}

	mux := http.NewServeMux()

	// ── API routes registered BEFORE the static handler ──────────────────

	mux.HandleFunc("/api", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		loc, _ := time.LoadLocation("Asia/Kolkata")
		timestamp := time.Now().In(loc).Format(time.RFC3339)
		json.NewEncoder(w).Encode(map[string]string{
			"service":   "service-a",
			"version":   version,
			"message":   "Hello from Service A",
			"timestamp": timestamp,
		})
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "healthy",
			"service": "service-a",
			"version": version,
		})
	})

	mux.HandleFunc("/version", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"service": "service-a",
			"version": version,
		})
	})

	mux.HandleFunc("/call-b", func(w http.ResponseWriter, r *http.Request) {
		url := "http://service-b.mesh-demo.svc.cluster.local/api"

		resp, err := httpClient.Get(url)
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(map[string]string{
				"error":   fmt.Sprintf("failed to reach service-b: %v", err),
				"service": "service-a",
				"version": version,
			})
			return
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(map[string]string{
				"error": "failed to read response from service-b",
			})
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(resp.StatusCode)
		w.Write(body)
	})

	// ── Root route ────────────────────────────────────────────────────────
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"service": "service-a",
			"version": version,
			"message": "API-only backend. Use /api, /health, /version, or /call-b.",
		})
	})

	log.Printf("service-a %s listening on :%s", version, port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}
