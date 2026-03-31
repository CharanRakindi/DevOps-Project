package main

import (
	"embed"
	"html/template"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

//go:embed templates/*.html
var templateFS embed.FS

func main() {
	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "v1"
	}

	r := gin.Default()

	// Parse embedded templates
	tmpl := template.Must(template.ParseFS(templateFS, "templates/*.html"))
	r.SetHTMLTemplate(tmpl)

	// Dashboard — serves the modern UI at root
	r.GET("/", func(c *gin.Context) {
		c.HTML(http.StatusOK, "dashboard.html", gin.H{
			"Version": version,
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
