#!/bin/bash

# Set up hidden parent directory
VOCABOSAI_DIR="$HOME/.vocabos/ai"
PORT=6661
NODE_VERSION="18"

echo "🔍 Checking for necessary dependencies..."

# Ensure the hidden parent directory exists
if [ ! -d "$VOCABOSAI_DIR" ]; then
    echo "📂 Creating hidden parent directory at $VOCABOSAI_DIR..."
    mkdir -p "$VOCABOSAI_DIR"
fi

# Install Homebrew if not installed
if ! command -v brew &>/dev/null; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >/dev/null 2>&1
fi

# Install nvm if not installed
if [ ! -d "$HOME/.nvm" ]; then
    echo "📦 Installing nvm..."
    brew install nvm >/dev/null 2>&1
    mkdir -p "$HOME/.nvm"
    echo 'export NVM_DIR="$HOME/.nvm"' >> "$HOME/.zshrc"
    echo '[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"' >> "$HOME/.zshrc"
    source "$HOME/.zshrc"
fi

# Load nvm
export NVM_DIR="$HOME/.nvm"
source "/opt/homebrew/opt/nvm/nvm.sh"

# Install and use Node.js 18 with nvm
if ! nvm list | grep -q "v$NODE_VERSION"; then
    echo "📦 Installing Node.js v$NODE_VERSION using nvm..."
    nvm install $NODE_VERSION >/dev/null 2>&1
fi

nvm use $NODE_VERSION >/dev/null 2>&1
echo "✅ Using Node.js version: $(node -v)"

# Set up project folder
cd "$VOCABOSAI_DIR"

# Initialize a Node.js project if package.json doesn't exist
if [ ! -f "package.json" ]; then
    echo "📦 Initializing Node.js project..."
    npm init -y >/dev/null 2>&1
    # Set the project type to "module" for ES module support
    jq '. + {"type": "module"}' package.json > tmp.json && mv tmp.json package.json
fi

# Install required packages
echo "📦 Installing required Vocabosai libraries..."
npm install express @xenova/transformers >/dev/null 2>&1

# Create the API server script
SERVER_SCRIPT="$VOCABOSAI_DIR/server.js"

cat <<EOF > "$SERVER_SCRIPT"
import express from "express";
import { pipeline } from "@xenova/transformers";

const app = express();
app.use(express.json());

console.log("🚀 Loading Vocabosai model (GPT-2)...");
const generator = await pipeline("text-generation", "Xenova/gpt2");

app.post("/generate", async (req, res) => {
    const prompt = req.body.prompt;
    if (!prompt) {
        return res.status(400).json({ error: "No prompt provided" });
    }

    const response = await generator(prompt, { max_length: 150 });
    res.json({ response: response[0].generated_text });
});

app.listen($PORT, () => {
    console.log("🚀 Vocabosai API server running on port $PORT...");
});
EOF

echo "🚀 Starting Vocabosai API server on port $PORT..."
node "$SERVER_SCRIPT"