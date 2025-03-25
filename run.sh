#!/bin/bash

# Check if required tools are installed
for tool in jq ffmpeg; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: $tool is required but not installed"
        echo "Install it using: brew install $tool"
        exit 1
    fi
done

# Check if a file was provided as an argument
if [ $# -eq 0 ]; then
    echo "Error: Please provide a JSON file as an argument"
    echo "Usage: $0 <filename.json>"
    exit 1
fi

# Check if the file exists
if [ ! -f "$1" ]; then
    echo "Error: File '$1' not found"
    exit 1
fi

# Create recordings directory if it doesn't exist
RECORDINGS_DIR="recordings"
mkdir -p "$RECORDINGS_DIR"

# Generate unique filenames for the recording
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RECORDING_FILE="$RECORDINGS_DIR/screen_recording_$TIMESTAMP.mov"
MP4_FILE="$RECORDINGS_DIR/screen_recording_$TIMESTAMP.mp4"

# Calculate delays for 50 WPM typing simulation
CHAR_DELAY=0.024  # 50 WPM = ~250 chars per minute = ~0.024s per char

# Function to type a single character in iTerm
type_char() {
    local char="$1"
    osascript <<EOF
    tell application "iTerm"
        tell current window
            tell current session
                write text "$char" without newline
            end tell
        end tell
    end tell
EOF
}

# Function to execute commands in iTerm with typing simulation
execute_command() {
    local cmd="$1"
    local length=${#cmd}
    
    # Create/activate iTerm window if needed
    osascript <<EOF
    tell application "iTerm"
        if not (exists current window) then
            create window with default profile
        end if
        activate
    end tell
EOF
    
    # Type each character with delay
    for (( i=0; i<length; i++ )); do
        char="${cmd:$i:1}"
        type_char "$char"
        sleep $CHAR_DELAY
    done
    
    # Press enter
    osascript <<EOF
    tell application "iTerm"
        tell current window
            tell current session
                write text ""
            end tell
        end tell
    end tell
EOF
    
    sleep 5
}

# Process setup commands first
echo "Running setup commands..."
while IFS= read -r cmd; do
    if [[ -n "$cmd" ]]; then
        execute_command "$cmd"
    fi
done < <(jq -r '.setup[]' "$1" 2>/dev/null)

# Clear the screen before starting runtime commands
osascript <<EOF
tell application "iTerm"
    tell current window
        tell current session
            write text "clear"
        end tell
    end tell
end tell
EOF
sleep 1

# Start screen recording
echo "Starting screen recording..."
screencapture -v -V 30 "$RECORDING_FILE" &
SCREEN_CAPTURE_PID=$!

# Process runtime commands
echo "Running runtime commands..."
while IFS= read -r cmd; do
    if [[ -n "$cmd" ]]; then
        execute_command "$cmd"
    fi
done < <(jq -r '.runtime[]' "$1" 2>/dev/null)

# Stop screen recording
echo "Stopping screen recording..."
kill $SCREEN_CAPTURE_PID

# Wait a moment for the recording to finish writing
sleep 2

# Convert MOV to MP4
echo "Converting recording to MP4..."
ffmpeg -i "$RECORDING_FILE" -vcodec h264 -acodec aac "$MP4_FILE" -y

# Remove the original MOV file
rm "$RECORDING_FILE"

echo "Recording saved to: $MP4_FILE"
