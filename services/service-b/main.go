package main

import (
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

	// Root route to return an API message
	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service": "service-b",
			"version": version,
			"message": "API-only backend. Use /api, /health, or /version.",
		})
	})

	// Main API endpoint — consumed by service-a via internal DNS
	r.GET("/api", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service":   "service-b",
			"version":   version,
			"message":   "Hello from Service B",
			"timestamp": time.Now().Format(time.RFC3339),
		})
	})

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"service": "service-b",
			"version": version,
		})
	})

	// Version info endpoint
	r.GET("/version", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"service": "service-b",
			"version": version,
		})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	r.Run(":" + port)
}
