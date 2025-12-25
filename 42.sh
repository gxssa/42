#!/bin/bash
set -e

animate_text() {
    local text="$1"
    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep 0.005
    done
    echo
}

# ─────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────
clear
echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│            Fortytwo CPU Node Setup                         │"
echo "└────────────────────────────────────────────────────────────┘"
echo ""

animate_text "Welcome to Fortytwo CPU Node Setup!"

# ─────────────────────────────────────────────────────────────
# Dependencies
# ─────────────────────────────────────────────────────────────
for pkg in curl unzip; do
    if ! command -v $pkg &> /dev/null; then
        animate_text "Installing $pkg..."
        sudo apt update && sudo apt install -y $pkg
    fi
done

# ─────────────────────────────────────────────────────────────
# Directories
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
# Download Fortytwo Utilities (Official)
# ─────────────────────────────────────────────────────────────
UTILS_VERSION=$(curl -fsSL https://download.swarminference.io/utilities/latest)
UTILS_URL="https://download.swarminference.io/utilities/v${UTILS_VERSION}/FortytwoUtilsLinux"

animate_text "Downloading Fortytwo Utils v$UTILS_VERSION..."
curl -fL -o "$UTILS_EXEC" "$UTILS_URL"
chmod +x "$UTILS_EXEC"

# ─────────────────────────────────────────────────────────────
# Identity Setup
# ─────────────────────────────────────────────────────────────
if [[ -f "$ACCOUNT_PRIVATE_KEY_FILE" ]]; then
    ACCOUNT_PRIVATE_KEY=$(cat "$ACCOUNT_PRIVATE_KEY_FILE")
    animate_text "✓ Existing identity loaded."
else
    echo ""
    echo "[1] Create new identity"
    echo "[2] Recover identity"
    read -rp "Select option [1-2]: " IDENTITY_OPTION

    if [[ "$IDENTITY_OPTION" == "2" ]]; then
        while true; do
            read -rp "Enter recovery phrase: " ACCOUNT_SEED_PHRASE
            if ACCOUNT_PRIVATE_KEY=$("$UTILS_EXEC" --phrase "$ACCOUNT_SEED_PHRASE"); then
                echo "$ACCOUNT_PRIVATE_KEY" > "$ACCOUNT_PRIVATE_KEY_FILE"
                animate_text "✓ Identity recovered."
                break
            else
                echo "Invalid phrase. Try again."
            fi
        done
    else
        "$UTILS_EXEC" --check-drop-service
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
echo "Choose model:"
echo " [1] VibeThinker 1.5B Q4"
echo " [2] Qwen3 1.7B"
read -rp "Select [1-2]: " MODEL_OPTION
MODEL_OPTION=${MODEL_OPTION:-1}

if [[ "$MODEL_OPTION" == "2" ]]; then
    LLM_HF_REPO="unsloth/Qwen3-1.7B-GGUF"
    LLM_HF_MODEL_NAME="Qwen3-1.7B-Q4_K_M.gguf"
    NODE_NAME="Qwen3 1.7B Q4"
else
    LLM_HF_REPO="mradermacher/VibeThinker-1.5B-GGUF"
    LLM_HF_MODEL_NAME="VibeThinker-1.5B.Q4_K_M.gguf"
    NODE_NAME="VibeThinker 1.5B Q4"
fi

animate_text "Selected model: $NODE_NAME"
"$UTILS_EXEC" --hf-repo "$LLM_HF_REPO" --hf-model-name "$LLM_HF_MODEL_NAME" --model-cache "$PROJECT_MODEL_CACHE_DIR"

# ─────────────────────────────────────────────────────────────
# Download Capsule (Custom ZIP)
# ─────────────────────────────────────────────────────────────
CAPSULE_ZIP_URL="https://raw.githubusercontent.com/gxssa/42/main/FortytwoCapsule.zip"
CAPSULE_ZIP_PATH="/tmp/FortytwoCapsule.zip"

animate_text "Downloading Capsule (custom build)..."
curl -fL -o "$CAPSULE_ZIP_PATH" "$CAPSULE_ZIP_URL"
unzip -o "$CAPSULE_ZIP_PATH" -d /tmp

if [[ ! -f "/tmp/FortytwoCapsule" ]]; then
    echo "✕ Capsule binary not found."
    exit 1
fi

mv /tmp/FortytwoCapsule "$CAPSULE_EXEC"
chmod +x "$CAPSULE_EXEC"
rm -f "$CAPSULE_ZIP_PATH"

# ─────────────────────────────────────────────────────────────
# Download Protocol (Official)
# ─────────────────────────────────────────────────────────────
PROTOCOL_VERSION=$(curl -fsSL https://download.swarminference.io/protocol/latest)
PROTOCOL_URL="https://download.swarminference.io/protocol/v${PROTOCOL_VERSION}/FortytwoProtocolNode-linux-amd64"

animate_text "Downloading Protocol v$PROTOCOL_VERSION..."
curl -fL -o "$PROTOCOL_EXEC" "$PROTOCOL_URL"
chmod +x "$PROTOCOL_EXEC"

# ─────────────────────────────────────────────────────────────
# Launch Capsule
# ─────────────────────────────────────────────────────────────
animate_text "Starting Capsule..."
"$CAPSULE_EXEC" \
  --llm-hf-repo "$LLM_HF_REPO" \
  --llm-hf-model-name "$LLM_HF_MODEL_NAME" \
  --model-cache "$PROJECT_MODEL_CACHE_DIR" \
  > "$CAPSULE_LOGS" 2>&1 &
CAPSULE_PID=$!
CAPSULE_LOGS="$PROJECT_DEBUG_DIR/FortytwoCapsule.logs"

CAPSULE_READY_URL="http://0.0.0.0:42442/ready"
animate_text "Waiting for Capsule readiness..."
until curl -sf "$CAPSULE_READY_URL" >/dev/null; do
    sleep 5
    kill -0 "$CAPSULE_PID" 2>/dev/null || exit 1
done

# ─────────────────────────────────────────────────────────────
# Launch Protocol
# ─────────────────────────────────────────────────────────────
animate_text "Starting Protocol..."
"$PROTOCOL_EXEC" --account-private-key "$ACCOUNT_PRIVATE_KEY" &
PROTOCOL_PID=$!

trap "kill $CAPSULE_PID $PROTOCOL_PID 2>/dev/null; exit 0" SIGINT SIGTERM
wait
