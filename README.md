# **Hytale Server Manager GUI - Comprehensive Guide**

**This program was full made by AI LLM's ChatGPT, ClaudeAI, Copilot, qwen:14b, qen 2.5-coder:14b. ZERO CODE WAS MADE BY A HUMAN**



## Overview
Hytale Server Manager (DJMN) is a PowerShell-based GUI for managing Hytale servers. It provides:

- Easy start/stop/restart control for your server
- Console log viewing and server command execution
- Configuration editing
- Mod management
- Automatic download of required server files and downloader executable

The GUI is fully **zero-state safe**, meaning it can launch and display all tabs even if no server files, config, or logs exist.

---

## Table of Contents
1. [First-Time Setup](#first-time-setup)
2. [Control Tab](#control-tab)
3. [Console Tab](#console-tab)
4. [Configuration Tab](#configuration-tab)
5. [Mod Manager Tab](#mod-manager-tab)
6. [Troubleshooting](#troubleshooting)
7. [Tips & Recommendations](#tips--recommendations)

---

## 1️⃣ First-Time Setup

### Step 1: Launch the Manager
- Open `Hytale_Server_Manager_DJMN.ps1` in PowerShell.  
- The GUI will launch even if no files or folders exist.  
- Warnings will appear about missing server files — this is normal.

### Step 2: Download the Server Downloader
- Click the **“Update Downloader”** button.  
- Downloads the `hytale-downloader-windows-amd64.exe` file.  
- GUI remains functional while downloading.

### Step 3: Download Server Files
- Click **“Update Server”**.  
- The downloader will prompt for an **authorization code/link**.  
- Follow instructions to authorize your account.  
- Server files (`HytaleServer.jar`, `Assets.zip`, config skeletons, etc.) are downloaded and extracted.  
- Your server folder is now fully populated.

### Step 4: Start the Server
- Use the **Control Tab** to click **Start Server**.  
- Server logs appear in the console tab.  
- The server may prompt for a new authorization link — follow it to complete the connection to Hytale’s network.

### Step 5: Optional Authentication
- In the **Console Tab**, click the **`/auth login device`** button to generate the authorization link automatically, without typing the command manually.

---

## 2️⃣ Control Tab
The **Control Tab** allows you to manage the server lifecycle:

| Button | Function | Notes |
|--------|---------|-------|
| Start Server | Launches the Hytale server | Disabled if server files are missing |
| Stop Server | Stops the running server process | Disabled if no server is running |
| Restart Server | Stops and then starts the server | Shows warning if server files are missing |

**Zero-State Behavior:**  
- Buttons show warnings if server files are missing.  
- No crashes occur when server isn’t running.  

---

## 3️⃣ Console Tab
The **Console Tab** allows you to view live logs and send commands to the server.

### Components:
- **Log Output Textbox**: Displays real-time server logs.
- **Command Textbox**: Type commands to send to the server.
- **Send Button**: Sends the command in the textbox.
- **`/auth login device` Button**: Sends the command to generate an authorization link automatically.

**Notes:**
- If the server is not running, the buttons display warnings instead of failing.
- Logs update live as the server writes to its stdout.

---

## 4️⃣ Configuration Tab
The **Configuration Tab** allows you to view and edit `config.json`.

### Features:
- **Config Editor**: Shows the contents of `config.json`.  
- **Save / Apply Buttons**: Write changes back to `config.json`.  

**Zero-State Behavior:**
- If `config.json` doesn’t exist, the editor is empty.  
- Saving will create a new config file if none exists.  

---

## 5️⃣ Mod Manager Tab
The **Mod Manager Tab** allows you to manage installed mods.

### Features:
- Shows contents of `mods/` and `mods_disabled/` folders.  
- Allows enabling/disabling mods without editing files manually.

**Zero-State Behavior:**
- Empty folders are handled gracefully.  
- GUI does not crash if no mods are installed.

---

## 6️⃣ Troubleshooting

### Common Issues:
1. **Server Won’t Start**
   - Ensure `HytaleServer.jar` and `Assets.zip` exist in the script folder.
   - Use **Update Server** to download missing files.

2. **Authorization Needed**
   - Use the `/auth login device` button in the console tab to generate the link.

3. **Button Clicks Do Nothing**
   - Check that the server is running when sending commands.
   - GUI warnings indicate missing files or inactive server.

4. **PowerShell Errors on Launch**
   - Ensure you are running in **STA mode**:  
     ```powershell
     powershell -sta -file Hytale_Server_Manager_DJMN.ps1
     ```

---

## 7️⃣ Tips & Recommendations
- Always keep your **hytale-downloader-windows-amd64.exe** updated.  
- For first-time users, follow the exact **First-Time Setup** sequence to ensure a clean environment.  
- All tabs are zero-state safe, but server operations require files and authorization.  
- Back up your `config.json` before making large changes.  
- Use the **Console Tab** to monitor logs and test server commands interactively.

---



<img width="1180" height="638" alt="{88D7501D-2B5F-4556-991A-7E951DD44F7B}" src="https://github.com/user-attachments/assets/8576a157-09eb-4da3-b7db-5dfbf3a2c8ce" />

<img width="1179" height="406" alt="{09CD1A69-6DFA-49E5-BB4C-7D1D47407508}" src="https://github.com/user-attachments/assets/09f84596-3c2b-4ef1-9857-2838d853754d" />

<img width="1179" height="638" alt="{ADFB9C6D-579B-4EE5-B075-F6AB4304B27F}" src="https://github.com/user-attachments/assets/428f6def-99b5-4ed3-a4ad-83a2bf5f0e24" />



