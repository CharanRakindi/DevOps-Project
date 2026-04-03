package main

import (
	"io"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
)

func main() {
	version := os.Getenv("VERSION")
	if version == "" {
		version = "v1"
	}

	r := gin.Default()

	// /api — single API endpoint; Istio routes /v2 here via URI rewrite
	r.GET("/api", func(c *gin.Context) {
		resp, err := http.Get("http://service-b/api")

		var serviceBResponse string

		if err == nil {
			defer resp.Body.Close()
			body, _ := io.ReadAll(resp.Body)
			serviceBResponse = string(body)
		} else {
			serviceBResponse = "service-b not reachable"
		}

		c.JSON(200, gin.H{
			"message":   "Hello from Service A",
			"service":   "service-a",
			"version":   version,
			"service_b": serviceBResponse,
		})
	})

	// Health check for K8s probes
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":  "healthy",
			"service": "service-a",
			"version": version,
		})
	})

	// Version endpoint
	r.GET("/version", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"service": "service-a",
			"version": version,
		})
	})

	r.Run(":8080")
}
