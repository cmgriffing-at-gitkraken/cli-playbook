# CLI Playbook

A tool for recording and executing CLI command sequences with screen recording capabilities.

## Overview

CLI Playbook allows you to define a sequence of commands in a JSON playbook file and execute them while recording your screen. The tool is particularly useful for:

- Creating CLI demos
- Documenting development workflows
- Automating repetitive command sequences
- Creating tutorial videos

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

1. Create a JSON playbook file with your commands:

```json
{
  "setup": [
    "cd /your/project",
    "npm install"
  ],
  "runtime": [
    {
      "command": "npm start",
      "sleep": 5
    },
    {
      "command": "curl http://localhost:3000",
      "sleep": 5
    }
  ]
}
```

2. Run the playbook:

```bash
./run.sh your-playbook.json
```

## How It Works

1. **Setup Phase**: 
   - Executes all commands in the `setup` array
   - These commands are not recorded
   - Useful for preparation steps like installing dependencies

2. **Recording Phase**:
   - Starts screen recording
   - Executes all commands in the `runtime` array
   - Each command is executed in iTerm2
   - Commands have a 5-second delay between them
   - Screen recording captures all runtime commands

3. **Output**:
   - Recordings are saved to the `recordings` directory
   - Videos are automatically converted from MOV to MP4 format
   - Each recording has a timestamp in the filename

## File Structure

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
        "echo 'Setup complete'"
    ],
    "runtime": [
        "echo 'Running runtime commands...'",
        "echo 'Runtime complete'"
    ]
}
```

## Notes

- The script creates a new iTerm window if one doesn't exist
- Screen recording is done at 30 FPS
- Videos are converted to H.264/AAC MP4 format for compatibility
- Original MOV recordings are automatically deleted after conversion
