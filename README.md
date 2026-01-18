# Hytale Server Manager

A **PowerShell-based GUI** for managing Hytale servers. Provides easy server control, real-time logs, RAM allocation, CPU/RAM monitoring, configuration editing, command sending, and more — all in a user-friendly interface.

fully made by AI LLMs this application was not made at all by a human, just prompts

---

## Overview

The **Hytale Server Manager** simplifies running a Hytale server by giving a full GUI with:

- Start / Stop / Restart server
- Dual console output (Control & Console tab)
- Colored logs `[INFO]`, `[WARN]`, `[ERR]`
- RAM sliders (min/max)
- CPU/RAM monitoring
- Configuration editor with JSON validation
- Quick command buttons
- File validation
- Update tab simulation

This tool is ideal for **local server management**, but can be adapted for remote servers.

---

## Features

| Feature | Description |
|---------|-------------|
| **Server Control** | Start, Stop, Restart server; live status display. |
| **Dual Colored Console** | Logs shown on Control & Console tabs with color coding: `[INFO]`=Green, `[WARN]`=Yellow, `[ERR]`=Red. |
| **Command Input** | Send commands to the server directly via input box or quick buttons. |
| **RAM Management** | Adjust min/max RAM allocation with sliders. |
| **CPU/RAM Monitoring** | Live usage display. |
| **Configuration Editor** | Edit `config.json` safely with JSON validation. |
| **Update Tab** | Simulate server update workflow. |
| **Check Files Tab** | Validates essential files and folders. |

---

## Installation & Requirements

### Requirements

- Windows 10 or later
- PowerShell 5+
- Java JDK installed and added to system PATH
- Hytale server files:
  - `HytaleServer.jar`
  - `Assets.zip`
  - `Server/` folder
  - `mods/` folder
  - `config.json`

### Installation

1. Clone or download this repository.
2. Place the script in the folder containing your Hytale server files.
3. Run the script via PowerShell:profit?

