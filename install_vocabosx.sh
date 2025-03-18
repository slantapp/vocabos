#!/bin/bash

VOCABOS_DIR="$HOME/.vocabos/trans"
VOCABOS_BIN="$VOCABOS_DIR/main"
VOCABOS_ENGINE="$VOCABOS_DIR/VocabosEngine"
VOCABOS_SCRIPT="$VOCABOS_DIR/main.go"
CONTROL_SCRIPT="$VOCABOS_DIR/vocabos_server_control.sh"
GO_DIR="$VOCABOS_DIR/go"
GO_BIN="$GO_DIR/bin/go"
SERVER_PORT=6660
LOG_FILE="$VOCABOS_DIR/server.log"
WHISPER_MODEL="medium"
MODEL_PATH="$VOCABOS_DIR/models/ggml-$WHISPER_MODEL.bin"

echo "Checking system requirements..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install Go locally if not present
if [ ! -d "$GO_DIR" ]; then
    echo "Installing Go locally..."
    mkdir -p "$GO_DIR"
    curl -L https://go.dev/dl/go1.22.0.darwin-amd64.tar.gz | tar -C "$GO_DIR" --strip-components=1 -xzf -
fi

# Ensure Go is available
export PATH="$GO_DIR/bin:$PATH"

# Clone or update Whisper.cpp
if [ -d "$VOCABOS_DIR" ]; then
    read -p "Vocabos is already installed. Do you want to reinstall it? (y/n): " reinstall
    if [[ "$reinstall" == "y" ]]; then
        rm -rf "$VOCABOS_DIR"
    else
        echo "Skipping Whisper.cpp installation..."
    fi
fi

echo "Installing Vocabos..."
git clone https://github.com/ggerganov/whisper.cpp.git "$VOCABOS_DIR"
cd "$VOCABOS_DIR" || exit
make

# Download the "medium" model automatically
if [ ! -f "$MODEL_PATH" ]; then
    echo "Downloading Whisper 'medium' model..."
    bash ./models/download-ggml-model.sh "$WHISPER_MODEL"
else
    echo "Whisper 'medium' model already installed."
fi

# Set up Go project
echo "Initializing Go project..."
cd "$VOCABOS_DIR" || exit
"$GO_BIN" mod init vocabos
"$GO_BIN" get github.com/gin-gonic/gin
"$GO_BIN" get github.com/gorilla/websocket
"$GO_BIN" mod tidy

# Create Go API for VocabosEngine
echo "Setting up VocabosEngine..."
cat <<EOL > "$VOCABOS_SCRIPT"
package main

import (
    "fmt"
    "net/http"
    "github.com/gin-gonic/gin"
    "github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
    CheckOrigin: func(r *http.Request) bool { return true },
}

func handleWebSocket(c *gin.Context) {
    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        fmt.Println("Failed to set WebSocket upgrade:", err)
        return
    }
    defer conn.Close()

    for {
        _, msg, err := conn.ReadMessage()
        if err != nil {
            fmt.Println("Read error:", err)
            break
        }
        fmt.Println("Received:", string(msg))

        if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
            fmt.Println("Write error:", err)
            break
        }
    }
}

func main() {
    router := gin.Default()

    router.GET("/status", func(c *gin.Context) {
        c.JSON(http.StatusOK, gin.H{"status": "running"})
    })

    router.GET("/ws", handleWebSocket)

    router.Run(":6660")
}
EOL

# Build and start VocabosEngine
echo "Building VocabosEngine..."
"$GO_BIN" build -o VocabosEngine main.go

# Create control script
cat <<EOL > "$CONTROL_SCRIPT"
#!/bin/bash

VOCABOS_ENGINE="$VOCABOS_ENGINE"
LOG_FILE="$LOG_FILE"
SERVER_PORT=$SERVER_PORT

case "\$1" in
    stop)
        echo "Stopping VocabosEngine..."
        pkill -f VocabosEngine
        echo "VocabosEngine stopped."
        ;;
    start)
        echo "Starting VocabosEngine..."
        nohup "\$VOCABOS_ENGINE" > "\$LOG_FILE" 2>&1 &
        echo "VocabosEngine started on port \$SERVER_PORT"
        ;;
    restart)
        echo "Restarting VocabosEngine..."
        pkill -f VocabosEngine
        nohup "\$VOCABOS_ENGINE" > "\$LOG_FILE" 2>&1 &
        echo "VocabosEngine restarted on port \$SERVER_PORT"
        ;;
    status)
        if pgrep -f VocabosEngine > /dev/null; then
            echo "VocabosEngine is running."
        else
            echo "VocabosEngine is not running."
        fi
        ;;
    *)
        echo "Usage: vocabos {start|stop|restart|status}"
        exit 1
esac
EOL

# Move control script to /usr/local/bin for global access
echo "Making Vocabos accessible globally..."
sudo mv "$CONTROL_SCRIPT" /usr/local/bin/vocabos
sudo chmod +x /usr/local/bin/vocabos

# Ensure the server starts on boot
echo "Starting VocabosEngine..."
nohup "$VOCABOS_ENGINE" > "$LOG_FILE" 2>&1 &

echo "Installation complete. VocabosEngine is running!"
echo "You can now control Vocabos globally with:"
echo "  vocabos start | stop | restart | status"
echo "Check logs: tail -f $LOG_FILE"