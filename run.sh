#!/bin/bash

# Default terminal application
TERMINAL_APP="iTerm"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -t|--terminal) TERMINAL_APP="$2"; shift ;;
        *) JSON_FILE="$1" ;;
    esac
    shift
done

# Check if required tools are installed
for tool in jq ffmpeg; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: $tool is required but not installed"
        echo "Install it using: brew install $tool"
        exit 1
    fi
done

# Check if a file was provided as an argument
if [ -z "$JSON_FILE" ]; then
    echo "Error: Please provide a JSON file as an argument"
    echo "Usage: $0 [--terminal <app_name>] <filename.json>"
    echo "       Default terminal is iTerm"
    exit 1
fi

# Check if the file exists
if [ ! -f "$JSON_FILE" ]; then
    echo "Error: File '$JSON_FILE' not found"
    exit 1
fi

# Create recordings directory if it doesn't exist
RECORDINGS_DIR="recordings"
mkdir -p "$RECORDINGS_DIR"

# Generate unique filenames for the recording
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MP4_FILE="$RECORDINGS_DIR/screen_recording_$TIMESTAMP.mp4"

# Calculate delays for 150 WPM typing simulation
CHAR_DELAY=0.008  # 150 WPM = ~750 chars per minute = ~0.008s per char

# Function to type a single character using System Events
type_char() {
    local char="$1"
    osascript -e "
    tell application \"System Events\"
        keystroke \"$char\"
    end tell
    "
}

# Function to execute commands with typing simulation
execute_command() {
    local cmd="$1"
    local length=${#cmd}
    
    # Activate terminal window
    osascript -e "
    tell application \"$TERMINAL_APP\"
        activate
    end tell
    "
    
    # Small delay to ensure terminal is ready
    sleep 0.5
    
    # Type each character with delay
    for (( i=0; i<length; i++ )); do
        char="${cmd:$i:1}"
        type_char "$char"
        sleep $CHAR_DELAY
    done

    # Send return key to execute the command
    osascript -e "
    tell application \"System Events\"
        keystroke return
    end tell
    "
}

# Check for accessibility permissions
check_accessibility_permission() {
    # Try to use System Events - this will trigger permission prompt if needed
    if ! osascript -e 'tell application "System Events" to get name of first process' &>/dev/null; then
        echo "Error: Accessibility permission is required"
        echo "Please grant accessibility permission to Terminal/iTerm in System Preferences > Security & Privacy > Privacy > Accessibility"
        echo "After granting permission, you may need to restart your terminal application"
        exit 1
    fi
}

# Check for screen recording permissions
check_screen_recording_permission() {
    # Try to list devices - this will trigger permission prompt if needed
    ffmpeg -f avfoundation -list_devices true -i "" &>/dev/null
    
    # Check if we can actually access screen devices
    if ! ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -q "Capture screen"; then
        echo "Error: Screen recording permission is required"
        echo "Please grant screen recording permission to Terminal/iTerm in System Preferences > Security & Privacy > Privacy > Screen Recording"
        echo "After granting permission, you may need to restart your terminal application"
        exit 1
    fi
}

# Check if terminal application is running and launch it if needed
check_terminal_app() {
    local was_launched=false
    local terminal_lower=$(echo "$TERMINAL_APP" | tr '[:upper:]' '[:lower:]')
    
    # Case-insensitive check for running terminal
    if ! osascript -e "
        tell application \"System Events\"
            set processList to name of every process
            set foundProcess to false
            repeat with processName in processList
                if (processName as string) contains \"$TERMINAL_APP\" or (lowercase of (processName as string)) contains \"$terminal_lower\" then
                    set foundProcess to true
                    exit repeat
                end if
            end repeat
            return foundProcess
        end tell
    " | grep -q "true"; then
        echo "Launching $TERMINAL_APP..."
        osascript -e "tell application \"$TERMINAL_APP\" to activate"
        was_launched=true
        sleep 1
    fi
    
    # If we just launched the terminal, make it full screen
    if [ "$was_launched" = true ]; then
        echo "Setting $TERMINAL_APP to full screen..."
        if [ "$TERMINAL_APP" = "iTerm" ] || [ "$terminal_lower" = "iterm" ]; then
            # iTerm-specific full screen command
            osascript -e '
            tell application "iTerm"
                tell current window
                    set fullscreen to true
                end tell
            end tell
            '
        else
            # Generic approach for other terminals
            osascript -e "
            tell application \"System Events\"
                tell process \"$TERMINAL_APP\"
                    keystroke \"f\" using {command down, control down}
                end tell
            end tell
            "
        fi
        sleep 1
    fi
}

# Check for required permissions and applications
echo "Checking permissions and applications..."
check_accessibility_permission
check_screen_recording_permission
check_terminal_app

# Process setup commands first
echo "Running setup commands..."
while IFS= read -r cmd; do
    if [[ -n "$cmd" ]]; then
        execute_command "$cmd"
    fi
done < <(jq -r '.setup[]' "$JSON_FILE" 2>/dev/null)

# Start screen recording
echo "Starting screen recording..."

# List available devices and capture the screen index
SCREEN_DEVICE=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep "Capture screen" | head -n1 | grep -o "[0-9]")
if [ -z "$SCREEN_DEVICE" ]; then
    echo "Error: Could not find screen capture device"
    echo "Available devices:"
    ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -A4 "AVFoundation"
    exit 1
fi

# Record screen using the detected device index
ffmpeg -f avfoundation -i "${SCREEN_DEVICE}:none" -framerate 30 -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$MP4_FILE" &
FFMPEG_PID=$!

# Process runtime commands
echo "Running runtime commands..."
# Use jq to extract each runtime command object as a complete JSON object
jq -c '.runtime[]' "$JSON_FILE" | while read -r line; do
    if [[ -n "$line" ]]; then
        # Parse command and sleep time from JSON object
        cmd=$(echo "$line" | jq -r '.command // empty')
        sleep_time=$(echo "$line" | jq -r '.sleep // 5')
        
        if [[ -n "$cmd" ]]; then
            execute_command "$cmd"
            sleep "$sleep_time"
        fi
    fi
done

# Stop screen recording
echo "Stopping screen recording..."
kill -SIGINT $FFMPEG_PID

# Wait a moment for the recording to finish writing
sleep 2

echo "Recording saved to: $MP4_FILE"

# Print completion message to the controlled terminal
osascript -e "
tell application \"$TERMINAL_APP\"
    activate
end tell
"
sleep 0.5

# TODO: Kind of annoying that we type echo and then actually echo
execute_command "echo 'Recording Completed!'"
