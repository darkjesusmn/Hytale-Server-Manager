Hytale Server Manager

A PowerShell GUI-based server manager for Hytale, designed to simplify running, updating, and managing your Hytale server. It includes server control, automatic updates, console commands, configuration editing, and file verification — all in a dark-themed interface.

🚀 Features

Server Control

Start, stop, and restart your server with one click.

Auto-restart after updates or crashes.

Adjustable RAM allocation via sliders.

Real-time CPU and RAM monitoring.

Configuration & Permissions

Load, edit, and save config.json and permissions.json via GUI.

Syntax validation to prevent JSON errors.

Update Management

Automatic server updates using the official Hytale downloader.

Merge new files safely.

Auto-clean temporary files.

Update logs displayed in the GUI.

Console & Commands

Integrated server console with live output.

Send commands directly via GUI input.

Quick-access buttons for common commands:
/ban, /unban, /op, /kick, /give, /tp, /gamemode, /heal, /sudo, /stop, /whitelist, /plugin.

File Verification

Checks required files and directories:

HytaleServer.jar, Assets.zip, Server/, mods/, config.json.

Status indicators for missing or present files.

Overall server readiness display.

Dark Mode GUI

High-contrast colors and intuitive tabs for easy navigation.

🛠 Installation

Download this repository and place all files in a single folder.

Required files

HytaleServer.jar

Assets.zip

Server/ folder

mods/ folder (optional)

config.json

permissions.json

hytale-downloader-windows-amd64.exe

If you don’t have the Server/ folder or required files:

Run the Hytale Downloader (hytale-downloader-windows-amd64.exe) to download missing files.

Important: Extract the folder from the ZIP provided by the downloader.

Make sure all files and folders are in the same directory as this manager.

Ensure Java 17+ is installed and added to your system PATH.

Run the manager using PowerShell:

.\HytaleServerManager.ps1


The GUI will launch automatically; the PowerShell console window is hidden.

🎮 Usage
Server Control

Start Server: Launches the server with selected RAM settings.

Stop Server: Gracefully shuts down the server.

Restart Server: Stops and restarts automatically.

RAM Allocation: Adjust min/max RAM sliders.

Configuration

Load/Save Configuration: Edit config.json.

Load/Save Permissions: Edit permissions.json.

Update Management

Update Server: Downloads and merges latest server files. Stops server automatically if running.

Auto-Restart: Start server automatically after updates.

Check Version: Compare current server version with latest available.

Console Commands

Enter commands directly into the GUI input box.

Quick buttons for frequent commands:
/spawning, /ban, /unban, /gamemode, /give, /heal, /kick, /op, /perm, /plugin, /stop, /sudo, /tp, /whitelist, /ping.

File Checks

Check Files: Verify all required files and folders exist.

Status indicators:

✅ [OK] – file present

⚠ [WARN] – file missing

📁 Folder Structure
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

⚙ Requirements

Windows 10/11

PowerShell 5.1+

Java 17+ (compatible with Hytale Server)

Official Hytale Server Downloader (for missing files or updates)

🔧 Advanced Functions
Function	Description
Start-Server	Launches Hytale server with selected RAM allocation.
Stop-Server	Stops the running server safely.
Restart-Server	Stops and restarts the server.
Check-ServerFiles	Verifies required files and folders.
Update-Server	Downloads and installs latest server files.
Load-Config / Save-Config	Edit and save config.json.
Load-Permissions / Save-Permissions	Edit and save permissions.json.
Send-ServerCommand	Sends a raw command to the server process.
Get-VersionFromConsole	Reads server version from console output.
Run-DownloaderCommand	Executes the Hytale downloader with custom arguments.
🤝 Contributing

PRs for new features, plugins, or GUI improvements are welcome.

Ensure compatibility with PowerShell 5.1+ and Java 17+.

📜 License

MIT License – Free to use, modify, and distribute. Attribution appreciated.

🙏 Acknowledgements

Official Hytale server and downloader.

Inspired by Minecraft server managers.

Built with PowerShell and Windows Forms for accessibility and ease-of-use.
