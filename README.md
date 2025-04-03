# CLI Playbook

A tool for recording and executing CLI command sequences with screen recording capabilities.

## Overview

CLI Playbook allows you to define a sequence of commands in a JSON playbook file and execute them while recording your screen. The tool is particularly useful for:

- Creating CLI demos and tutorials
- Documenting development workflows
- Automating repetitive command sequences
- Recording step-by-step technical procedures

## Requirements

- macOS (uses macOS-specific screen recording)
- `jq` (for JSON parsing)
- `ffmpeg` (for video conversion)
- iTerm2 (for command execution)

Install dependencies using Homebrew:

```bash
brew install jq ffmpeg
```

## Usage

1. Create a JSON playbook file with your command sequence:

```json
{
  "setup": [
    "echo 'Running setup commands...'",
    "echo 'Setup complete'",
    "clear"
  ],
  "runtime": [
    {
      "command": "echo 'Running runtime commands...'",
      "sleep": 3
    },
    {
      "command": "echo 'Runtime complete'",
      "sleep": 4
    }
  ]
}
```

2. Run the playbook:

```bash
./run.sh your-playbook.json
```

## Playbook Structure

Your playbook JSON file should contain two main sections:

### 1. Setup Section

- An array of commands to run before recording starts
- Used for preparation steps (installing dependencies, cleaning directories, etc.)
- These commands are not recorded
- Example:
  ```json
  "setup": [
    "npm install",
    "mkdir -p output"
  ]
  ```

### 2. Runtime Section

- An array of command objects that will be executed during recording
- Each command object can have:
  - `command`: The CLI command to execute
  - `sleep`: Time to wait after command execution (in seconds)
- Example:
  ```json
  "runtime": [
    {
      "command": "ls -la",
      "sleep": 3
    }
  ]
  ```

## How It Works

1. **Setup Phase**:

   - Executes all commands in the `setup` array
   - No recording during this phase
   - Prepares environment for main execution

2. **Recording Phase**:

   - Starts screen recording
   - Executes each command in the `runtime` array
   - Respects sleep intervals between commands
   - Captures all terminal output

3. **Output**:
   - Recordings are saved in the `recordings` directory
   - Videos are automatically converted from MOV to MP4
   - Filenames include timestamps for easy identification

## Project Structure

```
.
├── run.sh              # Main script
├── recordings/         # Directory for recorded videos
└── playbooks/         # Directory for playbook JSON files
```

## Example Playbook

```json
{
  "setup": [
    "echo 'Running setup commands...'",
    "echo 'Setup complete'",
    "clear"
  ],
  "runtime": [
    {
      "command": "echo 'Running runtime commands...'",
      "sleep": 3
    },
    {
      "command": "echo 'Runtime complete'",
      "sleep": 4
    }
  ]
}
```

## Notes

- The script creates a new iTerm window if one doesn't exist
- Screen recording is done at 30 FPS
- Videos are converted to H.264/AAC MP4 format for compatibility
- Original MOV recordings are automatically deleted after conversion
