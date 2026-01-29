# **Hytale Server Manager GUI - Comprehensive Guide**

**This program was full made by AI LLM's ChatGPT, ClaudeAI, Copilot, qwen:14b, qen 2.5-coder:14b. ZERO CODE WAS MADE BY A HUMAN**

## **1. Installation Guide**

### **Prerequisites**
- **Windows Operating System** (tested on Windows 10/11)
- **hytale-downloader-windows-amd64.exe** (place in the same directory as the script)

### **Steps to Install and Run**
1. **Download the Script and Downloader**
   - Download the `HytaleServerManager.ps1` script from the provided source.
   - Place file in the same directory as your server(e.g., `C:\HytaleServer`).

2. **Run the Script**
   - **Right-click** the `HytaleServerManager.ps1` file.
   - Select **"Run with PowerShell"** from the context menu.
   - **No admin permissions are required** for this step.

3. ## 🟢 First-Time Setup for Hytale Server Manager

### 1️⃣ Launch the Manager for the First Time
- Open **Hytale_Server_Manager_DJMN.ps1** in PowerShell.  
- The GUI will launch even if no files or folders exist.  
- You’ll see warnings that required server files are missing — this is normal.  

---

### 2️⃣ Download the Server Downloader
- Click the **“Update Downloader”** button.  
- This downloads the `hytale-downloader-windows-amd64.exe` file required to fetch the server.  
- The GUI remains fully functional during this process.

---

### 3️⃣ Download the Server Files
- Click the **“Update Server”** button.  
- The downloader executable will open a window asking for an **authorization code/link**.  
- Follow the instructions in the window to authorize your account.  
- The downloader will fetch and extract **all necessary server files**, including:
  - `HytaleServer.jar`  
  - `Assets.zip`  
  - Config skeletons and folders  
- At this point, your server folder is fully populated and ready for first launch.

---

### 4️⃣ Start the Server
- Go to the **Control tab** and click **Start Server**.  
- The console tab will show server logs.  
- The server will start and may prompt for a new **authorization link** to connect to Hytale’s official server network.  
- Follow the link to complete authorization.

---

### 5️⃣ Optional: Authenticate the Server Easily
- In the **Console tab**, a new **`/auth login device`** button allows you to send the command automatically.  
- This generates the authorization link for connecting your server to Hytale servers without manually typing it.

---

### ✅ Notes
- All tabs (Control, Config, Mod Manager) are **fully zero-state safe** — the GUI won’t crash if files are missing.  
- Warnings are displayed instead of failing silently.  
- After this setup, you can start, stop, and configure the server fully through the manager.  


---

## **2. Key Features Overview**

### **A. Server Control**
- **Start/Stop/Restart Server**: Buttons to manage the server lifecycle.
- **RAM Configuration**: Sliders to set minimum and maximum RAM allocation for the server.
- **Console Management**: Real-time server console output with options to **clear**, **save**, or **copy** logs.

### **B. Configuration Editor**
- **Edit `config.json` and `permissions.json`**: Rich text editor for server configuration and permissions.
- **Save/Load Configurations**: Buttons to save changes or reload the current configuration.

### **C. Server Maintenance**
- **Check Required Files**: Validates the presence of essential files (e.g., `HytaleServer.jar`, `Assets.zip`, `config.json`).
- **Update Server**: Uses the `hytale-downloader` to fetch the latest server files. **Must be initiated manually**.
- **Update Log**: Displays logs from the update process, including success/failure messages.

### **D. Admin & World Commands**
- **Predefined Command Buttons**: Quick access to common admin and world commands (e.g., `/ban`, `/tp`, `/time`).
- **Custom Command Input**: Type and send custom commands directly to the server.

---

## **3. How to Use the Program**

### **Step 1: Launch the GUI**
- Right-click the script and select **"Run with PowerShell"**.
- The GUI will open, but **no server files will be downloaded automatically**.

### **Step 2: Download Server Files (First-Time Use)**
- Navigate to the **"Server Maintenance"** tab.
- Click the **"Update Server"** button.
  - This will:
    - Stop the server if it's running.
    - Use the `hytale-downloader` to download the latest server files.
    - Display progress in the **"Update Log"** textbox.
  - **Note**: This step is required for **first-time use** or **updates**.

### **Step 3: Start the Server**
- After downloading files, click the **"Start Server"** button.
- The server will launch with the configured RAM settings.
- Monitor the **"Main Console"** for server output and logs.

### **Step 4: Manage Server Settings**
- **Adjust RAM**: Use the sliders to set minimum and maximum RAM for the server.
- **Edit Configurations**: Click **"Load Configuration"** to view or edit `config.json`/`permissions.json`.

### **Step 5: Monitor Server Health**
- The GUI will automatically monitor:
  - **CPU/RAM Usage** (real-time updates).
  - **Player Count** (from server logs).
  - **Server Uptime** (since last start).
- If the server becomes unresponsive, the **"Health Monitor"** will automatically **restart it** after 5 failed ping attempts.

---

## **4. Troubleshooting Common Issues**

### **A. Missing Files After First Launch**
- **Cause**: You forgot to click the **"Update Server"** button.
- **Fix**: Navigate to the **"Server Maintenance"** tab and click **"Update Server"**.

### **B. "Downloader Not Found" Error**
- **Cause**: The `hytale-downloader-windows-amd64.exe` is not in the same directory as the script.
- **Fix**: Place the downloader in the same folder as the script and rerun the update.

### **C. Server Fails to Start**
- **Cause**: Missing or corrupted server files.
- **Fix**:
  1. Click **"Update Server"** to redownload files.
  2. Check the **"Update Log"** for errors.
  3. Ensure Java is installed and accessible.

---

## **5. Additional Notes**
- **No Admin Permissions Required**: The script runs as a standard user.
- **Minimize to Tray**: Click the **"System Tray"** icon (bottom-right corner) to minimize the GUI.
- **Auto-Restart Server**: Enable the **"Auto-restart server after update"** checkbox in the **"Server Maintenance"** tab.

---

## **6. Summary of Workflow**
1. **Run the script** with PowerShell.
2. **Update the server** manually via the **"Update Server"** button.
3. **Start the server** using the **"Start Server"** button.
4. **Monitor logs**, configure settings, and manage the server via the GUI.


<img width="1180" height="638" alt="{88D7501D-2B5F-4556-991A-7E951DD44F7B}" src="https://github.com/user-attachments/assets/8576a157-09eb-4da3-b7db-5dfbf3a2c8ce" />

<img width="1179" height="406" alt="{09CD1A69-6DFA-49E5-BB4C-7D1D47407508}" src="https://github.com/user-attachments/assets/09f84596-3c2b-4ef1-9857-2838d853754d" />

<img width="1179" height="638" alt="{ADFB9C6D-579B-4EE5-B075-F6AB4304B27F}" src="https://github.com/user-attachments/assets/428f6def-99b5-4ed3-a4ad-83a2bf5f0e24" />



