INSERT INTO readmes (project_name, content) VALUES (
    'Hytale Server Manager',
    $README$
# Hytale Server Manager

A PowerShell GUI-based server manager for Hytale. Easily run, update, and manage your server with a dark-themed interface. Includes server control, automatic updates, console commands, configuration editing, and file verification

---

## Features

### Server Control
* Start, stop, and restart your server with one click
* Auto-restart after updates or crashes
* Adjustable RAM allocation (min/max) with sliders
* Real-time CPU and RAM usage monitoring

### Configuration & Permissions
* Load, edit, and save config.json and permissions.json
* JSON syntax validation for safe editing
* Pretty-print JSON for readability

### Server Updates
* Download and install latest server files using the official Hytale downloader
* Auto-restart server after update
* View detailed update logs in GUI
* Verify if server update is available

### Console & Commands
* View live server console output
* Send commands directly to the server
* Preloaded buttons for common admin commands like /ban, /kick, /give, /op, /tp
* Command history support

### File Management
* Check for required files and folders (HytaleServer.jar, Assets.zip, Server folder, mods folder, config.json)
* Highlights missing files in GUI
* Can download missing files via Hytale downloader

---

## Installation

* Ensure you have PowerShell installed (Windows recommended)
* Place the Hytale Server Manager script in a folder of your choice
* Download the Hytale server files or use the Hytale downloader to get any missing files
* Extract the downloaded server files from the downloader so all files are in the **same directory** as this manager
* Launch the PowerShell script by right clicking it and run with powershell

---

## Usage

* **Start Server** - Starts the Hytale server using selected RAM settings
* **Stop Server** - Stops the running server
* **Restart Server** - Stops and restarts the server automatically
* **Adjust RAM** - Use sliders to set minimum and maximum RAM
* **Load Configuration** - Opens config.json in the built-in editor
* **Save Configuration** - Saves changes to config.json
* **Load Permissions** - Opens permissions.json in the built-in editor
* **Save Permissions** - Saves changes to permissions.json
* **Update Server** - Downloads latest server files and merges them automatically
* **Check Files** - Verifies all required files and folders are present
* **Console Tab** - View live server logs and send commands directly
* **Command Buttons** - Quickly insert common admin commands into console input

---

## Requirements

* Windows OS with PowerShell support
* Java installed and accessible in PATH
* HytaleServer.jar, Assets.zip, and Server folder in the same directory as the manager
* Hytale downloader (hytale-downloader-windows-amd64.exe) for updates and missing files

---

## Notes

* Missing files can be obtained using the Hytale downloader
* Extract downloaded server files so the folder structure matches the manager's directory
* Auto-restart can be toggled in the update tab
* Always back up your server files before major updates
$README$;
