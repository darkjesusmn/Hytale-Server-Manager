Hytale Server Manager – Detailed Guide
Overview

The Hytale Server Manager is a PowerShell-based GUI application for managing your Hytale server. It provides a user-friendly interface to start, stop, and monitor your server, edit configuration files, view logs in real-time, and send commands without touching the terminal.

This manager is designed for local servers but can be adapted for remote setups with minor modifications. It supports color-coded logs, RAM allocation control, and real-time CPU/RAM monitoring.

Features

Server Control

Start / Stop / Restart buttons for the server.

Tracks server status live (Stopped, Running, Error).

Automatically starts log polling for real-time monitoring.

Dual Colored Console

Control Tab and Console Tab display the same logs.

[INFO] → Green, [WARN] → Yellow, [ERR] → Red.

Auto-scroll to show the newest lines.

Input box to send commands to the server.

Buttons for Admin and World commands for quick command execution.

RAM Management

TrackBars allow easy adjustment of minimum and maximum RAM allocated to the server.

Displays current RAM allocation.

CPU & RAM Monitoring

Live display of server process CPU and RAM usage in the Control tab.

Configuration Editor

Load and edit config.json directly in the GUI.

Validation ensures proper JSON formatting.

Save changes back to the file safely.

Update Tab

Simulates server update workflow.

Displays update status.

Check Files Tab

Validates presence of essential files:

HytaleServer.jar

Assets.zip

Server/ folder

mods/ folder

config.json

Shows color-coded status [OK] or [!!] for missing files.

Installation & Requirements

Requirements

Windows 10 or later

PowerShell 5+

Java JDK installed and added to system PATH.

Hytale server files: HytaleServer.jar, Assets.zip, server folder structure, config.json.

Installation

Clone or download this repository.

Place the script in the folder containing your Hytale server files.

Double-click the .ps1 script or run in PowerShell:

powershell -ExecutionPolicy Bypass -File .\HytaleServerManager.ps1

Usage Guide
1. Server Control Tab

Start Server: Launches the server with specified RAM settings.

Stop Server: Stops the running server gracefully.

Restart Server: Stops and restarts the server automatically.

CPU / RAM Labels: Live updates from server process.

2. RAM Sliders

Adjust min/max RAM allocation for the server.

Changes take effect the next time you start the server.

Range:

Min: 1–32 GB

Max: 1–64 GB

3. Console / Command Tab

Displays server logs in real-time with color coding:

[INFO] → Green

[WARN] → Yellow

[ERR] → Red

Input box: Type commands and hit Send to execute.

Buttons: Quick-access commands (Admin & World commands) to send directly.

4. Configuration Tab

Load Configuration: Loads config.json into the editor.

Edit Config: Change server options safely.

Save Configuration: Writes changes back to config.json with JSON validation.

5. Update Tab

Simulated server update workflow.

Shows status messages like “Updating server...” or “Update complete!”

6. Check Files Tab

Press Check Files to validate required files.

Missing files are highlighted in red.

Present files are highlighted in green.

Code Structure

The script is organized in sections:

Imports

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing


Loads Windows Forms and Drawing libraries for GUI.

Global Variables

$script:serverProcess = $null
$script:serverRunning = $false
$script:jarPath = Join-Path $PSScriptRoot "HytaleServer.jar"


Tracks server process, status, paths, and RAM settings.

Dark Mode Colors

$colorBack, $colorText, $colorConsoleBack, etc.

Functions

Server Management: Start-Server, Stop-Server, Restart-Server

CPU/RAM Monitoring: Update-CPUAndRAMUsage

Log Polling: Start-LogPolling

File Validation: Check-ServerFiles

Config Editor: Load-Config, Save-Config

Console Log Handling: Append-ServerLog

Sends lines to both consoles with appropriate colors.

GUI Components

TabControl with:

Control tab

Console tab

Config tab

Update tab

Check Files tab

Buttons, sliders, labels, RichTextBoxes.

Event Handling

Button clicks call their respective functions.

TrackBar scroll events update RAM values.

Timer (logTimer) polls server logs and updates consoles.

GUI Run

$form.ShowDialog()


Displays the full GUI and enters the event loop.

Future Improvements (Roadmap)

Player Management UI (ban, kick, op, perms)

World / Environment Controls UI

Plugin Manager

Automated backups

Start server minimized / hidden PowerShell window

Server stats graphs (CPU/RAM/players over time)

Scheduled tasks (restart server, auto-update)

Customizable theme

Remote server management

Server performance alerts (email/popup)
