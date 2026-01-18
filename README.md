Hytale Server Manager

A PowerShell GUI-based manager for Hytale servers, providing an easy way to start, stop, restart, monitor, update, and configure your server without manually handling command-line operations. Built for Windows with a dark-themed, intuitive interface.

Features

Server Control: Start, stop, restart server with live console output.

Resource Monitoring: Real-time CPU and RAM usage display.

Configuration Management: Load and edit config.json and permissions.json from GUI.

Automatic Updates: Download the latest Hytale server files using the official downloader.

Command Interface: Send server commands via GUI, including admin commands.

File Integrity Check: Ensures all required files (HytaleServer.jar, Assets.zip, Server/, mods/, config.json) are present.

Dark Mode UI: Easy-on-the-eyes interface with colored consoles and tabs.

Installation

Download this repository and place all files in a single folder.

Required files:

HytaleServer.jar

Assets.zip

Server/ folder

mods/ folder (optional)

config.json

permissions.json

hytale-downloader-windows-amd64.exe

If you do not have the Server/ folder or other required files, you can run the Hytale Downloader (hytale-downloader-windows-amd64.exe) to download them.

Note: After downloading, extract the folder from the ZIP produced by the downloader. All server files and folders must be in the same folder as this manager.

Make sure Java is installed and accessible via your system PATH.

Run Hytale Server Manager.ps1 using PowerShell.

Usage
Server Control

Start Server: Launches the server with configured RAM allocation.

Stop Server: Gracefully stops the server.

Restart Server: Stops and immediately restarts the server.

Min/Max RAM Sliders: Adjust RAM allocation for the server.

Configuration

Load/Save Configuration: Edit config.json safely from the GUI.

Load/Save Permissions: Edit permissions.json safely.

Update Management

Update Server: Uses the official downloader to fetch the latest server files. Stops the server automatically if running.

Auto-Restart Option: Automatically restarts the server after updates.

Check Versions: Compare currently installed server version with the latest available.

Command Console

Send commands directly to the server.

Supports common admin commands:

/spawning, /ban, /unban, /gamemode, /give, /heal, /kick, /op, /perm, /plugin, /stop, /sudo, /tp, /whitelist, /ping.

File Checks

Check Files Button: Confirms presence of required files and folders.

Highlights missing files in red and shows [WARN] overall status.

Requirements

Windows OS

PowerShell 5.1+

Java 17+ (or version compatible with Hytale Server)

Official Hytale Server Downloader (for missing files or updates)

Folder Structure
HytaleServerManager/
│
├─ Hytale Server Manager.ps1
├─ HytaleServer.jar
├─ Assets.zip
├─ Server/
├─ mods/
├─ config.json
├─ permissions.json
├─ hytale-downloader-windows-amd64.exe
└─ logs/


All files/folders must be in the same directory as the manager.

Contributing

Feel free to submit PRs to improve UI, add features, or fix bugs. Please ensure PowerShell compatibility and Java version compatibility before submitting.

License

MIT License – Free to use, modify, and distribute.
