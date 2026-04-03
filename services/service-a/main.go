package main

import (
	"io/ioutil"
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

	// ✅ MAIN API
	r.GET("/api", func(c *gin.Context) {
		resp, err := http.Get("http://service-b/api")

		var serviceBResponse string

		if err == nil {
			body, _ := ioutil.ReadAll(resp.Body)
			serviceBResponse = string(body)
			resp.Body.Close()
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

	// 🔥 FIX: ADD THIS BLOCK
	r.GET("/v2", func(c *gin.Context) {
		resp, err := http.Get("http://service-b/api")

		var serviceBResponse string

		if err == nil {
			body, _ := ioutil.ReadAll(resp.Body)
			serviceBResponse = string(body)
			resp.Body.Close()
		} else {
			serviceBResponse = "service-b not reachable"
		}

		c.JSON(200, gin.H{
			"message":   "Hello from Service A (v2 route)",
			"service":   "service-a",
			"version":   "v2",
			"service_b": serviceBResponse,
		})
	})

	// Health checks
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "healthy", "service": "service-a", "version": version})
	})

	r.GET("/version", func(c *gin.Context) {
		c.JSON(200, gin.H{"service": "service-a", "version": version})
	})

	r.Run(":8080")
}
