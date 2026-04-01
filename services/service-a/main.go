package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

func main() {
	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "v1"
	}

	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	// ── Dashboard UI ─────────────────────────────────────────────────────
	// Serves static/index.html at root. All other static assets under /static/
	r.Static("/static", "./static")
	r.GET("/", func(c *gin.Context) {
		c.File("./static/index.html")
	})

	// ── API endpoint ─────────────────────────────────────────────────────
	r.GET("/api", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service":   "service-a",
			"version":   version,
			"message":   "Hello from Service A",
			"timestamp": time.Now().Format(time.RFC3339),
		})
	})

	// ── Service-to-service call ──────────────────────────────────────────
	httpClient := &http.Client{Timeout: 10 * time.Second}

	r.GET("/call-b", func(c *gin.Context) {
		url := "http://service-b.mesh-demo.svc.cluster.local/api"

		resp, err := httpClient.Get(url)
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"error":   fmt.Sprintf("failed to reach service-b: %v", err),
				"service": "service-a",
				"version": version,
			})
			return
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": "failed to read response from service-b",
			})
			return
		}

		c.Data(resp.StatusCode, "application/json", body)
	})

	// ── Health check (K8s probes) ────────────────────────────────────────
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"service": "service-a",
			"version": version,
		})
	})

	// ── Version info ─────────────────────────────────────────────────────
	r.GET("/version", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service": "service-a",
			"version": version,
		})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	r.Run(":" + port)
}
