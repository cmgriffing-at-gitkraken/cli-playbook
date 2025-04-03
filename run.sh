#!/bin/bash

# Exit on any error
set -e

# Exit on pipe failures (important for command chains)
set -o pipefail

# Default terminal applicationp
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

# Add this function near the top of the file, before execute_command
calculate_runtime() {
    local json_file="$1"
    local setup_time=0
    local runtime_time=0
    
    # Calculate setup commands time (0.5s per command + typing time)
    setup_time=$(jq -r '.setup | length' "$json_file")
    setup_time=$((setup_time * 1))  # 1 second per setup command
    
    # Calculate runtime commands time
    runtime_time=$(jq -r '.runtime | map(.sleep // 5) | add' "$json_file")
    
    # Add buffer time for startup, permissions, and final message
    local buffer_time=10
    
    # Total time in seconds
    echo $((setup_time + runtime_time + buffer_time))
}

# Replace the focus_terminal function with fullscreen detection
focus_terminal() {
    # Try to activate terminal
    osascript -e "
    tell application \"$TERMINAL_APP\"
        activate
    end tell
    "
    
    # Short delay for activation
    sleep 0.5
    
    # Check if we're in fullscreen mode and get frontmost app
    local check_result=$(osascript -e '
        tell application "System Events"
            # Get frontmost app
            set frontApp to first application process whose frontmost is true
            set frontAppName to name of frontApp
            
            # Check if any window is fullscreen
            set isFullscreen to false
            tell frontApp
                repeat with w in windows
                    if value of attribute "AXFullScreen" of w is true then
                        set isFullscreen to true
                        exit repeat
                    end if
                end repeat
            end tell
            
            return {frontAppName & "," & isFullscreen}
        end tell
    ')
    
    # Parse results
    local frontmost_app=$(echo "$check_result" | cut -d',' -f1)
    local is_fullscreen=$(echo "$check_result" | cut -d',' -f2)
    
    if [ "$is_fullscreen" = "true" ]; then
        echo "Error: Cannot proceed when a fullscreen window is active."
        echo "Please exit fullscreen mode before running the script."
        return 1
    fi
    
    if [[ ! "$frontmost_app" =~ $TERMINAL_APP ]]; then
        echo "Error: Could not focus terminal window. Please ensure $TERMINAL_APP is visible and on the current workspace."
        echo "Current frontmost app: $frontmost_app"
        return 1
    fi
    
    return 0
}

# Update execute_command to fail if focus isn't available
execute_command() {
    local cmd="$1"
    
    # Try to focus the terminal window
    if ! focus_terminal; then
        exit 1
    fi
    
    # Split command into words while preserving spaces and quotes
    local IFS=$'\n'
    local words=($(echo "$cmd" | sed -E $'s/[[:space:]]+/\\\n/g'))
    
    # Type each word in random chunks
    for i in "${!words[@]}"; do
        local word="${words[$i]}"
        local len=${#word}
        local pos=0
        
        # Type the word in random chunks
        while [ $pos -lt $len ]; do
            local chunk_size=$(( (RANDOM % 3) + 2 ))
            if [ $(($pos + $chunk_size)) -gt $len ]; then
                chunk_size=$(($len - $pos))
            fi
            
            local chunk="${word:$pos:$chunk_size}"
            osascript -e "
            tell application \"System Events\"
                keystroke \"${chunk}\"
                delay 0.05
            end tell
            "
            
            pos=$(($pos + $chunk_size))
        done
        
        # Add space between words (except for last word)
        if [ "$i" -lt "$(( ${#words[@]} - 1 ))" ]; then
            osascript -e "
            tell application \"System Events\"
                keystroke space
            end tell
            "
        fi
    done
    
    # Execute the command
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
        return 1
    fi
}

# Update the check_screen_recording_permission function
check_screen_recording_permission() {
    echo "Checking screen recording permission..."
    
    # Try a test recording for 1 second
    TEST_FILE="/tmp/test_recording.mov"
    if screencapture -V 1.0 "$TEST_FILE" 2>/dev/null; then
        echo "Screen recording permission verified"
        rm -f "$TEST_FILE"
        return 0
    else
        echo "Screen recording permission error detected."
        echo "Please ensure screen recording permission is granted to $TERMINAL_APP in:"
        echo "System Preferences > Security & Privacy > Privacy > Screen Recording"
        echo "After granting permission, please:"
        echo "1. Quit $TERMINAL_APP completely"
        echo "2. Relaunch $TERMINAL_APP"
        return 1
    fi
}

# Replace the verify_terminal_permissions function with this version
verify_terminal_permissions() {
    local terminal_app="$1"
    echo "Verifying permissions for $terminal_app..."
    
    # Try a quick test recording to verify permissions
    TEST_FILE="/tmp/test_recording.mov"
    if screencapture -V 1.0 "$TEST_FILE" 2>/dev/null; then
        echo "Screen recording permission verified"
        rm -f "$TEST_FILE"
        return 0
    fi
    
    echo "Warning: Unable to verify screen recording permissions"
    echo "Please make sure to grant screen recording permissions to $terminal_app"
    echo "System Preferences > Security & Privacy > Privacy > Screen Recording"
    return 1
}

# Check if terminal application is running and launch it if needed
check_terminal_app() {
    local was_launched=false
    
    # First check if we have accessibility permissions
    if ! osascript -e 'tell application "System Events" to get name of first process' &>/dev/null; then
        echo "Error: Accessibility permission is required"
        echo "Please grant accessibility permission to Terminal/iTerm in:
System Preferences > Security & Privacy > Privacy > Accessibility"
        echo "After granting permission, you may need to restart your terminal application"
        exit 1
    fi
    
    # Simple check if the terminal is running
    if ! pgrep -i "$TERMINAL_APP" >/dev/null; then
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

# Uncomment and modify the permission checks
echo "Checking accessibility permission..."
if ! check_accessibility_permission; then
    exit 1
fi

echo "Checking screen recording permission..."
if ! check_screen_recording_permission; then
    exit 1
fi

# Add this call before starting the recording
echo "Verifying terminal permissions..."
verify_terminal_permissions "$TERMINAL_APP"

echo "Checking terminal application..."
check_terminal_app

# Process setup commands first
echo "Running setup commands..."
while IFS= read -r cmd; do
    if [[ -n "$cmd" ]]; then
        execute_command "$cmd"
    fi
done < <(jq -r '.setup[]' "$JSON_FILE" 2>/dev/null)

# Replace the recording section with this version
echo "Starting screen recording..."

# Calculate expected runtime
TOTAL_RUNTIME=$(calculate_runtime "$JSON_FILE")
echo "Estimated runtime: $TOTAL_RUNTIME seconds"

# Generate unique filenames for the recording
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RECORDING_FILE="$RECORDINGS_DIR/screen_recording_$TIMESTAMP.mov"
MP4_FILE="$RECORDINGS_DIR/screen_recording_$TIMESTAMP.mp4"

# Start the recording
echo "Starting recording to $RECORDING_FILE..."
screencapture -V "$TOTAL_RUNTIME.0" "$RECORDING_FILE" &
RECORDING_PID=$!

sleep 2

# Verify recording process started
if ! ps -p $RECORDING_PID > /dev/null; then
    echo "Error: Recording process failed to start"
    exit 1
fi

echo "Recording process started with PID: $RECORDING_PID"
RECORDING_START_TIME=$SECONDS

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

# Stop recording with better error handling
echo "Stopping screen recording..."
kill -SIGINT $RECORDING_PID

# Calculate actual runtime
ACTUAL_RUNTIME=$((SECONDS - RECORDING_START_TIME))
MINIMUM_RUNTIME=5  # Minimum seconds needed for a valid recording

# Wait for recording to complete
echo "Waiting for recording to complete..."
while [ $((SECONDS - RECORDING_START_TIME)) -lt $TOTAL_RUNTIME ]; do
    sleep 1
    echo -n "."
done
echo  # New line after dots

# Additional wait to ensure file is fully written
sleep 3

# Verify recording duration and file
if [ $ACTUAL_RUNTIME -lt $MINIMUM_RUNTIME ]; then
    echo "Error: Recording duration too short ($ACTUAL_RUNTIME seconds)"
    echo "Expected at least $MINIMUM_RUNTIME seconds"
    exit 1
fi

if [ ! -f "$RECORDING_FILE" ]; then
    echo "Error: Recording file was not created at: $RECORDING_FILE"
    echo "Available files in recordings directory:"
    ls -la "$RECORDINGS_DIR"
    exit 1
fi

# Get file size and verify it's not empty
FILE_SIZE=$(stat -f %z "$RECORDING_FILE")
if [ "$FILE_SIZE" -lt 1000 ]; then  # Less than 1KB
    echo "Error: Recording file is too small ($FILE_SIZE bytes)"
    exit 1
fi

echo "Recording completed successfully:"
echo "- Duration: $ACTUAL_RUNTIME seconds"
echo "- File size: $FILE_SIZE bytes"
echo "- Location: $RECORDING_FILE"

# Convert to MP4 with better error handling
if command -v ffmpeg &> /dev/null; then
    echo "Converting recording to MP4 format..."
    if [ ! -f "$RECORDING_FILE" ]; then
        echo "Error: Source recording file not found: $RECORDING_FILE"
        exit 1
    fi
    
    echo "Starting conversion from $RECORDING_FILE to $MP4_FILE"
    if ffmpeg -i "$RECORDING_FILE" \
        -c:v libx264 -preset medium \
        -pix_fmt yuv420p \
        -movflags +faststart \
        -y "$MP4_FILE" 2>"$RECORDINGS_DIR/conversion_error.log"; then
        
        echo "Converted successfully to: $MP4_FILE"
        echo "MP4 file size: $(stat -f %z "$MP4_FILE") bytes"
        rm "$RECORDING_FILE"  # Remove the original .mov file
    else
        echo "Warning: MP4 conversion failed. Error log:"
        cat "$RECORDINGS_DIR/conversion_error.log"
        echo "Keeping original .mov file: $RECORDING_FILE"
        echo "Available files in recordings directory:"
        ls -la "$RECORDINGS_DIR"
    fi
else
    echo "Recording saved as: $RECORDING_FILE"
fi

# Print completion message to the controlled terminal
osascript -e "
tell application \"$TERMINAL_APP\"
    activate
end tell
"
sleep 0.5

# TODO: Kind of annoying that we type echo and then actually echo
execute_command "echo 'Recording Completed!'"

# Function to handle errors
handle_error() {
    local line=$1
    local command=$2
    local code=$3
    echo "Error at line $line: Command '$command' exited with status $code"
    
    # If recording is in progress, try to stop it
    if [ -n "${RECORDING_PID:-}" ]; then
        echo "Stopping screen recording due to error..."
        kill -SIGINT $RECORDING_PID 2>/dev/null || true
    fi
    
    exit "$code"
}

# Set up error trap
trap 'handle_error ${LINENO} "$BASH_COMMAND" $?' ERR
