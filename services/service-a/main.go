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

	r := gin.Default()

	// Root endpoint — returns service identity and version
	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service":   "service-a",
			"version":   version,
			"message":   "Hello from Service A",
			"timestamp": time.Now().Format(time.RFC3339),
		})
	})

	// Calls service-b via K8s cluster DNS and returns its response
	r.GET("/call-b", func(c *gin.Context) {
		url := "http://service-b.mesh-demo.svc.cluster.local/api"
		client := &http.Client{Timeout: 10 * time.Second}

		resp, err := client.Get(url)
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

	// Health check endpoint (used by K8s liveness/readiness probes)
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"service": "service-a",
			"version": version,
		})
	})

	// Version info endpoint
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
