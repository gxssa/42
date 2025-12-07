#!/bin/bash
animate_text "Welcome to Fortytwo CPU Node Setup!"

# Check for curl
if ! command -v curl &> /dev/null; then
    animate_text "Installing curl..."
    sudo apt update && sudo apt install -y curl
fi

# ─────────────────────────────────────────────────────────────
# Set directories
# ─────────────────────────────────────────────────────────────
PROJECT_DIR="$HOME/FortytwoNode"
PROJECT_DEBUG_DIR="$PROJECT_DIR/debug"
PROJECT_MODEL_CACHE_DIR="$PROJECT_DIR/model_cache"
CAPSULE_EXEC="$PROJECT_DIR/FortytwoCapsule"
PROTOCOL_EXEC="$PROJECT_DIR/FortytwoProtocol"
UTILS_EXEC="$PROJECT_DIR/FortytwoUtils"
ACCOUNT_PRIVATE_KEY_FILE="$PROJECT_DIR/.account_private_key"

mkdir -p "$PROJECT_DEBUG_DIR" "$PROJECT_MODEL_CACHE_DIR"

# ─────────────────────────────────────────────────────────────
# Download Fortytwo Utilities
# ─────────────────────────────────────────────────────────────
UTILS_VERSION=$(curl -s "https://fortytwo-network-public.s3.us-east-2.amazonaws.com/utilities/latest" | tr -d '\r' | xargs)
UTILS_URL="https://fortytwo-network-public.s3.us-east-2.amazonaws.com/utilities/v$UTILS_VERSION/FortytwoUtilsLinux"
curl -L -o "$UTILS_EXEC" "$UTILS_URL"
if [[ $? -ne 0 || ! -s "$UTILS_EXEC" ]]; then
    echo "ERROR: Failed to download Fortytwo Utils from: $UTILS_URL"
    echo "curl exit: $?; file exists: $( [[ -s \"$UTILS_EXEC\" ]] && echo yes || echo no )"
    exit 1
fi
chmod +x "$UTILS_EXEC"

# ─────────────────────────────────────────────────────────────
# Identity Setup
# ─────────────────────────────────────────────────────────────
if [[ -f "$ACCOUNT_PRIVATE_KEY_FILE" ]]; then
    ACCOUNT_PRIVATE_KEY=$(cat "$ACCOUNT_PRIVATE_KEY_FILE")
    animate_text "✓ Private key loaded. Continuing setup..."
else
    echo -e "\nChoose identity method:"
    echo "[1] Create new identity with activation code"
    echo "[2] Recover existing identity with seed phrase"
    read -rp "Select option [1-2]: " IDENTITY_OPTION

    if [[ "$IDENTITY_OPTION" == "2" ]]; then
        while true; do
            read -rp "Enter your recovery phrase: " ACCOUNT_SEED_PHRASE
            ACCOUNT_PRIVATE_KEY=$("$UTILS_EXEC" --phrase "$ACCOUNT_SEED_PHRASE")
            if [[ "$ACCOUNT_PRIVATE_KEY" == 0x* ]]; then
                echo "$ACCOUNT_PRIVATE_KEY" > "$ACCOUNT_PRIVATE_KEY_FILE"
                animate_text "✓ Private key recovered and saved."
                break
            else
                echo "Invalid phrase. Try again."
            fi
        done
    else
        "$UTILS_EXEC" --check-drop-service || exit 1
        read -rp "Enter activation code: " INVITE_CODE
        "$UTILS_EXEC" --create-wallet "$ACCOUNT_PRIVATE_KEY_FILE" --drop-code "$INVITE_CODE"
        ACCOUNT_PRIVATE_KEY=$(<"$ACCOUNT_PRIVATE_KEY_FILE")
        animate_text "✓ New identity created."
    fi
fi

# ─────────────────────────────────────────────────────────────
# Model Selection
# ─────────────────────────────────────────────────────────────
echo ""
echo "Choose model to run on this CPU node:"
echo "  [1] VibeThinker 1.5B Q4 (≈1.1 GB RAM)"
echo "  [2] Qwen3‑1.7B – smarter model (≈1.7 GB RAM)"
read -rp "Select model [1-2] (default 1): " MODEL_OPTION
MODEL_OPTION=${MODEL_OPTION:-1}

if [[ "$MODEL_OPTION" == "2" ]]; then
    LLM_HF_REPO="unsloth/Qwen3-1.7B-GGUF"
    LLM_HF_MODEL_NAME="Qwen3-1.7B-Q4_K_M.gguf"
    NODE_NAME="Qwen 3 1.7B Q4"
else
    LLM_HF_REPO="mradermacher/VibeThinker-1.5B-GGUF"
    LLM_HF_MODEL_NAME="VibeThinker-1.5B.Q4_K_M.gguf"
    NODE_NAME="VibeThinker 1.5B Q4"
fi

animate_text "Selected model: $NODE_NAME"
animate_text "Fetching model (this may take a few minutes)..."

"$UTILS_EXEC" --hf-repo "$LLM_HF_REPO" --hf-model-name "$LLM_HF_MODEL_NAME" --model-cache "$PROJECT_MODEL_CACHE_DIR"

# ─────────────────────────────────────────────────────────────
# Download Capsule & Protocol binaries
# ─────────────────────────────────────────────────────────────
CAPSULE_VERSION=$(curl -s "https://fortytwo-network-public.s3.us-east-2.amazonaws.com/capsule/latest" | tr -d '\r' | xargs)
CAPSULE_URL="https://fortytwo-network-public.s3.us-east-2.amazonaws.com/capsule/v$CAPSULE_VERSION/FortytwoCapsule-linux-amd64"
curl -L -o "$CAPSULE_EXEC" "$CAPSULE_URL"
if [[ $? -ne 0 || ! -s "$CAPSULE_EXEC" ]]; then
    echo "ERROR: Failed to download Capsule from: $CAPSULE_URL"
    echo "curl exit: $?; file exists: $( [[ -s \"$CAPSULE_EXEC\" ]] && echo yes || echo no )"
    exit 1
fi
chmod +x "$CAPSULE_EXEC"

PROTOCOL_VERSION=$(curl -s "https://fortytwo-network-public.s3.us-east-2.amazonaws.com/protocol/latest" | tr -d '\r' | xargs)
PROTOCOL_URL="https://fortytwo-network-public.s3.us-east-2.amazonaws.com/protocol/v$PROTOCOL_VERSION/FortytwoProtocolNode-linux-amd64"
curl -L -o "$PROTOCOL_EXEC" "$PROTOCOL_URL"
if [[ $? -ne 0 || ! -s "$PROTOCOL_EXEC" ]]; then
    echo "ERROR: Failed to download Protocol from: $PROTOCOL_URL"
    echo "curl exit: $?; file exists: $( [[ -s \"$PROTOCOL_EXEC\" ]] && echo yes || echo no )"
    exit 1
fi
chmod +x "$PROTOCOL_EXEC"

# ─────────────────────────────────────────────────────────────
# Launch Capsule
# ─────────────────────────────────────────────────────────────
animate_text "Launching Capsule..."
"$CAPSULE_EXEC" --llm-hf-repo "$LLM_HF_REPO" --llm-hf-model-name "$LLM_HF_MODEL_NAME" --model-cache "$PROJECT_MODEL_CACHE_DIR" &
CAPSULE_PID=$!

CAPSULE_READY_URL="http://0.0.0.0:42442/ready"
animate_text "Waiting for Capsule readiness..."
while true; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$CAPSULE_READY_URL")
    [[ "$STATUS" == "200" ]] && break
    sleep 5
    if ! kill -0 "$CAPSULE_PID" 2>/dev/null; then
        echo "Capsule exited unexpectedly."
        exit 1
    fi
done

# ─────────────────────────────────────────────────────────────
# Launch Protocol
# ─────────────────────────────────────────────────────────────
animate_text "Starting Protocol Node..."
"$PROTOCOL_EXEC" --account-private-key "$ACCOUNT_PRIVATE_KEY" --db-folder "$PROJECT_DEBUG_DIR/db" &
PROTOCOL_PID=$!

# ─────────────────────────────────────────────────────────────
# Keep Process Alive
# ─────────────────────────────────────────────────────────────
trap "kill $CAPSULE_PID $PROTOCOL_PID 2>/dev/null; exit 0" SIGINT SIGTERM
wait