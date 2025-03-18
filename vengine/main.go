package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

const whisperDir = "$HOME/whisper.cpp"
const whisperBin = whisperDir + "/main"

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}
// Middleware for future access control
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Example: Implement token-based authentication later
		c.Next()
	}
}

// Check if Whisper.cpp is installed
func checkWhisperStatus(c *gin.Context) {
	if _, err := os.Stat(whisperBin); os.IsNotExist(err) {
		c.JSON(http.StatusInternalServerError, gin.H{"status": "Whisper is NOT installed"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "Whisper is installed"})
}

// Install model dynamically
func installModel(c *gin.Context) {
	model := c.Query("model")
	if model == "" {
		model = "medium" // Default model
	}

	modelPath := filepath.Join(whisperDir, "models", "ggml-"+model+".bin")
	if _, err := os.Stat(modelPath); err == nil {
		c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("Model %s is already installed", model)})
		return
	}

	cmd := exec.Command("bash", whisperDir+"/models/download-ggml-model.sh", model)
	err := cmd.Run()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to install model"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": fmt.Sprintf("Model %s installed", model)})
}

// Transcribe audio file
func transcribeAudio(c *gin.Context) {
	file, err := c.FormFile("audio")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Audio file required"})
		return
	}

	// Save the file
	dst := "/tmp/" + file.Filename
	c.SaveUploadedFile(file, dst)

	// Transcription command
	cmd := exec.Command(whisperBin, "--file", dst, "--model", "medium")
	out, err := cmd.Output()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Transcription failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"transcription": string(out)})
}

// Translate audio file
func translateAudio(c *gin.Context) {
	file, err := c.FormFile("audio")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Audio file required"})
		return
	}

	// Save the file
	dst := "/tmp/" + file.Filename
	c.SaveUploadedFile(file, dst)

	// Translation command
	cmd := exec.Command(whisperBin, "--file", dst, "--model", "medium", "--translate")
	out, err := cmd.Output()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Translation failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"translation": string(out)})
}

// WebSocket for live transcription
func streamAudio(c *gin.Context) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println("WebSocket upgrade failed:", err)
		return
	}
	defer conn.Close()

	for {
		_, audioData, err := conn.ReadMessage()
		if err != nil {
			log.Println("WebSocket error:", err)
			break
		}

		// Save temporary audio file
		audioPath := "/tmp/live_audio.wav"
		os.WriteFile(audioPath, audioData, 0644)

		// Run transcription
		cmd := exec.Command(whisperBin, "--file", audioPath, "--model", "medium")
		out, err := cmd.Output()
		if err != nil {
			conn.WriteMessage(websocket.TextMessage, []byte("Transcription failed"))
			continue
		}

		// Send transcription result
		conn.WriteMessage(websocket.TextMessage, out)
	}
}

func main() {
	router := gin.Default()
	router.Use(AuthMiddleware())

	router.GET("/status", checkWhisperStatus)
	router.GET("/install-model", installModel)
	router.POST("/transcribe", transcribeAudio)
	router.POST("/translate", translateAudio)
	router.GET("/stream", streamAudio)

	log.Println("Whisper API running on http://localhost:6660")
	router.Run(":6660")
}
