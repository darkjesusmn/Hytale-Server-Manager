# ==========================================================================================
# Hytale Server Manager GUI - Version 2.2
# ==========================================================================================
# Made with AI CCode From ChatGPT, Claude AI, Ollama LLMs and the github AI 
# ZERO CODE WAS MADE BY A HUMAN, only configured text, and made prompts for AI to work with.
#
# ============================================================================
#   ___ ___ _____.___.___________ _____   .____     ___________
#  /   |   \\__  |   |\__    ___//  _  \  |    |    \_   _____/
# /    ~    \/   |   |  |    |  /  /_\  \ |    |     |    __)_
# \    Y    /\____   |  |    | /    |    \|    |___  |        \
#  \___|_  / / ______|  |____| \____|__  /|_______ \/_______  /
#        \/  \/                        \/         \/        \/
#
#   ______________________________ ____   _________________________
#  /   _____/\_   _____/\______   \\   \ /   /\_   _____/\______   \
#  \_____  \  |    __)_  |       _/ \   Y   /  |    __)_  |       _/
#  /        \ |        \ |    |   \  \     /   |        \ |    |   \
# /_______  //_______  / |____|_  /   \___/   /_______  / |____|_  /
#         \/         \/         \/                    \/         \/
#
#    _____      _____    _______      _____     ________ _____________________
#   /     \    /  _  \   \      \    /  _  \   /  _____/ \_   _____/\______   \
#  /  \ /  \  /  /_\  \  /   |   \  /  /_\  \ /   \  ___  |    __)_  |       _/
# /    Y    \/    |    \/    |    \/    |    \\    \_\  \ |        \ |    |   \
# \____|__  /\____|__  /\____|__  /\____|__  / \______  //_______  / |____|_  /
#         \/         \/         \/         \/         \/         \/         \/
# ============================================================================

# IMPORTANT NOTES:
# - Must be run with **Windows PowerShell**, not PowerShell Core
# - GUI components require the script to run in **STA (Single-Threaded Apartment)** mode
# - This script should be saved and executed from the Hytale server directory so that
#   $PSScriptRoot correctly resolves relative paths to server files
# ==========================================================================================


# ==========================================================================================
# SECTION: NATIVE WINDOWS API IMPORTS
# ==========================================================================================
# This block injects a small C# class into the PowerShell runtime that allows us to call
# native Win32 API functions. These are used specifically to hide the PowerShell console
# window when the GUI launches.
#
# - kernel32.dll:GetConsoleWindow() retrieves the handle of the current console window
# - user32.dll:ShowWindow() changes the visibility state of a window
# ==========================================================================================

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    // Retrieves a handle (HWND) to the current console window
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    // Shows or hides a window based on the nCmdShow flag
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@


# ==========================================================================================
# SECTION: CONSOLE WINDOW VISIBILITY CONTROL
# ==========================================================================================
# These constants are standard Win32 values:
# - 0 = SW_HIDE  (hide the window)
# - 5 = SW_SHOW (show the window)
#
# The console window is hidden to provide a clean GUI-only experience for the user.
# ==========================================================================================

# Constants: 0 = hide, 5 = show
$consolePtr = [Win32]::GetConsoleWindow()     # Step 1: Obtain handle to the current PowerShell console
[Win32]::ShowWindow($consolePtr, 0)           # Step 2: Hide the console window using SW_HIDE


# ==========================================================================================
# SECTION: .NET ASSEMBLY LOADING (GUI DEPENDENCIES)
# ==========================================================================================
# These assemblies are required to build and display the Windows Forms GUI.
#
# System.Windows.Forms:
#   - Provides Form, Button, Label, TextBox, Timer, NotifyIcon, etc.
#
# System.Drawing:
#   - Provides Font, Color, Size, Point, Icon, and other graphics-related classes
# ==========================================================================================

# Add System.Windows.Forms to allow creation of GUI elements like forms, buttons, labels, textboxes, etc.
Add-Type -AssemblyName System.Windows.Forms

# Add System.Drawing to allow colors, fonts, and other graphical manipulations for the GUI
Add-Type -AssemblyName System.Drawing

# Add System.Web for URL encoding (CurseForge API integration)
Add-Type -AssemblyName System.Web

# ==========================================================================================
# SECTION: GLOBAL VARIABLES
# ==========================================================================================
# These variables are declared at the script scope so they can be accessed and modified
# across multiple functions, event handlers, and timers throughout the application.
#
# The use of `$script:` ensures the variables persist for the lifetime of the script and
# are not limited to local scopes.
# ==========================================================================================


# ------------------------------------------------------------------------------------------
# SERVER PROCESS STATE
# ------------------------------------------------------------------------------------------

# Stores the Process object of the running server
# Used to start, stop, monitor, and collect output from the server process
$script:serverProcess = $null

# Boolean flag indicating whether the server is currently running
# Used by UI logic to enable/disable buttons and prevent duplicate starts
$script:serverRunning = $false


# ------------------------------------------------------------------------------------------
# FILE PATH CONFIGURATION
# ------------------------------------------------------------------------------------------
# All paths are resolved relative to $PSScriptRoot to ensure portability and correctness
# regardless of where the script is launched from.

# Path to the Hytale server JAR file
$script:jarPath = Join-Path $PSScriptRoot "HytaleServer.jar"

# Path to the main server configuration file
$script:configPath = Join-Path $PSScriptRoot "config.json"

# Path to the server permissions file
$script:permissionsPath = Join-Path $PSScriptRoot "permissions.json"

# Path to the latest server log file
# This file is monitored in real-time for output and status updates
$script:logFilePath = Join-Path $PSScriptRoot "logs\latest.log"

# Path to the Hytale downloader executable
# Used to download or update server files
$script:downloaderPath = Join-Path $PSScriptRoot "hytale-downloader-windows-amd64.exe"

# Path to the GUI/application settings file
# Stores user preferences such as RAM allocation and UI state
$script:settingsPath = Join-Path $PSScriptRoot "hsm_settings.json"


# ------------------------------------------------------------------------------------------
# LOGGING & MONITORING INFRASTRUCTURE
# ------------------------------------------------------------------------------------------

# Timer responsible for periodically polling the log file
# Also used for updating CPU and RAM usage in the GUI
$script:logTimer = $null

# Tracks the last known size of the log file in bytes
# Allows incremental reading so only new log lines are processed
$script:lastLogSize = 0


# ------------------------------------------------------------------------------------------
# MEMORY ALLOCATION SETTINGS
# ------------------------------------------------------------------------------------------

# Minimum amount of RAM (in GB) allocated to the Java server process
$script:minRamGB = 4

# Maximum amount of RAM (in GB) allocated to the Java server process
$script:maxRamGB = 16


# ------------------------------------------------------------------------------------------
# EVENT REGISTRATION HANDLES
# ------------------------------------------------------------------------------------------
# These variables store event registration objects so they can be cleanly unregistered
# during shutdown or restart to prevent memory leaks and duplicate event firing.

$script:serverOutReg = $null            # STDOUT event registration for the server process
$script:serverErrReg = $null            # STDERR event registration for the server process
$script:logWatcherRegistration = $null  # FileSystemWatcher event registration
$script:logWatcher = $null              # FileSystemWatcher instance
$script:logFallbackTimer = $null        # Backup timer for log polling
$script:statsTimer = $null              # Timer for CPU/RAM stats updates
$script:cpuCounter = $null              # PerformanceCounter for server CPU usage
$script:systemCpuCounter = $null        # PerformanceCounter for total system CPU usage


# ------------------------------------------------------------------------------------------
# COMMAND HISTORY MANAGEMENT
# ------------------------------------------------------------------------------------------
# Stores previously entered server console commands so the user can navigate
# through them using keyboard shortcuts (e.g., up/down arrows)

$script:commandHistory = @()            # Array holding command history strings
$script:commandHistoryIndex = -1         # Current index within the command history array


# ------------------------------------------------------------------------------------------
# SERVER RUNTIME METRICS
# ------------------------------------------------------------------------------------------

# Timestamp captured when the server starts
# Used to calculate and display server uptime
$script:serverStartTime = $null

# ------------------------------------------------------------------------------------------
# PLAYER TRACKING
# ------------------------------------------------------------------------------------------

# Tracks the current number of players on the server
$script:playerCount = 0

# ------------------------------------------------------------------------------------------
# SYSTEM TRAY INTEGRATION
# ------------------------------------------------------------------------------------------

# NotifyIcon object used to place the application in the Windows system tray
# Enables minimize-to-tray behavior and background operation
$script:notifyIcon = $null

# ------------------------------------------------------------------------------------------
# SERVER HEALTH MONITORING
# ------------------------------------------------------------------------------------------

# Timer for periodic server health checks
$script:healthMonitorTimer = $null

# Tracks consecutive ping failures
$script:pingFailCount = 0

# Stores the last successful ping response time
$script:lastPingTime = $null

# ------------------------------------------------------------------------------------------
# MOD MANAGER PATHS
# ------------------------------------------------------------------------------------------

# Path to the mods folder where active mods are stored
$script:modsPath = Join-Path $PSScriptRoot "mods"

# Path to the disabled mods folder
$script:modsDisabledPath = Join-Path $PSScriptRoot "mods_disabled"

# Global variable to store the mod list view control
$script:modListView = $null

# ------------------------------------------------------------------------------------------
# CURSEFORGE API INTEGRATION
# ------------------------------------------------------------------------------------------

# CurseForge API Key
$script:curseForgeApiKey = '$2a$10$OAqNZqZBBGveZ8SnmJ4d6.FeLQMtC0DdkrLOSGA3RJjH1vPjWPKaK'

# CurseForge API Base URL
$script:curseForgeApiBase = 'https://api.curseforge.com/v1'

# Hytale Game ID on CurseForge
$script:hytaleGameId = 70216

# Hytale Mods Class ID
$script:hytaleModsClassId = 9137

# Path to CurseForge metadata file
$script:cfMetadataPath = Join-Path $PSScriptRoot "cf_mod_metadata.json"

# In-memory cache of CurseForge metadata
$script:cfMetadata = @{}


# ==========================================================================================
# SECTION: DARK MODE COLOR DEFINITIONS
# ==========================================================================================
# This section defines all color values used throughout the GUI when operating in dark mode.
# Centralizing color definitions here makes it easy to:
#   - Adjust the overall theme
#   - Maintain visual consistency
#   - Debug UI rendering issues related to visibility or contrast
#
# All colors are defined using System.Drawing.Color and, where applicable, ARGB values.
# ARGB format = (Alpha, Red, Green, Blue)
# ==========================================================================================


# ------------------------------------------------------------------------------------------
# MAIN WINDOW BACKGROUND
# ------------------------------------------------------------------------------------------
# Defines the background color of the primary application window (Form).
# A very dark gray is used instead of pure black to reduce eye strain.
$colorBack = [System.Drawing.Color]::FromArgb(30,30,30)


# ------------------------------------------------------------------------------------------
# DEFAULT TEXT COLOR
# ------------------------------------------------------------------------------------------
# Standard foreground color for labels and static text elements.
# White provides maximum contrast against the dark background.
$colorText = [System.Drawing.Color]::White


# ------------------------------------------------------------------------------------------
# TEXTBOX BACKGROUND COLOR
# ------------------------------------------------------------------------------------------
# Background color used for input fields such as textboxes.
# Slightly lighter than the main background to visually separate input areas.
$colorTextboxBack = [System.Drawing.Color]::FromArgb(50,50,50)


# ------------------------------------------------------------------------------------------
# TEXTBOX TEXT COLOR
# ------------------------------------------------------------------------------------------
# Foreground color for text entered into textboxes.
# White ensures readability against the darker textbox background.
$colorTextboxText = [System.Drawing.Color]::White


# ------------------------------------------------------------------------------------------
# BUTTON BACKGROUND COLOR
# ------------------------------------------------------------------------------------------
# Default background color for buttons.
# A mid-dark gray is used to distinguish buttons from both the background and textboxes.
$colorButtonBack = [System.Drawing.Color]::FromArgb(70,70,70)


# ------------------------------------------------------------------------------------------
# BUTTON TEXT COLOR
# ------------------------------------------------------------------------------------------
# Foreground color for button captions.
# White maintains consistent contrast and readability.
$colorButtonText = [System.Drawing.Color]::White


# ------------------------------------------------------------------------------------------
# SERVER CONSOLE BACKGROUND COLOR
# ------------------------------------------------------------------------------------------
# Background color for the server console output textbox.
# Pure black mimics a traditional terminal appearance.
$colorConsoleBack = [System.Drawing.Color]::Black


# ------------------------------------------------------------------------------------------
# SERVER CONSOLE TEXT COLOR
# ------------------------------------------------------------------------------------------
# Foreground color for server log output displayed in the console.
# LightGreen is commonly associated with terminal output and improves log readability.
$colorConsoleText = [System.Drawing.Color]::LightGreen

# ------------------------------------------------------------------------------------------
# THEME SWITCHER VARIABLES
# ------------------------------------------------------------------------------------------

# Current active theme
$script:currentTheme = "Dark"

# Available theme presets
$script:themes = @{
    "Dark" = @{
        Back = [System.Drawing.Color]::FromArgb(30,30,30)
        Text = [System.Drawing.Color]::White
        TextboxBack = [System.Drawing.Color]::FromArgb(50,50,50)
        TextboxText = [System.Drawing.Color]::White
        ButtonBack = [System.Drawing.Color]::FromArgb(70,70,70)
        ButtonText = [System.Drawing.Color]::White
        ConsoleBack = [System.Drawing.Color]::Black
        ConsoleText = [System.Drawing.Color]::LimeGreen
    }
    "Light" = @{
        Back = [System.Drawing.Color]::FromArgb(240,240,240)
        Text = [System.Drawing.Color]::Black
        TextboxBack = [System.Drawing.Color]::White
        TextboxText = [System.Drawing.Color]::Black
        ButtonBack = [System.Drawing.Color]::FromArgb(200,200,200)
        ButtonText = [System.Drawing.Color]::Black
        ConsoleBack = [System.Drawing.Color]::White
        ConsoleText = [System.Drawing.Color]::DarkGreen
    }
    "Blue" = @{
        Back = [System.Drawing.Color]::FromArgb(20,30,50)
        Text = [System.Drawing.Color]::White
        TextboxBack = [System.Drawing.Color]::FromArgb(30,50,80)
        TextboxText = [System.Drawing.Color]::White
        ButtonBack = [System.Drawing.Color]::FromArgb(50,80,120)
        ButtonText = [System.Drawing.Color]::White
        ConsoleBack = [System.Drawing.Color]::FromArgb(10,15,25)
        ConsoleText = [System.Drawing.Color]::Cyan
    }
    "Purple" = @{
        Back = [System.Drawing.Color]::FromArgb(40,20,50)
        Text = [System.Drawing.Color]::White
        TextboxBack = [System.Drawing.Color]::FromArgb(60,40,80)
        TextboxText = [System.Drawing.Color]::White
        ButtonBack = [System.Drawing.Color]::FromArgb(80,50,100)
        ButtonText = [System.Drawing.Color]::White
        ConsoleBack = [System.Drawing.Color]::FromArgb(20,10,30)
        ConsoleText = [System.Drawing.Color]::Magenta
    }
}

# =====================
# FUNCTIONS
# =====================
# This section contains reusable helper functions that encapsulate common logic
# used throughout the GUI. Grouping logic into functions improves readability,
# consistency, and long-term maintainability.


# =====================
# Function: Style-Button
# =====================
# PURPOSE:
# Applies a standardized dark-mode visual style to a Windows Forms Button control.
# This ensures all buttons in the GUI have a consistent look and feel.
#
# WHY THIS EXISTS:
# - Prevents duplicated styling code across the UI
# - Makes global visual changes easier (edit once, affects all buttons)
# - Improves readability and debugging of UI-related logic
#
# PARAMETERS:
# - $btn ([System.Windows.Forms.Button])
#   The button control instance that will receive the styling.
#
# OPERATION FLOW:
# Step 1: Set the button background color
# Step 2: Set the button text (foreground) color
# Step 3: Force the button to use a flat visual style
# Step 4: Customize the flat button border color
# =====================
function Style-Button {
    # Define the expected parameter type to ensure only Button controls are passed in
    param([System.Windows.Forms.Button]$btn)

    # Step 1:
    # Apply the predefined dark-mode background color for buttons
    $btn.BackColor = $colorButtonBack

    # Step 2:
    # Apply the predefined text color for button captions
    $btn.ForeColor = $colorButtonText

    # Step 3:
    # Set the button style to Flat for a modern, minimal dark-mode appearance
    # This disables the default 3D button rendering
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    # Step 4:
    # Customize the border color of the flat-style button
    # A subtle gray border helps the button stand out against the dark background
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(100,100,100)
}

# =====================
# Function: Format-Uptime
# =====================
# PURPOSE:
# Converts a server start DateTime into a human-readable uptime string.
# This is used for displaying server uptime in the GUI in a clean format.
#
# WHY THIS EXISTS:
# - Raw DateTime/TimeSpan values are not user-friendly
# - Provides consistent uptime formatting across the application
# - Safely handles cases where the server has not started yet
#
# PARAMETERS:
# - $startTime ([DateTime])
#   The DateTime value representing when the server was started.
#
# RETURN VALUE:
# - "N/A" if no start time is available
# - "Dd HH:MM:SS" if uptime is greater than one day
# - "HH:MM:SS" if uptime is less than one day
#
# OPERATION FLOW:
# Step 1: Validate the start time
# Step 2: Calculate elapsed runtime
# Step 3: Choose formatting based on number of days
# Step 4: Return formatted uptime string
# =====================
function Format-Uptime {
    # Accepts the server start time as a DateTime object
    param([DateTime]$startTime)

    # Step 1:
    # If the start time is null or empty, the server is not running
    # Return "N/A" to indicate uptime is unavailable
    if (-not $startTime) { return "N/A" }

    # Step 2:
    # Calculate the elapsed time between now and when the server started
    # The result is a TimeSpan object
    $ts = (Get-Date) - $startTime

    # Step 3:
    # If the server has been running for more than 1 day,
    # include the day count in the formatted output
    if ($ts.Days -gt 0) {

        # Step 4a:
        # Format uptime including days
        # Example: "3d 12:45:09"
        return ("{0}d {1:00}:{2:00}:{3:00}" -f $ts.Days, $ts.Hours, $ts.Minutes, $ts.Seconds)
    } else {

        # Step 4b:
        # Format uptime without days
        # Example: "12:45:09"
        return ("{0:00}:{1:00}:{2:00}" -f $ts.Hours, $ts.Minutes, $ts.Seconds)
    }
}

# =====================
# Function: Clear-Console
# =====================
# PURPOSE:
# Clears all text from the main server console output textbox in the GUI.
# This is typically used when resetting the UI, restarting the server,
# or when the user manually requests a clean console view.
#
# WHY THIS EXISTS:
# - Encapsulates console-clearing logic in one place
# - Prevents duplicated UI manipulation code
# - Safely handles cases where the textbox may not yet exist or is disposed
#
# DEPENDENCIES:
# - Relies on $txtConsole being a valid System.Windows.Forms.TextBox control
#
# OPERATION FLOW:
# Step 1: Attempt to clear the console textbox contents
# Step 2: Silently ignore any errors to prevent UI crashes
# =====================
function Clear-Console {
    # Attempt to clear all text from the console textbox
    # Wrapped in a try/catch to prevent exceptions if the control
    # is null, not initialized yet, or already disposed
    try { $txtConsole.Clear() } catch {}
}

# =====================
# Function: Save-ConsoleToFile
# =====================
# PURPOSE:
# Allows the user to save the contents of the main server console textbox
# to a text file on disk using a standard Windows Save File dialog.
#
# WHY THIS EXISTS:
# - Enables exporting server logs or console output for debugging
# - Provides an easy way for users to share logs or archive output
# - Uses familiar Windows UI patterns for file selection
#
# DEPENDENCIES:
# - $txtConsole must be a valid System.Windows.Forms.TextBox control
# - System.Windows.Forms must be loaded
#
# OPERATION FLOW:
# Step 1: Create a SaveFileDialog instance
# Step 2: Configure file filter and default filename
# Step 3: Display the dialog and wait for user confirmation
# Step 4: Write console text to the selected file path
# Step 5: Handle and report any errors that occur
# =====================
function Save-ConsoleToFile {
    try {
        # Step 1:
        # Create a new SaveFileDialog object to prompt the user for a file location
        $sfd = New-Object System.Windows.Forms.SaveFileDialog

        # Step 2:
        # Define allowed file types in the dialog
        # Default option is a .txt file, but all files can be selected if desired
        $sfd.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"

        # Step 3:
        # Set the default filename that appears in the dialog
        $sfd.FileName = "console_log.txt"

        # Step 4:
        # Show the dialog and check if the user clicked OK
        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {

            # Step 5:
            # Write the entire contents of the console textbox to the chosen file
            # UTF8 encoding is used for compatibility and readability
            $txtConsole.Text | Out-File -FilePath $sfd.FileName -Encoding UTF8
        }
    } catch {
        # ERROR HANDLING:
        # If any exception occurs (dialog failure, IO error, etc.),
        # display a message box to inform the user of the failure
        [System.Windows.Forms.MessageBox]::Show("Failed to save file: $_", "Error")
    }
}

# =====================
# Function: Copy-ConsoleToClipboard
# =====================
# PURPOSE:
# Copies the entire contents of the main server console textbox to the
# Windows clipboard so it can be pasted into other applications.
#
# WHY THIS EXISTS:
# - Makes it easy to quickly share server output
# - Useful for debugging, support requests, or log inspection
# - Avoids the need to manually select and copy large amounts of text
#
# DEPENDENCIES:
# - $txtConsole must be a valid System.Windows.Forms.TextBox control
# - System.Windows.Forms.Clipboard must be available
#
# OPERATION FLOW:
# Step 1: Verify the console contains text
# Step 2: Copy console text to the system clipboard
# Step 3: Silently handle any clipboard-related errors
# =====================
function Copy-ConsoleToClipboard {
    try {
        # Step 1:
        # Check if the console textbox contains any text
        # Prevents copying empty content to the clipboard
        if ($txtConsole.Text.Length -gt 0) {

            # Step 2:
            # Place the console text onto the Windows clipboard
            [System.Windows.Forms.Clipboard]::SetText($txtConsole.Text)
        }
    } catch {
        # ERROR HANDLING:
        # Clipboard access can fail if another application has it locked
        # Errors are intentionally ignored to avoid interrupting the UI
    }
}

# =====================
# Function: Clear-UpdateLog
# =====================
# PURPOSE:
# Clears all text from the update log textbox in the GUI.
# This is typically used when resetting update status output
# or preparing the UI for a new update/download operation.
#
# WHY THIS EXISTS:
# - Keeps update-related output separate from the main console
# - Provides a quick way to reset the update log display
# - Prevents duplicated textbox-clearing logic elsewhere in the code
#
# DEPENDENCIES:
# - $txtUpdateLog must be a valid System.Windows.Forms.TextBox control
#
# OPERATION FLOW:
# Step 1: Attempt to clear the update log textbox contents
# Step 2: Suppress any errors to avoid UI interruptions
# =====================
function Clear-UpdateLog {
    # Attempt to clear all text from the update log textbox
    # Wrapped in a try/catch to safely handle cases where the control
    # may not yet be initialized or has already been disposed
    try { $txtUpdateLog.Clear() } catch {}
}

# =====================
# Function: Save-UpdateLogToFile
# =====================
# PURPOSE:
# Allows the user to save the contents of the update log textbox to a file
# on disk using a standard Windows Save File dialog.
#
# WHY THIS EXISTS:
# - Enables exporting update logs for debugging, record-keeping, or sharing
# - Provides a user-friendly interface for file selection
# - Keeps update log management separate from the main console
#
# DEPENDENCIES:
# - $txtUpdateLog must be a valid System.Windows.Forms.TextBox control
# - System.Windows.Forms must be loaded
#
# OPERATION FLOW:
# Step 1: Create a SaveFileDialog instance
# Step 2: Set file type filter and default filename
# Step 3: Display the dialog and wait for user confirmation
# Step 4: Write the update log contents to the selected file path
# Step 5: Handle and report any errors during file saving
# =====================
function Save-UpdateLogToFile {
    try {
        # Step 1:
        # Initialize a new SaveFileDialog object for user file selection
        $sfd = New-Object System.Windows.Forms.SaveFileDialog

        # Step 2:
        # Restrict file selection to text files or all files
        $sfd.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"

        # Step 2b:
        # Set the default filename that will appear in the dialog
        $sfd.FileName = "update_log.txt"

        # Step 3:
        # Show the dialog; proceed only if the user clicks OK
        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {

            # Step 4:
            # Output the entire contents of the update log textbox to the chosen file
            # UTF8 encoding ensures compatibility with most text editors
            $txtUpdateLog.Text | Out-File -FilePath $sfd.FileName -Encoding UTF8
        }
    } catch {
        # Step 5: ERROR HANDLING
        # Display an error message box if saving fails for any reason
        [System.Windows.Forms.MessageBox]::Show("Failed to save file: $_", "Error")
    }
}

# =====================
# Function: Copy-UpdateLogToClipboard
# =====================
# PURPOSE:
# Copies the contents of the update log textbox to the Windows clipboard,
# allowing the user to paste it into other applications for sharing or analysis.
#
# WHY THIS EXISTS:
# - Facilitates quick sharing of update logs without saving a file
# - Supports troubleshooting and debugging by copying log output easily
# - Keeps update log clipboard operations separate from the main console
#
# DEPENDENCIES:
# - $txtUpdateLog must be a valid System.Windows.Forms.TextBox control
# - System.Windows.Forms.Clipboard must be available
#
# OPERATION FLOW:
# Step 1: Check if the update log textbox contains any text
# Step 2: If text exists, copy it to the clipboard
# Step 3: Silently ignore any exceptions (e.g., clipboard access issues)
# =====================
function Copy-UpdateLogToClipboard {
    try {
        # Step 1:
        # Ensure there is content to copy
        if ($txtUpdateLog.Text.Length -gt 0) {

            # Step 2:
            # Place the update log text onto the Windows clipboard
            [System.Windows.Forms.Clipboard]::SetText($txtUpdateLog.Text)
        }
    } catch {}
}

# =====================
# Function: Save-Settings
# =====================
# PURPOSE:
# Saves the current GUI window state and last selected tab to a JSON settings file.
# This allows the application to restore the window size, position, and selected tab
# the next time it is launched.
#
# WHY THIS EXISTS:
# - Improves user experience by remembering window layout and tab selection
# - Centralizes persistence logic into one function for maintainability
# - Stores settings in a human-readable and editable JSON file
#
# DEPENDENCIES:
# - $form must be a valid System.Windows.Forms.Form object
# - $tabs must be a valid tab control with a SelectedIndex property
# - $script:settingsPath must be a valid path for writing the settings JSON
#
# OPERATION FLOW:
# Step 1: Create a custom object representing window bounds and last selected tab
# Step 2: Convert the object to JSON with sufficient depth
# Step 3: Write the JSON to the settings file using UTF8 encoding
# Step 4: Silently handle any errors (e.g., file write permissions)
# =====================
function Save-Settings {
    try {
        # Step 1:
        # Build a PSObject capturing the current window and tab state
        $obj = [PSCustomObject]@{
            Width = $form.Width
            Height = $form.Height
            Left = $form.Left
            Top = $form.Top
            WindowState = $form.WindowState.ToString()
            LastTab = $tabs.SelectedIndex
        }

        # Step 2 & 3:
        # Convert the object to JSON and save to the settings file
        $obj | ConvertTo-Json -Depth 4 | Set-Content -Path $script:settingsPath -Encoding UTF8
    } catch {}
}

# =====================
# Function: Load-Settings
# =====================
# PURPOSE:
# Restores the GUI window size, position, window state, and last selected tab
# from the JSON settings file previously saved by Save-Settings.
#
# WHY THIS EXISTS:
# - Enhances user experience by preserving the last window layout
# - Ensures consistency between application launches
# - Encapsulates all settings restoration logic in one function
#
# DEPENDENCIES:
# - $form must be a valid System.Windows.Forms.Form object
# - $tabs must be a valid tab control
# - $script:settingsPath must point to a readable JSON settings file
#
# OPERATION FLOW:
# Step 1: Check if the settings file exists; exit if not
# Step 2: Read and parse the JSON settings file
# Step 3: Restore window size if width and height are valid
# Step 4: Restore window position if Left and Top are present
# Step 5: Restore window state (normal, minimized, maximized) safely
# Step 6: Restore last selected tab index if valid
# Step 7: Silently handle any errors to avoid crashing the GUI
# =====================
function Load-Settings {
    try {
        # Step 1:
        # Exit early if the settings file does not exist
        if (-not (Test-Path $script:settingsPath)) { return }

        # Step 2:
        # Read the entire file and convert JSON to a PSObject
        $json = Get-Content $script:settingsPath -Raw | ConvertFrom-Json

        # Step 3:
        # Restore window size if Width and Height are defined and reasonable
        if ($json.Width -and $json.Height) {
            # Basic sanity checks to avoid extremely small windows
            if ($json.Width -gt 200 -and $json.Height -gt 200) {
                $form.Size = New-Object System.Drawing.Size([int]$json.Width, [int]$json.Height)
            }
        }

        # Step 4:
        # Restore window position if Left and Top values exist
        if ($json.Left -ne $null -and $json.Top -ne $null) {
            $form.StartPosition = "Manual"
            $form.Location = New-Object System.Drawing.Point([int]$json.Left, [int]$json.Top)
        }

        # Step 5:
        # Restore window state safely (Normal, Minimized, Maximized)
        if ($json.WindowState) {
            try { 
                $form.WindowState = [System.Windows.Forms.FormWindowState]::Parse([string]$json.WindowState) 
            } catch {}
        }

        # Step 6:
        # Restore last selected tab if the index is valid
        if ($json.LastTab -ne $null) {
            $idx = [int]$json.LastTab
            if ($idx -ge 0 -and $idx -lt $tabs.TabCount) { $tabs.SelectedIndex = $idx }
        }

    } catch {}
}

# =====================
# Function: Add-ToCommandHistory
# =====================
# PURPOSE:
# Adds a new server console command to the command history array,
# ensuring that consecutive duplicate commands are not stored.
# This allows users to navigate previous commands efficiently using
# keyboard shortcuts like up/down arrows.
#
# WHY THIS EXISTS:
# - Maintains a persistent in-session command history
# - Prevents clutter from repeated identical commands
# - Provides a mechanism to track and navigate previous console inputs
#
# PARAMETERS:
# - $command ([string])
#   The console command string to be added to history
#
# OPERATION FLOW:
# Step 1: Ignore empty or whitespace-only commands
# Step 2: Add the command to history only if the last command differs
# Step 3: Update the history index to point to the end of the array
# =====================
function Add-ToCommandHistory {
    param([string]$command)

    # Step 1:
    # Ignore null, empty, or whitespace-only commands
    if ([string]::IsNullOrWhiteSpace($command)) { return }

    # Step 2:
    # Only add the command if it's the first one or differs from the previous command
    if ($script:commandHistory.Count -eq 0 -or $script:commandHistory[-1] -ne $command) {
        $script:commandHistory += $command
    }

    # Step 3:
    # Reset the command history index to the end to prepare for new navigation
    $script:commandHistoryIndex = $script:commandHistory.Count
}

# =====================
# Function: Create-TrayIcon
# =====================
# PURPOSE:
# Initializes the system tray icon (NotifyIcon) for the application and attaches
# a context menu with "Show" and "Exit" options. Supports double-click to restore
# the main window.
#
# WHY THIS EXISTS:
# - Enables minimize-to-tray functionality for background operation
# - Provides quick access to show the GUI or exit the application
# - Encapsulates tray icon setup and event handling in one reusable function
#
# DEPENDENCIES:
# - $form must be a valid System.Windows.Forms.Form object
# - System.Windows.Forms must be loaded
# - $script:notifyIcon stores the tray icon instance
#
# OPERATION FLOW:
# Step 1: Exit if a tray icon already exists
# Step 2: Create context menu with "Show" and "Exit" items
# Step 3: Initialize NotifyIcon with tooltip text, icon, and context menu
# Step 4: Make the tray icon visible
# Step 5: Attach event handlers:
#         - Show menu item click restores and brings the window to front
#         - Exit menu item click closes the application
#         - Double-click on the tray icon restores the window
# Step 6: Wrap all steps in try/catch to prevent unhandled exceptions
# =====================
function Create-TrayIcon {
    try {
        # Step 1:
        # Prevent creating multiple tray icons
        if ($script:notifyIcon) { return }

        # Step 2:
        # Create context menu for tray icon
        $contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
        $miShow = New-Object System.Windows.Forms.ToolStripMenuItem("Show")
        $miExit = New-Object System.Windows.Forms.ToolStripMenuItem("Exit")

        # Add menu items to the context menu
        $contextMenu.Items.Add($miShow) | Out-Null
        $contextMenu.Items.Add($miExit) | Out-Null

        # Step 3:
        # Create the NotifyIcon object and configure its properties
        $script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $script:notifyIcon.Text = "Hytale Server Manager"                   # Tooltip text
        $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application  # Default application icon
        $script:notifyIcon.ContextMenuStrip = $contextMenu                   # Attach context menu

        # Step 4:
        # Make the tray icon visible in the Windows system tray
        $script:notifyIcon.Visible = $true

        # Step 5a:
        # Event handler for "Show" menu item: restores the window
        $miShow.Add_Click({
            try {
                $form.Invoke([action]{
                    $form.Show()
                    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
                    $form.BringToFront()
                    $form.Activate()
                })
            } catch {}
        })

        # Step 5b:
        # Event handler for "Exit" menu item: closes the application
        $miExit.Add_Click({
            try { $form.Close() } catch {}
        })

        # Step 5c:
        # Event handler for double-clicking the tray icon: restore the window
        $script:notifyIcon.Add_MouseDoubleClick({
            try {
                $form.Invoke([action]{
                    $form.Show()
                    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
                    $form.BringToFront()
                    $form.Activate()
                })
            } catch {}
        })

    } catch {}
}

# =====================
# Function: Run-DownloaderAndCapture
# =====================
# PURPOSE:
# Executes the Hytale downloader with specified arguments and captures its output,
# returning a trimmed string suitable for parsing (e.g., version numbers or status messages).
#
# WHY THIS EXISTS:
# - Provides a wrapper around Run-DownloaderCommand that returns output for processing
# - Ensures output is consistently trimmed to avoid whitespace issues
# - Centralizes handling of downloader output for version checks or status reporting
#
# PARAMETERS:
# - $arguments ([string])
#   Command-line arguments to pass to the downloader executable
# - $description ([string], optional)
#   Text describing the operation for logging purposes (default: "Run downloader")
#
# RETURN VALUE:
# - Trimmed string output from the downloader command
# - $null if no output was returned
#
# OPERATION FLOW:
# Step 1: Call Run-DownloaderCommand with the provided arguments and description
# Step 2: If output exists, trim leading/trailing whitespace and return it
# Step 3: Return $null if there was no output
# =====================
function Run-DownloaderAndCapture {
    param([string]$arguments, [string]$description = "Run downloader")

    # Step 1:
    # Execute the downloader command and capture its output
    $output = Run-DownloaderCommand $arguments $description

    # Step 2:
    # Return trimmed output if available
    if ($output -ne $null) { return $output.Trim() }

    # Step 3:
    # Return $null if the command produced no output
    return $null
}

# =====================
# Function: Check-ServerFiles
# =====================
# PURPOSE:
# Validates the presence of required Hytale server files and directories,
# updates GUI labels for individual items, and provides an overall status
# indicator both in the GUI and the console.
#
# WHY THIS EXISTS:
# - Ensures the server has all necessary files before starting
# - Provides immediate visual feedback in the GUI for each required file/folder
# - Updates overall status to help users quickly identify missing components
#
# DEPENDENCIES:
# - GUI labels for each file/folder status ($lblJarStatus, $lblJarFile, etc.)
# - Overall status label ($lblOverallStatus)
# - Main console textbox ($txtConsole)
# - $PSScriptRoot should point to the server directory
#
# OPERATION FLOW:
# Step 1: Define the base server directory
# Step 2: Initialize a flag to track overall file validity
# Step 3: Create an array of required files/directories with their GUI labels
# Step 4: Loop through each item:
#         a) Construct full path
#         b) Check existence (Test-Path for files, -PathType Container for directories)
#         c) Update individual status labels (green [OK] or red [!!])
#         d) Set $allValid to $false if any item is missing
# Step 5: Update overall status label and append message to console
#         - Green "[OK] All required files present" if allValid
#         - Orange "[WARN] Missing required files" if any missing
# =====================
function Check-ServerFiles {

    # Step 1: Directory containing the script and server files
    $serverDir = $PSScriptRoot

    # Step 2: Initialize overall validity flag
    $allValid = $true

    # Step 3: Define required files and directories with associated GUI labels
    $items = @(
        @{Path="HytaleServer.jar"; Status=$lblJarStatus; Label=$lblJarFile; Type="File"; Name="HytaleServer.jar"},
        @{Path="Assets.zip"; Status=$lblAssetsStatus; Label=$lblAssetsFile; Type="File"; Name="Assets.zip"},
        @{Path="Server"; Status=$lblServerFolderStatus; Label=$lblServerFolder; Type="Directory"; Name="Server/"},
        @{Path="mods"; Status=$lblModsFolderStatus; Label=$lblModsFolder; Type="Directory"; Name="mods/"},
        @{Path="config.json"; Status=$lblConfigStatus; Label=$lblConfigFile; Type="File"; Name="config.json"}
    )

    # Step 4: Iterate over each required item to validate existence
    foreach ($item in $items) {
        # Step 4a: Construct the full filesystem path
        $fullPath = Join-Path $serverDir $item.Path

        # Step 4b: Check if the file or directory exists
        $exists = if ($item.Type -eq "File") {
            Test-Path $fullPath
        } else {
            Test-Path $fullPath -PathType Container
        }

        # Step 4c: Update GUI labels based on existence
        if ($exists) {
            # Item found
            $item.Status.Text = "[OK]"                       # Individual status indicator
            $item.Status.ForeColor = [System.Drawing.Color]::LightGreen
            $item.Label.Text = "$($item.Name) - Found"      # Display name with "Found"
            $item.Label.ForeColor = [System.Drawing.Color]::LightGreen
        } else {
            # Item missing
            $item.Status.Text = "[!!]"                       # Warning indicator
            $item.Status.ForeColor = [System.Drawing.Color]::Red
            $item.Label.Text = "$($item.Name) - Missing"    # Display name with "Missing"
            $item.Label.ForeColor = [System.Drawing.Color]::Red
            $allValid = $false                              # Mark overall validation as failed
        }
    }

    # Step 5: Update overall status label and console output
    if ($allValid) {
        # All required files present
        $lblOverallStatus.Text = "[OK] All required files present"
        $lblOverallStatus.ForeColor = [System.Drawing.Color]::LightGreen
        $txtConsole.AppendText("[INFO] All required files present`r`n")
    } else {
        # One or more required files are missing
        $lblOverallStatus.Text = "[WARN] Missing required files"
        $lblOverallStatus.ForeColor = [System.Drawing.Color]::Orange
        $txtConsole.AppendText("[WARN] Missing required files`r`n")
    }
}

# =====================
# Function: Update-CPUAndRAMUsage
# =====================
# PURPOSE:
# Monitors CPU and RAM usage of the running Hytale server process and updates GUI labels.
# If the server process is not running, displays system-wide CPU and RAM statistics.
# Also updates uptime label.
#
# KEY POINTS:
# - Uses per-process PerformanceCounter for server CPU
# - Calculates RAM usage against either max configured RAM or system total
# - Updates colors based on thresholds:
#       Green: <50%, Orange: 50-79%, Red: >=80%
# - Fully wrapped in try/catch to prevent GUI crashes on errors
# =====================
function Update-CPUAndRAMUsage {
    try {
        # -------------------------
        # System-wide CPU stats
        # -------------------------
        if (-not $script:systemCpuCounter) {
            $script:systemCpuCounter = New-Object System.Diagnostics.PerformanceCounter(
                "Processor", "% Processor Time", "_Total", $true
            )
            $null = $script:systemCpuCounter.NextValue()
        }

        Start-Sleep -Milliseconds 200
        $sysCpu = [math]::Round($script:systemCpuCounter.NextValue(), 1)

        # -------------------------
        # System-wide RAM stats
        # -------------------------
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalKB = [double]$os.TotalVisibleMemorySize
        $freeKB  = [double]$os.FreePhysicalMemory
        $usedKB  = $totalKB - $freeKB

        $usedMB  = [math]::Round($usedKB / 1024, 1)
        $totalMB = [math]::Round($totalKB / 1024, 1)

        $memPercent = 0
        if ($totalMB -gt 0) {
            $memPercent = [math]::Round(($usedMB / $totalMB) * 100, 1)
        }

        # -------------------------
        # Update GUI
        # -------------------------
        $lblCPU.Text = "System CPU: ${sysCpu}%"
        $lblRAM.Text = "System RAM: ${usedMB} MB / ${totalMB} MB (${memPercent}%)"
        $lblUptime.Text = "Uptime: $(Format-Uptime $script:serverStartTime)"

        # -------------------------
        # Color thresholds
        # -------------------------
        $lblCPU.ForeColor = if ($sysCpu -ge 80) {
            [System.Drawing.Color]::Red
        } elseif ($sysCpu -ge 50) {
            [System.Drawing.Color]::Orange
        } else {
            [System.Drawing.Color]::LightGreen
        }

        $lblRAM.ForeColor = if ($memPercent -ge 80) {
            [System.Drawing.Color]::Red
        } elseif ($memPercent -ge 50) {
            [System.Drawing.Color]::Orange
        } else {
            [System.Drawing.Color]::LightGreen
        }

    } catch {
        # Optional: swallow errors to avoid GUI crashes
    }
}


# =====================
# Function: Update-PlayerCount
# =====================
# PURPOSE:
# Monitors console output for player join/leave messages and updates the player count.
# Detects patterns like "Player 'Name' joined" and "Removing player 'Name'"
#
# PARAMETERS:
# - $logLine ([string]): A single line of console output to check
#
# OPERATION FLOW:
# Step 1: Check for player join pattern
# Step 2: Check for player leave pattern
# Step 3: Update GUI label with current count
# Step 4: Apply color coding based on player count
# =====================
function Update-PlayerCount {
    param([string]$logLine)
    
    try {
        # Skip empty lines
        if ([string]::IsNullOrWhiteSpace($logLine)) { return }
        
        # Step 1: Detect player join
        if ($logLine -match "Player\s+'([^']+)'\s+joined\s+world") {
            $playerName = $matches[1]
            $script:playerCount++
        }
        
        # Step 2: Detect player leave
        elseif ($logLine -match "Removing\s+player\s+'([^']+)") {
            $playerName = $matches[1].Trim()
            if ($script:playerCount -gt 0) {
                $script:playerCount--
            }
        }
        
        # Step 3: Update GUI label (only if it exists)
        if ($lblServerPing) {
            $lblServerPing.Text = "Players Online: $script:playerCount"
            
            # Step 4: Color coding
            if ($script:playerCount -eq 0) {
                $lblServerPing.ForeColor = [System.Drawing.Color]::Gray
            } elseif ($script:playerCount -le 5) {
                $lblServerPing.ForeColor = [System.Drawing.Color]::LightGreen
            } elseif ($script:playerCount -le 15) {
                $lblServerPing.ForeColor = [System.Drawing.Color]::Yellow
            } else {
                $lblServerPing.ForeColor = [System.Drawing.Color]::Orange
            }
        }
    } catch {
        # Silently ignore errors to prevent crashes
    }
}

# =====================
# Function: Monitor-ServerHealth
# =====================
# PURPOSE:
# Monitors server health by sending /ping commands at regular intervals.
# If the server fails to respond after multiple attempts, automatically restarts it.
#
# OPERATION FLOW:
# Step 1: Check if server is running
# Step 2: Send /ping command to server
# Step 3: Wait for response in console output
# Step 4: If no response after timeout, increment failure counter
# Step 5: After 5 consecutive failures, trigger auto-restart
# Step 6: Reset failure counter on successful ping
# =====================
function Monitor-ServerHealth {
    # Only monitor if server is marked as running
    if (-not $script:serverRunning) {
        $script:pingFailCount = 0
        return
    }

    # Timer for /who command to update player count
    if (-not $script:whoMonitorTimer) {
        $script:whoMonitorTimer = New-Object System.Windows.Forms.Timer
        $script:whoMonitorTimer.Interval = 30000  # 30 seconds
        $script:whoMonitorTimer.Add_Tick({
            if ($script:serverRunning -and $script:serverProcess -and -not $script:serverProcess.HasExited) {
                try {
                    $script:serverProcess.StandardInput.WriteLine("who")
                    Start-Sleep -Milliseconds 500
                
                    $lines = $txtConsole.Text.Split("`n") | Select-Object -Last 20
                    foreach ($line in $lines) {
                        if ($line -match "default \((\d+)\):") {
                            $playerCount = [int]$matches[1]
                            $script:playerCount = $playerCount
                            break
                        }
                    }
                
                    if ($lblServerPing) {
                        $lblServerPing.Text = "Players Online: $script:playerCount"
                        if ($script:playerCount -eq 0) {
                            $lblServerPing.ForeColor = [System.Drawing.Color]::Gray
                        } elseif ($script:playerCount -le 5) {
                            $lblServerPing.ForeColor = [System.Drawing.Color]::LightGreen
                        } elseif ($script:playerCount -le 15) {
                            $lblServerPing.ForeColor = [System.Drawing.Color]::Yellow
                        } else {
                            $lblServerPing.ForeColor = [System.Drawing.Color]::Orange
                        }
                    }
                } catch {
                    # Handle errors silently
                }
            }
        })
        $script:whoMonitorTimer.Start()
    }
}

# =====================
# Function: Start-LogPolling
# =====================
# PURPOSE:
# Continuously monitors the server's latest.log file and updates the UI console(s) in real-time.
# Uses FileSystemWatcher for immediate detection and a fallback Timer for missed events.
#
# KEY POINTS:
# - Prevents multiple watchers from being created
# - Tracks last read file position to append only new lines
# - Updates both main console ($txtConsole) and optional command console ($txtCommandConsole)
# - Uses BeginInvoke to safely update GUI from background threads
# - Provides fallback polling in case the watcher misses changes
#
# OPERATION FLOW:
# Step 1: Prevent duplicate watchers by checking $script:logWatcher
# Step 2: Initialize last log size based on existing log file
# Step 3: Create FileSystemWatcher for latest.log in its directory
# Step 4: Register event handler for Changed events
#         a) Debounce slightly to allow writer to flush
#         b) Open log file, seek to last read position
#         c) Read new lines into buffer
#         d) Update last read position
#         e) Append buffer to UI consoles using BeginInvoke
# Step 5: Create fallback Timer (200ms) for missed events
# Step 6: On fallback Timer tick, check file length, read new lines, update UI
# Step 7: Catch failures from watcher creation, fallback to a faster Timer (100ms)
# =====================
function Start-LogPolling {
    # Step 1: Avoid multiple watchers
    if ($script:logWatcher) { return }

    # Step 2: Reset last log read position
    $script:lastLogSize = 0

    # Step 2a: Initialize position if file exists
    $logExists = Test-Path $script:logFilePath
    if ($logExists) { $script:lastLogSize = (Get-Item $script:logFilePath).Length }

    try {
        # Step 3: Extract directory and filename
        $logDir = Split-Path $script:logFilePath
        $logFile = Split-Path $script:logFilePath -Leaf

        # Create FileSystemWatcher for latest.log
        $script:logWatcher = New-Object System.IO.FileSystemWatcher $logDir, $logFile
        $script:logWatcher.NotifyFilter = [System.IO.NotifyFilters]'LastWrite,Size'
        $script:logWatcher.IncludeSubdirectories = $false
        $script:logWatcher.EnableRaisingEvents = $true

        # Step 4: Register event handler for Changed event
        if ($script:logWatcherRegistration) {
            try { Unregister-Event -SubscriptionId $script:logWatcherRegistration.Id -ErrorAction SilentlyContinue } catch {}
            $script:logWatcherRegistration = $null
        }

        $script:logWatcherRegistration = Register-ObjectEvent -InputObject $script:logWatcher -EventName Changed -Action {
            # Step 4a: Debounce to allow file flush
            Start-Sleep -Milliseconds 30
            try {
                if (-not (Test-Path $script:logFilePath)) { return }

                # Step 4b: Open log file for reading from last position
                $fs = [System.IO.File]::Open($script:logFilePath,'Open','Read','ReadWrite')
                $fs.Seek($script:lastLogSize, 'Begin') | Out-Null
                $sr = New-Object System.IO.StreamReader($fs)

                # Step 4c: Read new lines
                $buffer = ""
                while (-not $sr.EndOfStream) { $buffer += $sr.ReadLine() + "`r`n" }

                # Step 4d: Update last read position
                $script:lastLogSize = $fs.Position

                # Step 4e: Append to UI safely
                $sr.Close(); $fs.Close()
                if ($buffer) {
                    $del = [System.Action[string]]{ param($s) 
                        $txtConsole.AppendText($s)
						foreach ($line in ($s -split "`r?`n")) {
							Update-PlayerCount $line
						}
					}
					$txtConsole.BeginInvoke($del, $buffer) | Out-Null

                    if ($script:txtCommandConsole) {
                        $del2 = [System.Action[string]]{ param($s) $txtCommandConsole.AppendText($s) }
                        $txtCommandConsole.BeginInvoke($del2, $buffer) | Out-Null
                    }
                }
            } catch {}
        }

        # Step 5: Create fallback timer (200ms) in case watcher misses updates
        if ($script:logFallbackTimer) { $script:logFallbackTimer.Stop(); $script:logFallbackTimer.Dispose() }
        $script:logFallbackTimer = New-Object System.Windows.Forms.Timer
        $script:logFallbackTimer.Interval = 200
        $script:logFallbackTimer.Add_Tick({
            if (-not (Test-Path $script:logFilePath)) { return }
            try {
                $info = Get-Item $script:logFilePath
                if ($info.Length -gt $script:lastLogSize) {
                    $fs = [System.IO.File]::Open($script:logFilePath,'Open','Read','ReadWrite')
                    $fs.Seek($script:lastLogSize, 'Begin') | Out-Null
                    $sr = New-Object System.IO.StreamReader($fs)
                    $buf = ""
                    while (-not $sr.EndOfStream) { $buf += $sr.ReadLine() + "`r`n" }
                    $script:lastLogSize = $fs.Position
                    $sr.Close(); $fs.Close()

                    if ($buf) {
                        $del = [System.Action[string]]{ param($s) 
                            $txtConsole.AppendText($s)
                            # Check each line for player join/leave
                            foreach ($line in ($s -split "`r?`n")) {
                                Update-PlayerCount $line
                            }
                        }
                        $txtConsole.BeginInvoke($del, $buf) | Out-Null
                        if ($script:txtCommandConsole) {
                            $del2 = [System.Action[string]]{ param($s) $txtCommandConsole.AppendText($s) }
                            $txtCommandConsole.BeginInvoke($del2, $buf) | Out-Null
                        }
                    }
                }
            } catch {}
        })
        $script:logFallbackTimer.Start()

    } catch {
        # Step 7: If watcher fails, fallback to a simple fast polling timer (100ms)
        if ($script:logTimer) { $script:logTimer.Stop(); $script:logTimer.Dispose() }
        $script:logTimer = New-Object System.Windows.Forms.Timer
        $script:logTimer.Interval = 100
        $script:logTimer.Add_Tick({
            if (-not (Test-Path $script:logFilePath)) { return }
            try {
                $info = Get-Item $script:logFilePath
                if ($info.Length -gt $script:lastLogSize) {
                    $fs = [System.IO.File]::Open($script:logFilePath,'Open','Read','ReadWrite')
                    $fs.Seek($script:lastLogSize, 'Begin') | Out-Null
                    $sr = New-Object System.IO.StreamReader($fs)
                    while (-not $sr.EndOfStream) {
                        $txtConsole.AppendText($sr.ReadLine() + "`r`n")
                    }
                    $script:lastLogSize = $fs.Position
                    $sr.Close(); $fs.Close()
                }
            } catch {}
        })
        $script:logTimer.Start()
    }
}

# =====================
# Function: Load-Config
# =====================
# PURPOSE:
# Loads the server configuration file (config.json) into the GUI editor.
# If the file contains valid JSON, it formats it for readability (pretty-printed).
# If the JSON is invalid, it falls back to displaying the raw file contents.
#
# WHY THIS EXISTS:
# - Allows users to view and edit server configuration safely within the GUI
# - Provides a readable, indented format for easier understanding of JSON structure
# - Ensures that even malformed JSON is still visible to the user
#
# OPERATION FLOW:
# Step 1: Check if config.json exists; exit if missing
# Step 2: Attempt to parse the file as JSON
#         a) If successful, convert back to pretty-printed JSON string
#         b) Set $txtConfigEditor.Text to formatted JSON
# Step 3: If JSON parsing fails, read the file as raw text and display it
# =====================
function Load-Config {
    # Step 1: Exit if config file doesn't exist
    if (-not (Test-Path $script:configPath)) { return }

    try {
        # Step 2a: Parse JSON content
        $json = Get-Content $script:configPath -Raw | ConvertFrom-Json

        # Step 2b: Convert to pretty-printed JSON string
        $formatted = $json | ConvertTo-Json -Depth 10 -Compress:$false

        # Step 2c: Update editor textbox
        $txtConfigEditor.Text = $formatted
    } catch {
        # Step 3: Fallback to raw text if JSON invalid
        $txtConfigEditor.Text = Get-Content $script:configPath -Raw
    }
}


# =====================
# Function: Save-Config
# =====================
# PURPOSE:
# Validates and saves the contents of the configuration editor ($txtConfigEditor)
# back to the server's config.json file. Ensures that only valid JSON is written.
#
# WHY THIS EXISTS:
# - Prevents invalid JSON from being saved and potentially breaking the server
# - Maintains a pretty-printed layout for easier future edits
# - Provides user feedback on success or failure
#
# OPERATION FLOW:
# Step 1: Attempt to parse the editor text as JSON to validate it
# Step 2: If valid, convert it back to pretty-printed JSON string
# Step 3: Write the formatted JSON to config.json
# Step 4: Notify the user of successful save via MessageBox
# Step 5: If JSON is invalid, catch the exception and notify user with error MessageBox
# =====================
function Save-Config {
    try {
        # Step 1: Validate JSON by parsing
        $txtConfigEditor.Text | ConvertFrom-Json  

        # Step 2: Pretty-print JSON for consistent formatting
        $pretty = ($txtConfigEditor.Text | ConvertFrom-Json | ConvertTo-Json -Depth 10 -Compress:$false)

        # Step 3: Write formatted JSON to file
        Set-Content -Path $script:configPath -Value $pretty

        # Step 4: Notify success
        [System.Windows.Forms.MessageBox]::Show("Configuration saved successfully","Success")
    } catch {
        # Step 5: Notify failure if JSON invalid
        [System.Windows.Forms.MessageBox]::Show("Invalid JSON format. Please check your configuration.","Error")
    }
}

# =====================
# Function: Load-Permissions
# =====================
# PURPOSE:
# Loads the server permissions file (permissions.json) into the GUI editor.
# If the file contains valid JSON, it is pretty-printed for readability.
# If the JSON is invalid, the raw file contents are displayed.
#
# WHY THIS EXISTS:
# - Allows users to view and edit server permissions within the GUI
# - Provides a readable, indented format for easier understanding
# - Ensures even malformed JSON is still accessible for inspection
#
# OPERATION FLOW:
# Step 1: Check if permissions.json exists; exit if missing
# Step 2: Attempt to parse the file as JSON
#         a) If valid, convert to pretty-printed JSON
#         b) Set $txtConfigEditor.Text to formatted JSON
# Step 3: If parsing fails, display raw file contents
# =====================
function Load-Permissions {
    # Step 1: Exit if permissions file does not exist
    if (-not (Test-Path $script:permissionsPath)) { return }

    try {
        # Step 2a: Parse JSON content
        $json = Get-Content $script:permissionsPath -Raw | ConvertFrom-Json

        # Step 2b: Convert to pretty-printed JSON
        $formatted = $json | ConvertTo-Json -Depth 10 -Compress:$false

        # Step 2c: Update editor textbox
        $txtConfigEditor.Text = $formatted
    } catch {
        # Step 3: Fallback to raw text if JSON invalid
        $txtConfigEditor.Text = Get-Content $script:permissionsPath -Raw
    }
}

# =====================
# Function: Save-Permissions
# =====================
# PURPOSE:
# Validates and saves the contents of the permissions editor ($txtConfigEditor)
# back to the server's permissions.json file. Only valid JSON will be saved.
#
# WHY THIS EXISTS:
# - Prevents invalid JSON from being written, which could break server permissions
# - Maintains a consistent, pretty-printed format for easier future edits
# - Provides immediate user feedback on success or failure
#
# OPERATION FLOW:
# Step 1: Attempt to parse the editor text as JSON to validate it
# Step 2: If valid, convert it back to a pretty-printed JSON string
# Step 3: Write the formatted JSON to permissions.json
# Step 4: Display a MessageBox to confirm successful save
# Step 5: If JSON is invalid, catch the exception and display an error MessageBox
# =====================
function Save-Permissions {
    try {
        # Step 1: Validate JSON by parsing
        $txtConfigEditor.Text | ConvertFrom-Json  

        # Step 2: Pretty-print JSON for consistent formatting
        $pretty = ($txtConfigEditor.Text | ConvertFrom-Json | ConvertTo-Json -Depth 10 -Compress:$false)

        # Step 3: Save formatted JSON to file
        Set-Content -Path $script:permissionsPath -Value $pretty

        # Step 4: Notify success
        [System.Windows.Forms.MessageBox]::Show("Permissions saved successfully","Success")
    } catch {
        # Step 5: Notify user if JSON is invalid
        [System.Windows.Forms.MessageBox]::Show("Invalid JSON format. Please check your permissions file.","Error")
    }
}

# =====================
# Function: Open-ConfigFile
# =====================
# PURPOSE:
# Opens the config.json file in the system's default text editor.
# Allows users to edit the configuration file in their preferred editor
# (Notepad, VS Code, Notepad++, etc.) instead of the built-in editor.
#
# WHY THIS EXISTS:
# - Some users prefer their own editor with syntax highlighting and features
# - Allows quick access without loading the file into the GUI editor first
# - Familiar workflow for power users
#
# PARAMETERS:
# None
#
# OPERATION FLOW:
# Step 1: Verify config.json exists
# Step 2: Open file with default application (system association)
# Step 3: Show error if file doesn't exist
# =====================
function Open-ConfigFile {
    try {
        # Step 1: Check if config file exists
        if (-not (Test-Path $script:configPath)) {
            [System.Windows.Forms.MessageBox]::Show(
                "config.json not found at: $script:configPath",
                "File Not Found",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        # Step 2: Open the file with default associated editor
        Start-Process -FilePath $script:configPath
        $txtConsole.AppendText("[INFO] Opened config.json in default editor`r`n")
    } catch {
        # Step 3: Handle any errors
        [System.Windows.Forms.MessageBox]::Show(
            "Error opening config.json: $_",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        $txtConsole.AppendText("[ERR] Failed to open config.json: $_`r`n")
    }
}

# =====================
# Function: Open-PermissionsFile
# =====================
# PURPOSE:
# Opens the permissions.json file in the system's default text editor.
# Allows users to edit the permissions file in their preferred editor
# (Notepad, VS Code, Notepad++, etc.) instead of the built-in editor.
#
# WHY THIS EXISTS:
# - Some users prefer their own editor with syntax highlighting and features
# - Allows quick access without loading the file into the GUI editor first
# - Familiar workflow for power users
#
# PARAMETERS:
# None
#
# OPERATION FLOW:
# Step 1: Verify permissions.json exists
# Step 2: Open file with default application (system association)
# Step 3: Show error if file doesn't exist
# =====================
function Open-PermissionsFile {
    try {
        # Step 1: Check if permissions file exists
        if (-not (Test-Path $script:permissionsPath)) {
            [System.Windows.Forms.MessageBox]::Show(
                "permissions.json not found at: $script:permissionsPath",
                "File Not Found",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        # Step 2: Open the file with default associated editor
        Start-Process -FilePath $script:permissionsPath
        $txtConsole.AppendText("[INFO] Opened permissions.json in default editor`r`n")
    } catch {
        # Step 3: Handle any errors
        [System.Windows.Forms.MessageBox]::Show(
            "Error opening permissions.json: $_",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        $txtConsole.AppendText("[ERR] Failed to open permissions.json: $_`r`n")
    }
}

# =====================
# Function: Run-DownloaderCommand
# =====================
# PURPOSE:
# Executes the Hytale downloader executable with specified command-line arguments,
# logs the entire operation to the Update Log textbox, captures both stdout and stderr,
# and returns the standard output for further processing.
#
# WHY THIS EXISTS:
# - Provides a standardized way to run the downloader from the GUI
# - Captures and displays all output in the Update Log for user visibility
# - Handles errors gracefully and provides feedback via MessageBox
# - Allows other functions (like Run-DownloaderAndCapture) to use the output programmatically
#
# PARAMETERS:
# - $arguments ([string]): Arguments to pass to the downloader executable
# - $description ([string]): A descriptive label for the operation (used in logs)
#
# RETURN VALUE:
# - Returns the raw standard output from the downloader process
# - Returns $null if an exception occurs
#
# OPERATION FLOW:
# Step 1: Verify the downloader executable exists; display error and exit if missing
# Step 2: Append log headers and description to $txtUpdateLog
# Step 3: Prepare a ProcessStartInfo object for running the downloader
#         a) Set executable path, arguments, working directory
#         b) Redirect stdout and stderr
#         c) Hide console window
# Step 4: Start the process and read both stdout and stderr
# Step 5: Wait for process to exit
# Step 6: Append standard output and errors to the Update Log
# Step 7: Append exit code and log footer
# Step 8: Return the captured standard output
# Step 9: Catch any exceptions, log them, display MessageBox, and return $null
# =====================
function Run-DownloaderCommand {
    param([string]$arguments, [string]$description)
    
    # Step 1: Ensure the downloader exists
    if (-not (Test-Path $script:downloaderPath)) {
        $txtUpdateLog.AppendText("[ERROR] Downloader not found at: $script:downloaderPath`r`n")
        [System.Windows.Forms.MessageBox]::Show("Downloader executable not found!", "Error")
        return
    }

    try {
        # Step 2: Log operation start
        $txtUpdateLog.AppendText("========================================`r`n")
        $txtUpdateLog.AppendText("[INFO] $description`r`n")
        $txtUpdateLog.AppendText("[INFO] Command: $script:downloaderPath $arguments`r`n")
        $txtUpdateLog.AppendText("========================================`r`n")

        # Step 3: Setup process information
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:downloaderPath
        $psi.Arguments = $arguments
        $psi.WorkingDirectory = $PSScriptRoot
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi

     # Step 4: Start process and capture output
        $process.Start() | Out-Null
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()

        # Step 5: Wait for process to finish
        while (-not $process.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }

        # Step 6: Append stdout and stderr to Update Log
        if ($output) { $txtUpdateLog.AppendText($output + "`r`n") }
        if ($errorOutput) { $txtUpdateLog.AppendText("[ERROR] $errorOutput`r`n") }

        # Step 7: Append exit code and log footer
        $txtUpdateLog.AppendText("[INFO] Command completed (Exit Code: $($process.ExitCode))`r`n")
        $txtUpdateLog.AppendText("========================================`r`n")

        # Step 8: Return the standard output
        return $output
    } catch {
        # Step 9: Handle exceptions
        $txtUpdateLog.AppendText("[EXCEPTION] $($_)`r`n")
        [System.Windows.Forms.MessageBox]::Show("Command failed: $_", "Error")
        return $null
    }
}

# =====================
# Function: Get-DownloaderServerVersion
# =====================
# PURPOSE:
# Queries the Hytale downloader for the server version string or hash, which is useful
# for verifying the current version or deciding if an update is needed.
#
# WHY THIS EXISTS:
# - Provides a simple way to get the server version without manually parsing files
# - Supports downstream logic for automated updates or version checks
#
# OPERATION FLOW:
# Step 1: Call Run-DownloaderAndCapture with "-print-version" to retrieve version info
# Step 2: If no output is returned, exit and return $null
# Step 3: Attempt to match known downloader output patterns:
#         a) Date-hash format (YYYY.MM.DD-HASH) → return only the HASH part
#         b) Semantic version format (X.Y.Z) → return the matched version
# Step 4: If no pattern matches, return the trimmed raw output as a fallback
#
# RETURN VALUE:
# - Returns the server version string or hash if detected
# - Returns $null if downloader fails or no output is available
# =====================
function Get-DownloaderServerVersion {
    # Step 1: Get downloader output for version
    $output = Run-DownloaderAndCapture "-print-version" "Get downloader server version"

    # Step 2: Return null if output empty
    if (-not $output) { return $null }

    # Step 3a: Match date-hash format (e.g., 2026.01.19-abcdef123)
    if ($output -match '(\d{4}\.\d{2}\.\d{2})-(\w+)') {
        return $matches[2]  # Return the hash portion
    }

    # Step 3b: Match semantic version format (e.g., 2.1.0)
    if ($output -match '(\d+\.\d+\.\d+)') {
        return $matches[1]
    }

    # Step 4: Fallback to trimmed raw output
    return $output
}

# =====================
# Function: Get-ZipServerVersion
# =====================
# PURPOSE:
# Determines the server version or build hash from the most recently downloaded server ZIP file.
#
# WHY THIS EXISTS:
# - Useful for version comparison between existing ZIPs and the downloader
# - Helps identify if the server is up-to-date or requires an update
#
# OPERATION FLOW:
# Step 1: List all ZIP files in the script folder, excluding Assets.zip
# Step 2: If no ZIP files found, return $null
# Step 3: Sort ZIPs by LastWriteTime descending and pick the most recent
# Step 4: Use regex to extract version/hash from filename pattern:
#         a) Expected format: "YYYY.MM.DD-HASH.zip"
#         b) Return only the HASH portion
# Step 5: If filename does not match pattern, return $null
#
# RETURN VALUE:
# - Returns the extracted hash string from the latest ZIP
# - Returns $null if no suitable ZIP found or format unrecognized
# =====================
function Get-ZipServerVersion {
    # Step 1: Get all ZIP files except Assets.zip
    $zipFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.zip" | Where-Object { $_.Name -notlike "Assets.zip" }

    # Step 2: Return null if none found
    if ($zipFiles.Count -eq 0) { return $null }

    # Step 3: Get the most recently modified ZIP
    $latestZip = $zipFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    # Step 4: Extract hash from filename using regex
    if ($latestZip.Name -match '^\d{4}\.\d{2}\.\d{2}-(.+)\.zip$') {
        return $matches[1]  # Return only the hash portion
    } else {
        # Step 5: Return null if pattern does not match
        return $null
    }
}

# =====================
# Function: Check-ServerUpdate
# =====================
# PURPOSE:
# Compares the server version reported by the downloader executable with the version
# extracted from the latest downloaded ZIP file, and notifies the user if an update is needed.
#
# WHY THIS EXISTS:
# - Provides a simple mechanism for users to check if their server files are up-to-date
# - Ensures that administrators are aware when a new server build is available
# - Integrates directly with the update log and GUI notifications
#
# OPERATION FLOW:
# Step 1: Get the server version reported by the downloader
#         - Uses Get-DownloaderServerVersion
# Step 2: If downloader version cannot be read, show MessageBox error and exit
# Step 3: Get the version/hash from the latest downloaded ZIP
#         - Uses Get-ZipServerVersion
# Step 4: If no ZIP found, show MessageBox error and exit
# Step 5: Append debug info to the update log for troubleshooting
# Step 6: Compare versions:
#         a) If different → show MessageBox that an update is available with both versions
#         b) If same → show MessageBox that server is up-to-date
#
# DEPENDENCIES:
# - Get-DownloaderServerVersion
# - Get-ZipServerVersion
# - $txtUpdateLog must be a valid TextBox control
#
# UI INTERACTIONS:
# - Uses System.Windows.Forms.MessageBox to notify the user of errors or update status
# - Updates $txtUpdateLog with debug information
# =====================
function Check-ServerUpdate {

    # Step 1: Retrieve downloader-reported version
    $exeVersion = Get-DownloaderServerVersion
    if (-not $exeVersion) {
        # Step 2: Notify user if version cannot be read
        [System.Windows.Forms.MessageBox]::Show(
            "Could not read server version from downloader.",
            "Version Error"
        )
        return
    }

    # Step 3: Retrieve latest ZIP version
    $zipVersion = Get-ZipServerVersion
    if (-not $zipVersion) {
        # Step 4: Notify user if no ZIP found
        [System.Windows.Forms.MessageBox]::Show(
            "No server update ZIP found to compare against.",
            "No Update Package"
        )
        return
    }
	
    # Step 5: Debug logging
	$txtUpdateLog.AppendText("[DEBUG] EXE=$exeVersion ZIP=$zipVersion`r`n")

    # Step 6: Compare versions and notify user
    if ($exeVersion -ne $zipVersion) {
        # Update available
        [System.Windows.Forms.MessageBox]::Show(
            "Update Available!`n`nInstalled (EXE): $exeVersion`nZIP Package: $zipVersion",
            "Update Available",
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
    else {
        # Up to date
        [System.Windows.Forms.MessageBox]::Show(
            "No update available.`n`nVersion: $exeVersion",
            "Up To Date",
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
}

# =====================
# Function: Send-ServerCommand
# =====================
# PURPOSE:
# Sends a command string to the running Hytale server process via its standard input.
# This allows execution of in-game commands directly from the GUI or scripts.
#
# WHY THIS EXISTS:
# - Provides a bridge between the GUI and server console
# - Enables administrators to send commands without opening the server console
# - Prevents errors when the server is not running
#
# OPERATION FLOW:
# Step 1: Check if the server process is currently running and valid
# Step 2: If running, write the command line to the server's StandardInput
# Step 3: If not running, display a MessageBox error to notify the user
#
# PARAMETERS:
# - $command : String command to send to the server console (e.g., "stop", "save-all")
#
# DEPENDENCIES:
# - $script:serverRunning must accurately reflect server state
# - $script:serverProcess must be a valid Process object with StandardInput accessible
# - GUI MessageBox requires System.Windows.Forms
# =====================
function Send-ServerCommand {
    param($command)

    # Step 1: Validate server process
    if ($script:serverRunning -and $script:serverProcess -and -not $script:serverProcess.HasExited) {
        # Step 2: Send command to server console
        $script:serverProcess.StandardInput.WriteLine($command)
    } else {
        # Step 3: Notify user if server is not running
        [System.Windows.Forms.MessageBox]::Show("Server is not running.","Error")
    }
}

# =====================
# Function: Get-VersionFromConsole
# =====================
# PURPOSE:
# Scans the last few lines of a given console TextBox to detect and extract a semantic version number
# in the format major.minor.patch (e.g., 1.2.3). Useful for determining server or mod versions
# directly from console output without parsing files.
#
# WHY THIS EXISTS:
# - Provides a quick way to determine the current running version from logs or server output
# - Limits scanning to last N lines for performance and relevancy
# - Returns $null if no version is found
#
# OPERATION FLOW:
# Step 1: Split the full console text into individual lines
# Step 2: Select only the last 20 lines to focus on recent output
# Step 3: Iterate over each line and attempt to match a semantic version pattern
# Step 4: If a match is found, return the first matched version string
# Step 5: If no matches found after scanning, return $null
#
# PARAMETERS:
# - $console : System.Windows.Forms.TextBox control containing console output
#
# RETURN:
# - String containing semantic version (e.g., "1.2.3") if found
# - $null if no version detected
# =====================
function Get-VersionFromConsole {
    param([System.Windows.Forms.TextBox]$console)

    # Step 1: Split console text into lines
    $lines = $console.Text -split "`r?`n"

    # Step 2 & 3: Scan last 20 lines for a semantic version pattern
    foreach ($line in ($lines | Select-Object -Last 20)) {
        if ($line -match "(\d+\.\d+\.\d+)") {
            # Step 4: Return the first version found
            return $matches[1]
        }
    }

    # Step 5: No version found
    return $null
}

# =====================
# Function: Start-Server
# =====================
# PURPOSE:
# Launches the Hytale server via Java with specified RAM settings, sets up event handlers to capture
# both standard output and error streams asynchronously, updates the GUI status and console logs,
# and initializes log polling and performance monitoring.
#
# WHY THIS EXISTS:
# - Provides a single, centralized way to start the server with all necessary hooks for UI updates
# - Ensures RAM constraints are validated before launch
# - Captures real-time server output for display in GUI consoles
# - Records start time for uptime tracking
# - Integrates seamlessly with logging, command sending, and performance monitoring
#
# OPERATION FLOW:
# Step 1: Check if the server is already running; exit early if so
# Step 2: Verify that HytaleServer.jar exists; show error if missing
# Step 3: Validate Min/Max RAM settings (ensure integers and Min <= Max)
# Step 4: Append info to GUI console about RAM and startup
# Step 5: Create ProcessStartInfo for Java execution
#        - FileName: "java"
#        - Arguments: include -Xms, -Xmx, -jar, assets, backup options
#        - RedirectStandardOutput/Error/Input to capture streams
#        - CreateNoWindow = true to hide console
# Step 6: Instantiate the Process object, enable raising events
# Step 7: Start the process, begin async reading of stdout and stderr
# Step 8: Register ObjectEvents for OutputDataReceived and ErrorDataReceived
#        - Append output to both main console and command console safely
# Step 9: Record server start time and mark server as running
# Step 10: Update status label in GUI (Running/Green)
# Step 11: Start log polling to tail latest.log
# Step 12: Update initial CPU and RAM stats
# Step 13: Catch any exceptions, log to console, and update GUI status (Error/Red)
#
# PARAMETERS: None
#
# RETURN: None
# =====================
function Start-Server {
    if ($script:serverRunning) { return }

    # Step 2: Ensure server JAR exists
    if (-not (Test-Path $script:jarPath)) {
        [System.Windows.Forms.MessageBox]::Show("HytaleServer.jar missing","Error")
        return
    }

    # Step 3: Validate RAM settings
    $minRam = if ($script:minRamGB -and $script:minRamGB -gt 0) { $script:minRamGB } else { 4 }
    $maxRam = if ($script:maxRamGB -and $script:maxRamGB -gt 0) { $script:maxRamGB } else { 8 }

    if ($minRam -gt $maxRam) {
        [System.Windows.Forms.MessageBox]::Show("Min RAM cannot exceed Max RAM","Error")
        return
    }

    # Step 4: Log RAM and startup info
    $txtConsole.AppendText("[INFO] RAM: Min=${minRam}GB Max=${maxRam}GB`r`n")
    $txtConsole.AppendText("[INFO] Starting server...`r`n")

    # Step 5: Configure process
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "java"
    $psi.Arguments = "-Xms${minRam}G -Xmx${maxRam}G -jar `"$script:jarPath`" --assets Assets.zip --backup --backup-dir backup"
    $psi.WorkingDirectory = $PSScriptRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true

    try {
        # Step 6: Instantiate process
        $script:serverProcess = New-Object System.Diagnostics.Process
        $script:serverProcess.StartInfo = $psi
        $script:serverProcess.EnableRaisingEvents = $true

        # Step 7: Start process and async reading
        $script:serverProcess.Start() | Out-Null
        $script:serverProcess.BeginOutputReadLine()
        $script:serverProcess.BeginErrorReadLine()

        # Step 8: Register stdout event
        if ($script:serverOutReg) {
            try { Unregister-Event -SubscriptionId $script:serverOutReg.Id -ErrorAction SilentlyContinue } catch {}
            $script:serverOutReg = $null
        }
        $script:serverOutReg = Register-ObjectEvent -InputObject $script:serverProcess -EventName "OutputDataReceived" -Action {
            if ($Event.SourceEventArgs.Data) {
                try { $txtConsole.AppendText("$($Event.SourceEventArgs.Data)`r`n") } catch {}
                try { $txtCommandConsole.AppendText("$($Event.SourceEventArgs.Data)`r`n") } catch {}
            }
        }

        # Register stderr event
        if ($script:serverErrReg) {
            try { Unregister-Event -SubscriptionId $script:serverErrReg.Id -ErrorAction SilentlyContinue } catch {}
            $script:serverErrReg = $null
        }
        $script:serverErrReg = Register-ObjectEvent -InputObject $script:serverProcess -EventName "ErrorDataReceived" -Action {
            if ($Event.SourceEventArgs.Data) {
                try { $txtConsole.AppendText("[ERR] $($Event.SourceEventArgs.Data)`r`n") } catch {}
                try { $txtCommandConsole.AppendText("[ERR] $($Event.SourceEventArgs.Data)`r`n") } catch {}
            }
        }

        # Step 9: Record start time
        $script:serverStartTime = Get-Date
        $script:serverRunning = $false

        # Step 9b: Create auto-restart timer (6 hours = 21600000 milliseconds)
        if ($script:autoRestartTimer) {
            try { $script:autoRestartTimer.Stop() } catch {}
            try { $script:autoRestartTimer.Dispose() } catch {}
        }
        $script:autoRestartTimer = New-Object System.Windows.Forms.Timer
        $script:autoRestartTimer.Interval = 21600000  # 6 hours
        $script:autoRestartTimer.Add_Tick({
            $txtConsole.AppendText("[INFO] Auto-restart timer triggered after 6 hours`r`n")
            $txtConsole.AppendText("[INFO] Initiating scheduled server restart...`r`n")
            Restart-Server
        })
        $script:autoRestartTimer.Start()
        $txtConsole.AppendText("[INFO] Auto-restart timer set for 6 hours`r`n")

        # Step 10: Update GUI status
        $lblStatus.Text = "Status: Running"
        $lblStatus.ForeColor = [System.Drawing.Color]::LightGreen

        # Step 11: Start log polling
        Start-LogPolling

        # Step 11b: Confirm server is fully running after warm-up
        Start-Sleep -Seconds 2

        if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
            $script:serverRunning = $true
            $txtConsole.AppendText("[INFO] Server process confirmed running`r`n")
        }
		
		# Step 12: Start health monitoring
		if ($script:healthMonitorTimer) {
			$script:healthMonitorTimer.Stop()
			$script:healthMonitorTimer.Dispose()
        }
		$script:healthMonitorTimer = New-Object System.Windows.Forms.Timer
		$script:healthMonitorTimer.Interval = 150000  # in milliseconds
		$script:healthMonitorTimer.Add_Tick({ Monitor-ServerHealth })
		$script:healthMonitorTimer.Start()
		$script:pingFailCount = 0
		$txtConsole.AppendText("[INFO] Server health monitoring started`r`n")
    } catch {
        # Step 13: Handle startup errors
        $txtConsole.AppendText("[ERROR] Failed to start server: $_`r`n")
        $lblStatus.Text = "Status: Error"
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
    }
}

# =====================
# Function: Stop-Server
# =====================
# PURPOSE:
# Safely stops the running Hytale server process after performing a backup.
# Disposes of timers, unregisters events, and updates the GUI to reflect the stopped state.
# Ensures that memory/resources are cleaned up to avoid leaks and prevent stale event triggers.
#
# OPERATION FLOW:
# Step 0: Exit early if server is not running
# Step 1: Stop health monitor timer immediately
# Step 2: Send backup command and wait for completion
# Step 3: Terminate the server process
# Step 4: Dispose the per-process CPU PerformanceCounter to free system resources
# Step 5: Stop and dispose the log fallback timer (used if FileSystemWatcher misses updates)
# Step 6: Unregister FileSystemWatcher event registration, if any
# Step 7: Stop and dispose the FileSystemWatcher itself
# Step 8: Stop and dispose any old-style log timer fallback
# Step 9: Unregister server stdout/stderr event handlers to prevent background callbacks
# Step 10: Reset server state variables and update GUI labels to show the server is stopped
# Step 11: Append a console log entry indicating server shutdown
#
# PARAMETERS: None
#
# RETURN: None
# =====================
function Stop-Server {
    # Step 0: Early exit if server not running
    if (-not $script:serverRunning) { return }

    # Step 1: Stop health monitor timer FIRST to prevent interference
    if ($script:healthMonitorTimer) {
        try { $script:healthMonitorTimer.Stop() } catch {}
        try { $script:healthMonitorTimer.Dispose() } catch {}
        $script:healthMonitorTimer = $null
    }
    $script:pingFailCount = 0

        # STOP auto-restart timer FIRST
    if ($script:autoRestartTimer) {
        try { $script:autoRestartTimer.Stop() } catch {}
        try { $script:autoRestartTimer.Dispose() } catch {}
        $script:autoRestartTimer = $null
    }

    # Step 2: Initiate backup before shutdown
    if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
        try {
            $txtConsole.AppendText("[INFO] Initiating backup before server shutdown...`r`n")
            
            # Send backup command
            $script:serverProcess.StandardInput.WriteLine("backup")
            
            # Wait for backup completion (look for completion message in logs)
            $backupStartTime = Get-Date
            $backupCompleted = $false
            $timeout = 60  # 60 second timeout for backup
            
            while (-not $backupCompleted -and ((Get-Date) - $backupStartTime).TotalSeconds -lt $timeout) {
                Start-Sleep -Milliseconds 500
                
                # Check recent console output for backup completion message
                $recentOutput = $txtConsole.Text.Split("`n") | Select-Object -Last 20
                
                foreach ($line in $recentOutput) {
                    # Look for common backup completion messages
                    if ($line -match "backup.*complete|backup.*finished|backup.*success|saved.*backup") {
                        $backupCompleted = $true
                        $txtConsole.AppendText("[INFO] Backup completed successfully`r`n")
                        break
                    }
                }
            }
            
            if (-not $backupCompleted) {
                $txtConsole.AppendText("[WARN] Backup timeout - proceeding with shutdown anyway`r`n")
            }
            
            # Small delay to ensure backup files are written
            Start-Sleep -Seconds 2
            
        } catch {
            $txtConsole.AppendText("[WARN] Backup command failed: $_ - proceeding with shutdown`r`n")
        }
    }

    # Step 8: Stop and dispose any old-style fallback log timer
    if ($script:logTimer) {
        try { $script:logTimer.Stop() } catch {}
        try { $script:logTimer.Dispose() } catch {}
        $script:logTimer = $null
    }

    # Step 4: Dispose CPU performance counter
    if ($script:cpuCounter) {
        try { $script:cpuCounter.Dispose() } catch {}
        $script:cpuCounter = $null
    }

    # Step 5: Stop and dispose log fallback timer
    if ($script:logFallbackTimer) {
        try { $script:logFallbackTimer.Stop() } catch {}
        try { $script:logFallbackTimer.Dispose() } catch {}
        $script:logFallbackTimer = $null
    }

    # Step 6: Unregister FileSystemWatcher event
    if ($script:logWatcherRegistration) {
        try { Unregister-Event -SubscriptionId $script:logWatcherRegistration.Id -ErrorAction SilentlyContinue } catch {}
        $script:logWatcherRegistration = $null
    }

    # Step 7: Stop and dispose the FileSystemWatcher itself
    if ($script:logWatcher) {
        try { $script:logWatcher.EnableRaisingEvents = $false } catch {}
        try { $script:logWatcher.Dispose() } catch {}
        $script:logWatcher = $null
    }

    # Step 8: Stop and dispose any old-style fallback log timer
    if ($script:logTimer) {
        try { $script:logTimer.Stop() } catch {}
        try { $script:logTimer.Dispose() } catch {}
        $script:logTimer = $null
    }

        # Step 3: Kill the running server process if it exists
    try {
        if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
            $txtConsole.AppendText("[INFO] Stopping server process...`r`n")
            $script:serverProcess.StandardInput.WriteLine("stop")
            $script:serverProcess.WaitForExit(15000)
        }
    } catch {}

    # Step 9: Unregister server stdout/stderr event handlers
    if ($script:serverOutReg) {
        try { Unregister-Event -SubscriptionId $script:serverOutReg.Id -ErrorAction SilentlyContinue } catch {}
        $script:serverOutReg = $null
    }
    if ($script:serverErrReg) {
        try { Unregister-Event -SubscriptionId $script:serverErrReg.Id -ErrorAction SilentlyContinue } catch {}
        $script:serverErrReg = $null
    }


    # Step 10: Reset server state variables and update GUI
    $script:serverRunning = $false
    $script:serverProcess = $null
    $script:serverStartTime = $null
    $script:playerCount = 0
    $lblStatus.Text = "Status: Stopped"
    $lblStatus.ForeColor = [System.Drawing.Color]::Red
    $lblUptime.Text = "Uptime: N/A"
    $lblServerPing.Text = "Players Online: 0"
    $lblServerPing.ForeColor = [System.Drawing.Color]::Gray

    # Step 11: Log server stop event to console
    $txtConsole.AppendText("[INFO] Server stopped`r`n")
}
# =====================
# Function: Restart-Server
# =====================
# PURPOSE:
# Provides a mechanism to restart the Hytale server with a configurable countdown warning.
# Warns players multiple times before restart to prevent data loss or interrupted gameplay.
# Useful for applying new configuration changes, clearing memory, or recovering from an error state.
#
# OPERATION FLOW:
# Step 1: Announce restart to all players with countdown
# Step 2: Send warning messages at intervals (60s, 30s, 10s, 5s, etc.)
# Step 3: Stop the server gracefully using Stop-Server
# Step 4: Wait for resources to fully release
# Step 5: Start the server using Start-Server
#
# PARAMETERS: 
# - $countdownSeconds (optional): Total countdown time in seconds (default: 60)
#
# RETURN: None
# =====================
function Restart-Server {
    param([int]$countdownSeconds = 60)
    
    # Check if server is running
    if (-not $script:serverRunning) {
        $txtConsole.AppendText("[WARN] Cannot restart - server is not running`r`n")
        return
    }
    
    # Step 1: Initial announcement
    $txtConsole.AppendText("[INFO] Server restart initiated - $countdownSeconds second countdown`r`n")
    Send-ServerCommand "/say [SERVER] Server restart in $countdownSeconds seconds!"
    
    # Step 2: Countdown warnings at specific intervals
    $warningIntervals = @(60, 45, 30, 20, 10, 5, 4, 3, 2, 1)
    
    foreach ($interval in $warningIntervals) {
        if ($interval -ge $countdownSeconds) { continue }
        
        # Calculate wait time until next warning
        $currentTime = $countdownSeconds
        $waitTime = $currentTime - $interval
        
        if ($waitTime -gt 0) {
            # RESPONSIVE SLEEP - keeps GUI alive
            $sleepEnd = (Get-Date).AddSeconds($waitTime)
            while ((Get-Date) -lt $sleepEnd) {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 100
            }
            
            $countdownSeconds = $interval
            
            # Send warning message
            if ($interval -le 10) {
                Send-ServerCommand "/say [SERVER] RESTARTING IN $interval SECONDS!"
                $txtConsole.AppendText("[WARN] Restart in $interval seconds...`r`n")
            } else {
                Send-ServerCommand "/say [SERVER] Server restart in $interval seconds"
                $txtConsole.AppendText("[INFO] Restart in $interval seconds...`r`n")
            }
        }
    }
    
    # Final warning
    Send-ServerCommand "/say [SERVER] RESTARTING NOW! Please reconnect in a moment..."
    $txtConsole.AppendText("[INFO] Initiating restart sequence...`r`n")
    
    # RESPONSIVE SLEEP - Small delay for final message
    $sleepEnd = (Get-Date).AddSeconds(2)
    while ((Get-Date) -lt $sleepEnd) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    
    # Step 3: Stop server
    Stop-Server
    
    # RESPONSIVE SLEEP - Wait for resources to release
    $sleepEnd = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $sleepEnd) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    
    # Step 5: Start server
    Start-Server
}

# =====================
# Function: Update-Server
# Description: Full update flow using the downloader executable with clear step-by-step sections.
# =====================
function Update-Server {

    # ==============================
    # Step 0: Check if downloader exists
    # ==============================
    if (-not (Test-Path $script:downloaderPath)) {
        $txtUpdateLog.AppendText("[ERROR] Downloader not found at: $script:downloaderPath`r`n")
        $txtUpdateLog.AppendText("[INFO] Please download 'hytale-downloader-windows-amd64.exe' and place it in the server directory.`r`n")
        [System.Windows.Forms.MessageBox]::Show("Downloader executable not found!`n`nPlease download 'hytale-downloader-windows-amd64.exe' and place it in the server folder.", "Error")
        return
    }

    # ==============================
    # Step 1: Stop server if running
    # ==============================
    $wasRunning = $false
    if ($script:serverRunning) {
        $txtUpdateLog.AppendText("[INFO] Server is running - stopping for update...`r`n")
        $wasRunning = $true
        Stop-Server
        $sleepEnd = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $sleepEnd) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
    }

    # ==============================
    # Step 1b: Record existing latest server ZIP before downloading
    # ==============================
    $existingZips = Get-ChildItem -Path $PSScriptRoot -Filter "*.zip" | Where-Object { $_.Name -notlike "Assets.zip" }
    $latestExistingZip = $null
    if ($existingZips.Count -gt 0) {
        $latestExistingZip = $existingZips | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $txtUpdateLog.AppendText("[INFO] Existing latest zip before download: $($latestExistingZip.Name)`r`n")
    }

    try {
        $txtUpdateLog.AppendText("========================================`r`n")
        $txtUpdateLog.AppendText("[INFO] Starting Hytale Server Update`r`n")
        $txtUpdateLog.AppendText("========================================`r`n")
        $txtUpdateLog.AppendText("[INFO] Running downloader: $script:downloaderPath`r`n")

        # ==============================
        # Step 2: Run the downloader (GUI-friendly)
        # ==============================
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:downloaderPath
        $psi.WorkingDirectory = $PSScriptRoot
        $psi.UseShellExecute = $true        # Must be true for GUI apps
        $psi.CreateNoWindow = $false        # Show the GUI for authorization
        $psi.RedirectStandardOutput = $false
        $psi.RedirectStandardError = $false

        $updateProcess = New-Object System.Diagnostics.Process
        $updateProcess.StartInfo = $psi

        # Start the GUI downloader
        $updateProcess.Start() | Out-Null
        $txtUpdateLog.AppendText("[INFO] Downloader launched. Please complete authorization in the pop-up window...`r`n")

        # Wait for process to finish while keeping GUI responsive
        while (-not $updateProcess.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }

        $txtUpdateLog.AppendText("[INFO] Downloader finished (Exit Code: $($updateProcess.ExitCode))`r`n")

        if ($updateProcess.ExitCode -ne 0) {
            $txtUpdateLog.AppendText("[WARN] Downloader exited with non-zero code. Update may have failed.`r`n")
            [System.Windows.Forms.MessageBox]::Show("Download may have failed. Check the update log for details.", "Warning")
            
            if ($wasRunning -and $chkAutoRestart.Checked) {
                $txtUpdateLog.AppendText("[INFO] Restarting server...`r`n")
                Start-Server
            }
            return
        }

        # ==============================
        # Step 3+: Continue as normal
        # ==============================
        $txtUpdateLog.AppendText("[INFO] Searching for downloaded files...`r`n")
        $zipFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.zip" | 
                    Where-Object { $_.Name -notlike "Assets.zip" } | 
                    Sort-Object LastWriteTime -Descending

        if ($zipFiles.Count -eq 0) {
            $txtUpdateLog.AppendText("[ERROR] No new zip file found after download!`r`n")
            [System.Windows.Forms.MessageBox]::Show("No update file found after download.", "Error")
            
            if ($wasRunning -and $chkAutoRestart.Checked) {
                $txtUpdateLog.AppendText("[INFO] Restarting server...`r`n")
                Start-Server
            }
            return
        }

        $downloadedZip = $zipFiles[0]
        $txtUpdateLog.AppendText("[INFO] Found: $($downloadedZip.Name) ($([math]::Round($downloadedZip.Length / 1MB, 2)) MB)`r`n")
        
        # ==============================
        # Step 4: Remove old zip if a new zip was downloaded
        # ==============================
        if ($latestExistingZip -and ($latestExistingZip.FullName -ne $downloadedZip.FullName)) {
            Remove-Item -Path $latestExistingZip.FullName -Force
            $txtUpdateLog.AppendText("[INFO] Removed old zip: $($latestExistingZip.Name)`r`n")
        }

        # ==============================
        # Step 5: Existing JAR check / confirmation
        # ==============================
        $existingJar = Join-Path $PSScriptRoot "HytaleServer.jar"
        if (Test-Path $existingJar) {
            $existingJarDate = (Get-Item $existingJar).LastWriteTime
            $zipDate = $downloadedZip.LastWriteTime
            
            # If ZIP is not newer, prompt user
            if ($zipDate -le $existingJarDate) {
                $txtUpdateLog.AppendText("[INFO] Downloaded file is not newer than existing server files.`r`n")
                $result = [System.Windows.Forms.MessageBox]::Show(
                    "The downloaded file does not appear to be newer than your current server.`n`nDo you want to install it anyway?",
                    "Confirm Update",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
                
                if ($result -eq [System.Windows.Forms.DialogResult]::No) {
                    $txtUpdateLog.AppendText("[INFO] Update cancelled by user. Deleting downloaded file...`r`n")
                    Remove-Item -Path $downloadedZip.FullName -Force
                    
                    if ($wasRunning -and $chkAutoRestart.Checked) {
                        $txtUpdateLog.AppendText("[INFO] Restarting server...`r`n")
                        Start-Server
                    }
                    return
                }
            }
        }

        # ==============================
        # Step 6: Extract, merge, cleanup (FIXED)
        # ==============================
        $txtUpdateLog.AppendText("[INFO] Extracting update files...`r`n")
        $tempExtractPath = Join-Path $PSScriptRoot "temp_update_extract"

        # Remove previous temp extraction folder if it exists
        if (Test-Path $tempExtractPath) {
            $txtUpdateLog.AppendText("[INFO] Cleaning old temp directory...`r`n")
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        New-Item -Path $tempExtractPath -ItemType Directory -Force | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($downloadedZip.FullName, $tempExtractPath)
        $txtUpdateLog.AppendText("[INFO] Extraction complete.`r`n")

        # Merge 'assets.zip' and 'server' folder into root
        $filesCopied = 0
        $filesUpdated = 0

        # Copy assets.zip if exists
        $assetsZip = Join-Path $tempExtractPath "assets.zip"
        if (Test-Path $assetsZip) {
            $destAssetZip = Join-Path $PSScriptRoot "assets.zip"
            $fileExists = Test-Path $destAssetZip
            Copy-Item -Path $assetsZip -Destination $destAssetZip -Force
            if ($fileExists) { $filesUpdated++ } else { $filesCopied++ }
        }

        # Copy server folder contents into root
        $serverFolder = Join-Path $tempExtractPath "server"
        if (Test-Path $serverFolder) {
            Get-ChildItem -Path $serverFolder -Recurse | ForEach-Object {
                $relativePath = $_.FullName.Substring($serverFolder.Length + 1)
                $destinationPath = Join-Path $PSScriptRoot $relativePath
                if ($_.PSIsContainer) {
                    if (-not (Test-Path $destinationPath)) {
                        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
                    }
                } else {
                    $fileExists = Test-Path $destinationPath
                    Copy-Item -Path $_.FullName -Destination $destinationPath -Force
                    if ($fileExists) { $filesUpdated++ } else { $filesCopied++ }
                }
            }
        }

        $txtUpdateLog.AppendText("[INFO] Merge complete! New files: $filesCopied | Updated files: $filesUpdated`r`n")

        # Delete temp extraction folder
        $txtUpdateLog.AppendText("[INFO] Cleaning up temporary files...`r`n")
        Remove-Item -Path $tempExtractPath -Recurse -Force

        $txtUpdateLog.AppendText("========================================`r`n")
        $txtUpdateLog.AppendText("[SUCCESS] Update completed successfully!`r`n")
        $txtUpdateLog.AppendText("========================================`r`n")

        # Re-validate server files
        Check-ServerFiles

        # Auto-restart server if previously running and checkbox enabled
        if ($wasRunning -and $chkAutoRestart.Checked) {
            $txtUpdateLog.AppendText("[INFO] Auto-restart enabled - restarting server in 3 seconds...`r`n")
            $sleepEnd = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $sleepEnd) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
            Start-Server
            [System.Windows.Forms.MessageBox]::Show(
                "Update completed successfully!`n`nNew files: $filesCopied`nUpdated files: $filesUpdated`n`nServer has been restarted.",
                "Update Complete"
            )
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Update completed successfully!`n`nNew files: $filesCopied`nUpdated files: $filesUpdated`n`nYou can now start the server.",
                "Update Complete"
            )
        }

    } catch {
        # Log exception details
        $txtUpdateLog.AppendText("[EXCEPTION] $($_)`r`n")
        $txtUpdateLog.AppendText("[EXCEPTION] $($_.ScriptStackTrace)`r`n")
        [System.Windows.Forms.MessageBox]::Show("Update failed: $_", "Error")

        # Ask user if they want to restart server after failure
        if ($wasRunning) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "Update failed. Do you want to restart the server with the previous version?",
                "Restart Server?",
                [System.Windows.Forms.MessageBoxButtons]::YesNo
            )
            
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-Server
            }
        }
    }
}

# =====================
# FUNCTION: Update-StartButtonState
# PURPOSE: Enable or disable only the Start button based on current server status
# =====================
function Update-StartButtonState {
    # Check if status label shows "Stopped"
    if ($lblStatus.Text -match "Stopped") {
        # Enable Start button and set normal dark theme colors
        $btnStart.Enabled = $true
        $btnStart.BackColor = $colorButtonBack  # Use predefined background color
        $btnStart.ForeColor = $colorButtonText  # Use predefined text color
        $btnStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat  # Flat button style
    }
    # Check if status label shows "Running"
    elseif ($lblStatus.Text -match "Running") {
        # Disable Start button and apply blacked-out appearance
        $btnStart.Enabled = $false
        $btnStart.BackColor = [System.Drawing.Color]::Black       # Set completely black background
        $btnStart.ForeColor = [System.Drawing.Color]::DarkGray   # Set dim text color for disabled state
        $btnStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat  # Maintain flat button style
        $btnStart.FlatAppearance.BorderColor = [System.Drawing.Color]::Black  # Set black border color
    }
}

# =====================
# BACKUP RESTORE FUNCTIONS
# =====================

function Get-LatestBackup {
    # Safety check for root folder
    if ([string]::IsNullOrEmpty($PSScriptRoot)) {
        $txtUpdateLog.AppendText("[ERROR] Root folder path is not set`r`n")
        return $null
    }
    
    $backupFolder = Join-Path $PSScriptRoot "backup"
    
    if (-not (Test-Path $backupFolder)) {
        $txtUpdateLog.AppendText("[ERROR] Backup folder not found: $backupFolder`r`n")
        return $null
    }
    
    $backups = Get-ChildItem -Path $backupFolder -Filter "*.zip" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    
    if ($backups.Count -eq 0) {
        $txtUpdateLog.AppendText("[ERROR] No backup ZIP files found in: $backupFolder`r`n")
        return $null
    }
    
    return $backups[0]
}

function Restore-ServerBackup {
    # Safety check for root folder
    if ([string]::IsNullOrEmpty($PSScriptRoot)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Root folder path is not configured.`n`nPlease check your server settings.",
            "Configuration Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        $txtUpdateLog.AppendText("[ERROR] Root folder path is not set`r`n")
        return
    }
    
    # Confirmation dialog
    $result = [System.Windows.Forms.MessageBox]::Show(
        "This will restore the server from the latest backup.`n`nThe server will be stopped during this process.`n`nContinue?",
        "Restore Backup Confirmation",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }
    
    # Get latest backup
    $latestBackup = Get-LatestBackup
    
    if (-not $latestBackup) {
        [System.Windows.Forms.MessageBox]::Show(
            "No backup files found in the backup folder.`n`nExpected location: $PSScriptRoot\backup",
            "No Backups Found",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    
    # Stop server if running
    $wasRunning = $script:serverRunning
    if ($script:serverRunning) {
        $txtUpdateLog.AppendText("[BACKUP] Stopping server for restore...`r`n")
        Stop-Server
        $sleepEnd = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $sleepEnd) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
    }
    
    try {
        $txtUpdateLog.AppendText("[BACKUP] Starting restore from: $($latestBackup.Name)`r`n")
        $txtUpdateLog.AppendText("[BACKUP] Backup date: $($latestBackup.LastWriteTime)`r`n")
        
        # Define paths
        $backupZipPath = $latestBackup.FullName
        $universeFolder = Join-Path $PSScriptRoot "universe"
        $tempExtractFolder = Join-Path $PSScriptRoot "temp_restore"
        
        # Create temp extraction folder
        if (Test-Path $tempExtractFolder) {
            Remove-Item $tempExtractFolder -Recurse -Force
        }
        New-Item -ItemType Directory -Path $tempExtractFolder -Force | Out-Null
        
        # Extract backup to temp folder
        $txtUpdateLog.AppendText("[BACKUP] Extracting backup archive...`r`n")
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($backupZipPath, $tempExtractFolder)
        
        # Ensure universe folder exists
        if (-not (Test-Path $universeFolder)) {
            New-Item -ItemType Directory -Path $universeFolder -Force | Out-Null
            $txtUpdateLog.AppendText("[BACKUP] Created universe folder`r`n")
        }
        
        # Count files and folders for reporting
        $filesCopied = 0
        $foldersCopied = 0
        
        # Copy all contents from temp folder to universe folder
        $items = Get-ChildItem -Path $tempExtractFolder -Recurse
        
        foreach ($item in $items) {
            $relativePath = $item.FullName.Substring($tempExtractFolder.Length + 1)
            $destination = Join-Path $universeFolder $relativePath
            
            if ($item.PSIsContainer) {
                # Create directory if it doesn't exist
                if (-not (Test-Path $destination)) {
                    New-Item -ItemType Directory -Path $destination -Force | Out-Null
                    $foldersCopied++
                }
            } else {
                # Copy file (overwrite if exists)
                $destDir = Split-Path $destination -Parent
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -Path $item.FullName -Destination $destination -Force
                $filesCopied++
            }
        }
        
        # Clean up temp folder
        Remove-Item $tempExtractFolder -Recurse -Force
        
        $txtUpdateLog.AppendText("[BACKUP] Restore completed successfully!`r`n")
        $txtUpdateLog.AppendText("[BACKUP] Files merged: $filesCopied`r`n")
        $txtUpdateLog.AppendText("[BACKUP] Folders merged: $foldersCopied`r`n")
        
        # Show success message
        [System.Windows.Forms.MessageBox]::Show(
            "Backup restored successfully!`n`nFiles merged: $filesCopied`nFolders merged: $foldersCopied`n`nBackup: $($latestBackup.Name)",
            "Restore Complete",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        
        # Restart server if it was running before
        if ($wasRunning) {
            $restartPrompt = [System.Windows.Forms.MessageBox]::Show(
                "Would you like to restart the server now?",
                "Restart Server",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            if ($restartPrompt -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-Sleep -Seconds 1
                Start-Server
            }
        }
        
    } catch {
        $txtUpdateLog.AppendText("[ERROR] Restore failed: $_`r`n")
        
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to restore backup.`n`nError: $_",
            "Restore Failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        
        # Clean up temp folder if it exists
        if (Test-Path $tempExtractFolder) {
            Remove-Item $tempExtractFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# =====================
# Function: Download-LatestDownloader
# =====================
function Download-LatestDownloader {
    try {
        $txtUpdateLog.AppendText("[INFO] Starting downloader update...`r`n")
        
        # Define paths
        $downloaderZipUrl = "https://downloader.hytale.com/hytale-downloader.zip"
        $tempZipPath = Join-Path $env:TEMP "hytale-downloader.zip"
        $extractPath = $PSScriptRoot
        
        # Download the zip file
        $txtUpdateLog.AppendText("[INFO] Downloading from: $downloaderZipUrl`r`n")
        Invoke-WebRequest -Uri $downloaderZipUrl -OutFile $tempZipPath
        
        # Extract the zip
        $txtUpdateLog.AppendText("[INFO] Extracting to: $extractPath`r`n")
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZipPath, $extractPath)
        
        # Update the downloader path variable
        $script:downloaderPath = Join-Path $extractPath "hytale-downloader-windows-amd64.exe"
        $txtDownloaderPath.Text = $script:downloaderPath
        
        # Clean up temp file
        Remove-Item $tempZipPath -Force
        
        $txtUpdateLog.AppendText("[SUCCESS] Downloader updated successfully!`r`n")
        [System.Windows.Forms.MessageBox]::Show("Downloader updated successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    catch {
        $txtUpdateLog.AppendText("[ERROR] Failed to update downloader: $_`r`n")
        [System.Windows.Forms.MessageBox]::Show("Failed to update downloader: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# ==========================================================================================
# SECTION: MOD MANAGER FUNCTIONS
# ==========================================================================================

# ==========================================================================================
# SECTION: CURSEFORGE API FUNCTIONS
# ==========================================================================================

# =====================
# Function: Load-CurseForgeMetadata
# =====================
# =====================
# Function: Load-CurseForgeMetadata
# =====================
function Load-CurseForgeMetadata {
    if (Test-Path $script:cfMetadataPath) {
        try {
            $json = Get-Content $script:cfMetadataPath -Raw -ErrorAction Stop
            $tempData = $json | ConvertFrom-Json
            
            # Convert PSCustomObject to Hashtable properly (Windows PowerShell compatibility)
            $script:cfMetadata = @{}
            foreach ($property in $tempData.PSObject.Properties) {
                $modFileName = $property.Name
                $modData = $property.Value
                
                # Convert nested object to hashtable
                $script:cfMetadata[$modFileName] = @{
                    cf_project_id = $modData.cf_project_id
                    cf_slug = $modData.cf_slug
                    cf_name = $modData.cf_name
                    cf_author = $modData.cf_author
                    installed_version = $modData.installed_version
                    installed_file_id = $modData.installed_file_id
                    latest_version = $modData.latest_version
                    latest_file_id = $modData.latest_file_id
                    update_available = $modData.update_available
                    last_checked = $modData.last_checked
                    linked_date = $modData.linked_date
                    cf_url = $modData.cf_url
                }
            }
            
            Write-Host "[CF] Loaded metadata for $($script:cfMetadata.Count) mods"
        } catch {
            Write-Host "[CF] Error loading metadata: $_"
            $script:cfMetadata = @{}
        }
    } else {
        $script:cfMetadata = @{}
        Write-Host "[CF] No existing metadata file found"
    }
}

# =====================
# Function: Save-CurseForgeMetadata
# =====================
function Save-CurseForgeMetadata {
    try {
        $json = $script:cfMetadata | ConvertTo-Json -Depth 10
        $json | Set-Content $script:cfMetadataPath -Force
        Write-Host "[CF] Saved metadata for $($script:cfMetadata.Count) mods"
    } catch {
        Write-Host "[CF] Error saving metadata: $_"
    }
}

# =====================
# Function: Get-ModVersionFromFilename
# =====================
function Get-ModVersionFromFilename {
    param([string]$filename)
    
    # Try multiple version patterns
    $patterns = @(
        '[-_]v?(\d+\.\d+(?:\.\d+)?)\.jar$',  # ModName-1.2.3.jar or ModName-v1.2.3.jar
        '[-_](\d+\.\d+(?:\.\d+)?)[_-]',       # ModName-1.2.3-forge.jar
        '\((\d+\.\d+(?:\.\d+)?)\)\.jar$'      # ModName(1.2.3).jar
    )
    
    foreach ($pattern in $patterns) {
        if ($filename -match $pattern) {
            return $matches[1]
        }
    }
    
    return "Unknown"
}

# =====================
# Function: Get-ModNameFromFilename
# =====================
function Get-ModNameFromFilename {
    param([string]$filename)
    
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($filename)
    
    # Remove version patterns
    $cleanName = $baseName -replace '[-_]v?\d+\.\d+(?:\.\d+)?.*$', ''
    $cleanName = $cleanName -replace '[-_](alpha|beta|release|final|forge|fabric|hytale).*$', ''
    
    return $cleanName.Trim()
}

# =====================
# Function: Search-CurseForgeMods
# =====================
function Search-CurseForgeMods {
    param(
        [string]$searchQuery,
        [int]$pageSize = 10
    )
    
    try {
        $headers = @{
            "Accept" = "application/json"
            "x-api-key" = $script:curseForgeApiKey
        }
        
        $encodedQuery = [System.Web.HttpUtility]::UrlEncode($searchQuery)
        $url = "$($script:curseForgeApiBase)/mods/search?gameId=$($script:hytaleGameId)&classId=$($script:hytaleModsClassId)&searchFilter=$encodedQuery&pageSize=$pageSize"
        
        Write-Host "[CF] Searching for: $searchQuery"
        
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        
        if ($response.data) {
            Write-Host "[CF] Found $($response.data.Count) results"
            return $response.data
        } else {
            Write-Host "[CF] No results found"
            return @()
        }
    } catch {
        Write-Host "[CF] Search error: $_"
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to search CurseForge API.`n`nError: $_`n`nPlease check your internet connection and API key.",
            "CurseForge Search Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return @()
    }
}

# =====================
# Function: Get-CurseForgeModInfo
# =====================
function Get-CurseForgeModInfo {
    param([int]$projectId)
    
    try {
        $headers = @{
            "Accept" = "application/json"
            "x-api-key" = $script:curseForgeApiKey
        }
        
        $url = "$($script:curseForgeApiBase)/mods/$projectId"
        
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        
        if ($response.data) {
            return $response.data
        }
        return $null
    } catch {
        Write-Host "[CF] Error getting mod info: $_"
        return $null
    }
}

# =====================
# Function: Show-CurseForgeLinkDialog
# =====================
function Show-CurseForgeLinkDialog {
    if (-not $script:modListView.SelectedItems -or $script:modListView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select a mod from the list first.",
            "No Mod Selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }
    
    $selectedItem = $script:modListView.SelectedItems[0]
    $modFileName = $selectedItem.Text
    
    # Extract suggested search term
    $suggestedName = Get-ModNameFromFilename -filename $modFileName
    
    # Create search dialog
    $searchForm = New-Object System.Windows.Forms.Form
    $searchForm.Text = "Link to CurseForge"
    $searchForm.Size = New-Object System.Drawing.Size(700, 600)
    $searchForm.StartPosition = "CenterParent"
    $searchForm.BackColor = $colorBack
    $searchForm.FormBorderStyle = 'FixedDialog'
    $searchForm.MaximizeBox = $false
    
    # Mod file label
    $lblModFile = New-Object System.Windows.Forms.Label
    $lblModFile.Text = "Mod File: $modFileName"
    $lblModFile.Location = New-Object System.Drawing.Point(20, 20)
    $lblModFile.Size = New-Object System.Drawing.Size(660, 25)
    $lblModFile.ForeColor = $colorText
    $lblModFile.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $searchForm.Controls.Add($lblModFile)
    
    # Search box label
    $lblSearch = New-Object System.Windows.Forms.Label
    $lblSearch.Text = "Search CurseForge:"
    $lblSearch.Location = New-Object System.Drawing.Point(20, 60)
    $lblSearch.Size = New-Object System.Drawing.Size(150, 20)
    $lblSearch.ForeColor = $colorText
    $searchForm.Controls.Add($lblSearch)
    
    # Search textbox
    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location = New-Object System.Drawing.Point(20, 85)
    $txtSearch.Size = New-Object System.Drawing.Size(550, 25)
    $txtSearch.Text = $suggestedName
    $txtSearch.BackColor = $colorTextboxBack
    $txtSearch.ForeColor = $colorTextboxText
    $searchForm.Controls.Add($txtSearch)
    
    # Search button
    $btnSearch = New-Object System.Windows.Forms.Button
    $btnSearch.Text = "Search"
    $btnSearch.Location = New-Object System.Drawing.Point(580, 83)
    $btnSearch.Size = New-Object System.Drawing.Size(100, 30)
    $btnSearch.BackColor = [System.Drawing.Color]::FromArgb(64, 96, 224)
    $btnSearch.ForeColor = $colorButtonText
    $btnSearch.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $searchForm.Controls.Add($btnSearch)
    
    # Results ListView
    $lvResults = New-Object System.Windows.Forms.ListView
    $lvResults.Location = New-Object System.Drawing.Point(20, 130)
    $lvResults.Size = New-Object System.Drawing.Size(660, 350)
    $lvResults.View = 'Details'
    $lvResults.FullRowSelect = $true
    $lvResults.GridLines = $true
    $lvResults.BackColor = $colorTextboxBack
    $lvResults.ForeColor = $colorTextboxText
    $lvResults.Columns.Add("Mod Name", 250) | Out-Null
    $lvResults.Columns.Add("Author", 120) | Out-Null
    $lvResults.Columns.Add("Downloads", 100) | Out-Null
    $lvResults.Columns.Add("Project ID", 100) | Out-Null
    $searchForm.Controls.Add($lvResults)
    
    # Manual ID label
    $lblManual = New-Object System.Windows.Forms.Label
    $lblManual.Text = "Or enter Project ID manually:"
    $lblManual.Location = New-Object System.Drawing.Point(20, 495)
    $lblManual.Size = New-Object System.Drawing.Size(200, 20)
    $lblManual.ForeColor = $colorText
    $searchForm.Controls.Add($lblManual)
    
    # Manual ID textbox
    $txtProjectId = New-Object System.Windows.Forms.TextBox
    $txtProjectId.Location = New-Object System.Drawing.Point(220, 492)
    $txtProjectId.Size = New-Object System.Drawing.Size(150, 25)
    $txtProjectId.BackColor = $colorTextboxBack
    $txtProjectId.ForeColor = $colorTextboxText
    $searchForm.Controls.Add($txtProjectId)
    
    # Link button
    $btnLink = New-Object System.Windows.Forms.Button
    $btnLink.Text = "Link Selected"
    $btnLink.Location = New-Object System.Drawing.Point(480, 520)
    $btnLink.Size = New-Object System.Drawing.Size(200, 35)
    $btnLink.BackColor = [System.Drawing.Color]::FromArgb(32, 144, 32)
    $btnLink.ForeColor = $colorButtonText
    $btnLink.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnLink.Enabled = $false
    $searchForm.Controls.Add($btnLink)
    
    # Cancel button
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(270, 520)
    $btnCancel.Size = New-Object System.Drawing.Size(200, 35)
    $btnCancel.BackColor = $colorButtonBack
    $btnCancel.ForeColor = $colorButtonText
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.Add_Click({ $searchForm.Close() })
    $searchForm.Controls.Add($btnCancel)
    
    # Search function
    $performSearch = {
        $query = $txtSearch.Text.Trim()
        if ([string]::IsNullOrEmpty($query)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Please enter a search term.",
                "Search Required",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }
        
        $lvResults.Items.Clear()
        $btnLink.Enabled = $false
        
        # Show searching message
        $searchItem = New-Object System.Windows.Forms.ListViewItem("Searching CurseForge...")
        $lvResults.Items.Add($searchItem) | Out-Null
        $searchForm.Refresh()
        
        # Perform search
        $results = Search-CurseForgeMods -searchQuery $query
        
        $lvResults.Items.Clear()
        
        if ($results -and $results.Count -gt 0) {
            foreach ($mod in $results) {
                $item = New-Object System.Windows.Forms.ListViewItem($mod.name)
                
                # Get author name
                $authorName = "Unknown"
                if ($mod.authors -and $mod.authors.Count -gt 0) {
                    $authorName = $mod.authors[0].name
                }
                $item.SubItems.Add($authorName) | Out-Null
                
                # Format download count
                $downloads = if ($mod.downloadCount) { "{0:N0}" -f $mod.downloadCount } else { "0" }
                $item.SubItems.Add($downloads) | Out-Null
                
                # Project ID
                $item.SubItems.Add($mod.id.ToString()) | Out-Null
                
                # Store full mod data in tag
                $item.Tag = $mod
                
                $lvResults.Items.Add($item) | Out-Null
            }
        } else {
            $noResults = New-Object System.Windows.Forms.ListViewItem("No results found")
            $lvResults.Items.Add($noResults) | Out-Null
        }
    }
    
    # Search button click
    $btnSearch.Add_Click($performSearch)
    
    # Enter key in search box triggers search
    $txtSearch.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq 'Enter') {
            & $performSearch
            $e.SuppressKeyPress = $true
        }
    })
    
    # Enable Link button when item selected
    $lvResults.Add_SelectedIndexChanged({
        $btnLink.Enabled = ($lvResults.SelectedItems.Count -gt 0)
    })
    
    # Link button click
    $btnLink.Add_Click({
        $selectedMod = $null
        $projectId = 0
        
        # Check if manual ID was entered
        if (-not [string]::IsNullOrWhiteSpace($txtProjectId.Text)) {
            if ([int]::TryParse($txtProjectId.Text, [ref]$projectId)) {
                # Get mod info from API
                $modInfo = Get-CurseForgeModInfo -projectId $projectId
                if ($modInfo) {
                    $selectedMod = $modInfo
                } else {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Could not find mod with Project ID: $projectId",
                        "Invalid Project ID",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                    return
                }
            } else {
                [System.Windows.Forms.MessageBox]::Show(
                    "Invalid Project ID. Please enter a number.",
                    "Invalid Input",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                return
            }
        }
        # Check if search result was selected
        elseif ($lvResults.SelectedItems.Count -gt 0) {
            $selectedMod = $lvResults.SelectedItems[0].Tag
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                "Please select a mod from the search results or enter a Project ID.",
                "No Selection",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }
        
        if ($selectedMod) {
            # Get installed version
            $installedVersion = Get-ModVersionFromFilename -filename $modFileName
            
            # Get latest file info
            $latestFile = $null
            $latestVersion = "Unknown"
            $latestFileId = 0
            
            if ($selectedMod.latestFiles -and $selectedMod.latestFiles.Count -gt 0) {
                $latestFile = $selectedMod.latestFiles[0]
                $latestVersion = if ($latestFile.displayName) { 
                    Get-ModVersionFromFilename -filename $latestFile.fileName 
                } else { 
                    "Unknown" 
                }
                $latestFileId = $latestFile.id
            }
            
            # Get author
            $author = "Unknown"
            if ($selectedMod.authors -and $selectedMod.authors.Count -gt 0) {
                $author = $selectedMod.authors[0].name
            }
            
            # Create metadata entry
            $metadata = @{
                cf_project_id = $selectedMod.id
                cf_slug = $selectedMod.slug
                cf_name = $selectedMod.name
                cf_author = $author
                installed_version = $installedVersion
                installed_file_id = 0
                latest_version = $latestVersion
                latest_file_id = $latestFileId
                update_available = $false
                last_checked = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                linked_date = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                cf_url = "https://www.curseforge.com/hytale/mods/$($selectedMod.slug)"
            }
            
            # Check if update available
            if ($installedVersion -ne "Unknown" -and $latestVersion -ne "Unknown") {
                try {
                    $v1 = [version]$installedVersion
                    $v2 = [version]$latestVersion
                    $metadata.update_available = $v2 -gt $v1
                } catch {
                    # Version comparison failed, mark as unknown
                    $metadata.update_available = $false
                }
            }
            
            # Save to metadata
            $script:cfMetadata[$modFileName] = $metadata
            Save-CurseForgeMetadata
            
            [System.Windows.Forms.MessageBox]::Show(
                "Successfully linked '$modFileName' to CurseForge project:`n`n" +
                "Name: $($selectedMod.name)`n" +
                "Author: $author`n" +
                "Project ID: $($selectedMod.id)`n" +
                "Installed Version: $installedVersion`n" +
                "Latest Version: $latestVersion",
                "Mod Linked",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            
            # Refresh mod list to show new status
            Refresh-ModList
            
            $searchForm.Close()
        }
    })
    
    # Show form
    $searchForm.ShowDialog() | Out-Null
}



# =====================
# Function: Refresh-ModList
# =====================
# PURPOSE: Scans the mods and mods_disabled folders and populates the ListView
function Refresh-ModList {
    if (-not $script:modListView) { return }
    
    $script:modListView.Items.Clear()
    
    # Ensure mods directories exist
    if (-not (Test-Path $script:modsPath)) {
        New-Item -Path $script:modsPath -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $script:modsDisabledPath)) {
        New-Item -Path $script:modsDisabledPath -ItemType Directory -Force | Out-Null
    }
    
    # Track mod base names for conflict detection
    $modGroups = @{}
    
    # Get enabled mods (in /mods folder)
    $enabledMods = Get-ChildItem -Path $script:modsPath -Filter "*.jar" -ErrorAction SilentlyContinue
    foreach ($mod in $enabledMods) {
        $item = New-Object System.Windows.Forms.ListViewItem($mod.Name)
        
        # Status
        $item.SubItems.Add("ENABLED") | Out-Null
        $item.ForeColor = [System.Drawing.Color]::LimeGreen
        
        # Version
        $version = Get-ModVersionFromFilename -filename $mod.Name
        $item.SubItems.Add($version) | Out-Null
        
        # CF Status
        $cfStatus = "Not Linked"
        if ($script:cfMetadata.ContainsKey($mod.Name)) {
            $meta = $script:cfMetadata[$mod.Name]
            if ($meta.update_available -eq $true) {
                $cfStatus = "Update! ($($meta.latest_version))"
                $item.ForeColor = [System.Drawing.Color]::Orange
            } else {
                $cfStatus = "Linked"
            }
        }
        $item.SubItems.Add($cfStatus) | Out-Null
        
        # File Size
        $fileSizeMB = [math]::Round($mod.Length / 1MB, 2)
        if ($fileSizeMB -lt 0.01) {
            $fileSizeKB = [math]::Round($mod.Length / 1KB, 2)
            $item.SubItems.Add("$fileSizeKB KB") | Out-Null
        } else {
            $item.SubItems.Add("$fileSizeMB MB") | Out-Null
        }
        
        # File Path
        $item.SubItems.Add($mod.FullName) | Out-Null
        
        $item.Tag = @{ Enabled = $true; Path = $mod.FullName }
        $script:modListView.Items.Add($item) | Out-Null
        
        # Track for conflicts
        $baseName = Get-ModNameFromFilename -filename $mod.Name
        if (-not $modGroups.ContainsKey($baseName)) {
            $modGroups[$baseName] = @()
        }
        $modGroups[$baseName] += $item
    }
    
    # Get disabled mods (in /mods_disabled folder)
    $disabledMods = Get-ChildItem -Path $script:modsDisabledPath -Filter "*.jar" -ErrorAction SilentlyContinue
    foreach ($mod in $disabledMods) {
        $item = New-Object System.Windows.Forms.ListViewItem($mod.Name)
        
        # Status
        $item.SubItems.Add("DISABLED") | Out-Null
        $item.ForeColor = [System.Drawing.Color]::Red
        
        # Version
        $version = Get-ModVersionFromFilename -filename $mod.Name
        $item.SubItems.Add($version) | Out-Null
        
        # CF Status
        $cfStatus = "Not Linked"
        if ($script:cfMetadata.ContainsKey($mod.Name)) {
            $meta = $script:cfMetadata[$mod.Name]
            if ($meta.update_available -eq $true) {
                $cfStatus = "Update! ($($meta.latest_version))"
            } else {
                $cfStatus = "Linked"
            }
        }
        $item.SubItems.Add($cfStatus) | Out-Null
        
        # File Size
        $fileSizeMB = [math]::Round($mod.Length / 1MB, 2)
        if ($fileSizeMB -lt 0.01) {
            $fileSizeKB = [math]::Round($mod.Length / 1KB, 2)
            $item.SubItems.Add("$fileSizeKB KB") | Out-Null
        } else {
            $item.SubItems.Add("$fileSizeMB MB") | Out-Null
        }
        
        # File Path
        $item.SubItems.Add($mod.FullName) | Out-Null
        
        $item.Tag = @{ Enabled = $false; Path = $mod.FullName }
        $script:modListView.Items.Add($item) | Out-Null
    }
    
    # Mark version conflicts
    foreach ($baseName in $modGroups.Keys) {
        $group = $modGroups[$baseName]
        if ($group.Count -gt 1) {
            foreach ($item in $group) {
                $currentStatus = $item.SubItems[1].Text
                $item.SubItems[1].Text = "$currentStatus (Warning)"
                $item.ForeColor = [System.Drawing.Color]::Yellow
            }
        }
    }
}

# =====================
# Function: Toggle-ModState
# =====================
# PURPOSE: Enables or disables the selected mod by moving it between folders
function Toggle-ModState {
    if (-not $script:modListView.SelectedItems -or $script:modListView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a mod first!", "No Selection", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $selectedItem = $script:modListView.SelectedItems[0]
    $modData = $selectedItem.Tag
    $modPath = $modData.Path
    $modName = [System.IO.Path]::GetFileName($modPath)
    
    try {
        if ($modData.Enabled) {
            # DISABLE: Move from /mods to /mods_disabled
            $destinationPath = Join-Path $script:modsDisabledPath $modName
            Move-Item -Path $modPath -Destination $destinationPath -Force
            [System.Windows.Forms.MessageBox]::Show("Mod '$modName' has been disabled!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            # ENABLE: Move from /mods_disabled to /mods
            $destinationPath = Join-Path $script:modsPath $modName
            Move-Item -Path $modPath -Destination $destinationPath -Force
            [System.Windows.Forms.MessageBox]::Show("Mod '$modName' has been enabled!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        
        Refresh-ModList
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error toggling mod state: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# =====================
# Function: Open-ModsFolder
# =====================
# PURPOSE: Opens the mods folder in Windows Explorer
function Open-ModsFolder {
    if (-not (Test-Path $script:modsPath)) {
        New-Item -Path $script:modsPath -ItemType Directory -Force | Out-Null
    }
    Start-Process explorer.exe -ArgumentList $script:modsPath
}

# =====================
# Function: Remove-SelectedMod
# =====================
# PURPOSE: Permanently deletes the selected mod after confirmation
function Remove-SelectedMod {
    if (-not $script:modListView.SelectedItems -or $script:modListView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a mod to remove!", "No Selection", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $selectedItem = $script:modListView.SelectedItems[0]
    $modData = $selectedItem.Tag
    $modPath = $modData.Path
    $modName = [System.IO.Path]::GetFileName($modPath)
    
    # Confirmation dialog
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Are you sure you want to PERMANENTLY DELETE this mod?`n`nMod: $modName`n`nThis action cannot be undone!",
        "Confirm Deletion",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Remove-Item -Path $modPath -Force
            [System.Windows.Forms.MessageBox]::Show("Mod '$modName' has been permanently deleted!", "Deleted", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Refresh-ModList
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error deleting mod: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
}

# =====================
# Function: Open-CurseForge
# =====================
# PURPOSE: Opens the Hytale CurseForge page in the default browser
function Open-CurseForge {
    Start-Process "https://www.curseforge.com/hytale"
}

# =====================
# Function: Handle-ModDragDrop
# =====================
# PURPOSE: Handles files dropped into the mod list view
function Handle-ModDragDrop {
    param($sender, $e)
    
    $files = $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    
    if ($files) {
        $copiedCount = 0
        $skippedCount = 0
        
        foreach ($file in $files) {
            if ([System.IO.Path]::GetExtension($file) -eq ".jar") {
                try {
                    $fileName = [System.IO.Path]::GetFileName($file)
                    $destination = Join-Path $script:modsPath $fileName
                    
                    if (Test-Path $destination) {
                        $result = [System.Windows.Forms.MessageBox]::Show(
                            "Mod '$fileName' already exists. Overwrite?",
                            "File Exists",
                            [System.Windows.Forms.MessageBoxButtons]::YesNo,
                            [System.Windows.Forms.MessageBoxIcon]::Question
                        )
                        
                        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                            Copy-Item -Path $file -Destination $destination -Force
                            $copiedCount++
                        } else {
                            $skippedCount++
                        }
                    } else {
                        Copy-Item -Path $file -Destination $destination -Force
                        $copiedCount++
                    }
                } catch {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Error copying mod: $_",
                        "Error",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                }
            } else {
                $skippedCount++
            }
        }
        
        if ($copiedCount -gt 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Successfully installed $copiedCount mod(s)!`nSkipped: $skippedCount",
                "Mods Installed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            Refresh-ModList
        } elseif ($skippedCount -gt 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No valid .jar files were added. Only .jar files are supported!",
                "No Mods Added",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    }
}

# =====================
# Function: Handle-ModDragEnter
# =====================
# PURPOSE: Validates drag-drop operation
function Handle-ModDragEnter {
    param($sender, $e)
    
    if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $e.Effect = [Windows.Forms.DragDropEffects]::Copy
    } else {
        $e.Effect = [Windows.Forms.DragDropEffects]::None
    }
}

# =====================
# Function: Check-ModConflicts
# =====================
# PURPOSE: Checks for potential mod conflicts
function Check-ModConflicts {
    $conflicts = @()
    
    # Get all enabled mods
    $enabledMods = Get-ChildItem -Path $script:modsPath -Filter "*.jar" -ErrorAction SilentlyContinue
    
    # Simple conflict detection based on similar names
    foreach ($mod1 in $enabledMods) {
        foreach ($mod2 in $enabledMods) {
            if ($mod1.Name -ne $mod2.Name) {
                # Check if mod names are similar (might be different versions)
                $name1 = $mod1.BaseName -replace '[-_]\d+.*$', ''
                $name2 = $mod2.BaseName -replace '[-_]\d+.*$', ''
                
                if ($name1 -eq $name2) {
                    $conflicts += "POSSIBLE CONFLICT: '$($mod1.Name)' and '$($mod2.Name)' appear to be different versions of the same mod"
                }
            }
        }
    }
    
    # Known conflict patterns (you can expand this list)
    $knownConflicts = @{
        "OptiFine" = @("Sodium", "Iris")
        "Sodium" = @("OptiFine")
        "Iris" = @("OptiFine")
    }
    
    foreach ($mod in $enabledMods) {
        foreach ($conflictKey in $knownConflicts.Keys) {
            if ($mod.Name -like "*$conflictKey*") {
                foreach ($conflictMod in $knownConflicts[$conflictKey]) {
                    $hasConflict = $enabledMods | Where-Object { $_.Name -like "*$conflictMod*" }
                    if ($hasConflict) {
                        $conflicts += "KNOWN CONFLICT: '$($mod.Name)' conflicts with '$($hasConflict.Name)'"
                    }
                }
            }
        }
    }
    
    if ($conflicts.Count -gt 0) {
        $conflictMessage = "WARNING: Potential mod conflicts detected:`n`n" + ($conflicts -join "`n`n")
        [System.Windows.Forms.MessageBox]::Show(
            $conflictMessage,
            "Mod Conflicts Detected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "No mod conflicts detected!",
            "Conflict Check",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
}

# ==========================================================================================
# SECTION: THEME SWITCHER FUNCTIONS
# ==========================================================================================

# =====================
# Function: Apply-Theme
# =====================
# PURPOSE: Applies the selected theme to all GUI elements
function Apply-Theme {
    param([string]$themeName)
    
    if (-not $script:themes.ContainsKey($themeName)) {
        [System.Windows.Forms.MessageBox]::Show("Theme '$themeName' not found!", "Error")
        return
    }
    
    $theme = $script:themes[$themeName]
    $script:currentTheme = $themeName
    
    # Update global color variables
    $script:colorBack = $theme.Back
    $script:colorText = $theme.Text
    $script:colorTextboxBack = $theme.TextboxBack
    $script:colorTextboxText = $theme.TextboxText
    $script:colorButtonBack = $theme.ButtonBack
    $script:colorButtonText = $theme.ButtonText
    $script:colorConsoleBack = $theme.ConsoleBack
    $script:colorConsoleText = $theme.ConsoleText
    
    # Apply to main form
    $form.BackColor = $theme.Back
    
    # Apply to all tabs
    foreach ($tab in $tabs.TabPages) {
        $tab.BackColor = $theme.Back
        
        # Apply to all controls in each tab
        foreach ($control in $tab.Controls) {
            if ($control -is [System.Windows.Forms.Label]) {
                $control.ForeColor = $theme.Text
            }
            elseif ($control -is [System.Windows.Forms.TextBox] -or $control -is [System.Windows.Forms.RichTextBox]) {
                if ($control.Name -notlike "*Console*" -and $control.Name -notlike "*Log*") {
                    $control.BackColor = $theme.TextboxBack
                    $control.ForeColor = $theme.TextboxText
                } else {
                    $control.BackColor = $theme.ConsoleBack
                    $control.ForeColor = $theme.ConsoleText
                }
            }
            elseif ($control -is [System.Windows.Forms.Button]) {
                # Don't override special colored buttons (like Delete Mod button)
                if ($control.BackColor.R -eq 120 -and $control.BackColor.G -eq 40) {
                    # Keep red delete button
                    continue
                }
                elseif ($control.BackColor.R -eq 240 -and $control.BackColor.G -eq 100) {
                    # Keep orange CurseForge button
                    continue
                }
                else {
                    $control.BackColor = $theme.ButtonBack
                    $control.ForeColor = $theme.ButtonText
                }
            }
            elseif ($control -is [System.Windows.Forms.ListView]) {
                $control.BackColor = $theme.TextboxBack
                $control.ForeColor = $theme.TextboxText
            }
        }
    }
    
    # Refresh mod list to reapply colors
    if ($script:modListView) {
        Refresh-ModList
    }
    
    # Save theme preference
    Save-Settings
    
    [System.Windows.Forms.MessageBox]::Show(
        "Theme '$themeName' applied successfully!",
        "Theme Changed",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

# =====================
# Function: Get-ServerIP
# =====================
# PURPOSE: Gets the server's public and local IP addresses
function Get-ServerIP {
    try {
        # Get local IP
        $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.PrefixOrigin -eq "Dhcp" } | Select-Object -First 1).IPAddress
        
        # Get public IP
        try {
            $publicIP = (Invoke-RestMethod -Uri "https://api.ipify.org?format=text" -TimeoutSec 5).Trim()
        } catch {
            $publicIP = "Unable to fetch"
        }
        
        # Get server port from config
        $serverPort = "24454"  # Default Hytale port
        if (Test-Path $script:configPath) {
            try {
                $configContent = Get-Content -Path $script:configPath -Raw | ConvertFrom-Json
                if ($configContent.port) {
                    $serverPort = $configContent.port
                }
            } catch {
                # Use default if can't read config
            }
        }
        
        return @{
            LocalIP = $localIP
            PublicIP = $publicIP
            Port = $serverPort
        }
    } catch {
        return @{
            LocalIP = "Error"
            PublicIP = "Error"
            Port = "24454"
        }
    }
}

# =====================
# Function: Copy-ServerIP
# =====================
# PURPOSE: Copies server IP to clipboard and shows info
function Copy-ServerIP {
    $serverInfo = Get-ServerIP
    
    $ipText = "$($serverInfo.PublicIP):$($serverInfo.Port)"
    
    # Copy to clipboard
    [System.Windows.Forms.Clipboard]::SetText($ipText)
    
    $message = @"
Server IP Information Copied!

Public IP: $($serverInfo.PublicIP)
Local IP: $($serverInfo.LocalIP)
Port: $($serverInfo.Port)

Full Address: $ipText

Share this with friends to connect!
(Copied to clipboard)
"@
    
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        "Server IP",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

# =====================
# Function: Check-AllModUpdates
# =====================
function Check-AllModUpdates {
    # Count how many mods are linked
    $linkedCount = 0
    foreach ($key in $script:cfMetadata.Keys) {
        $linkedCount++
    }
    
    if ($linkedCount -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No mods are linked to CurseForge yet!`n`nUse the 'Link to CurseForge' button to link your mods first.",
            "No Linked Mods",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }
    
    Write-Host "[CF] Checking updates for $linkedCount linked mod(s)..."
    
    $updatesFound = 0
    $checkedCount = 0
    
    foreach ($modFileName in $script:cfMetadata.Keys) {
        $meta = $script:cfMetadata[$modFileName]
        $projectId = $meta.cf_project_id
        
        Write-Host "[CF] Checking $modFileName (Project ID: $projectId)..."
        
        # Get latest mod info from CurseForge
        $modInfo = Get-CurseForgeModInfo -projectId $projectId
        
        if ($modInfo -and $modInfo.latestFiles -and $modInfo.latestFiles.Count -gt 0) {
            $latestFile = $modInfo.latestFiles[0]
            $latestVersion = Get-ModVersionFromFilename -filename $latestFile.fileName
            $installedVersion = $meta.installed_version
            
            # Update metadata with latest info
            $meta.latest_version = $latestVersion
            $meta.latest_file_id = $latestFile.id
            $meta.last_checked = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            
            # Compare versions
            if ($installedVersion -ne "Unknown" -and $latestVersion -ne "Unknown") {
                try {
                    $v1 = [version]$installedVersion
                    $v2 = [version]$latestVersion
                    if ($v2 -gt $v1) {
                        $meta.update_available = $true
                        $updatesFound++
                        Write-Host "[CF] UPDATE AVAILABLE: $modFileName ($installedVersion -> $latestVersion)"
                    } else {
                        $meta.update_available = $false
                        Write-Host "[CF] Up to date: $modFileName ($installedVersion)"
                    }
                } catch {
                    $meta.update_available = $false
                    Write-Host "[CF] Could not compare versions for $modFileName"
                }
            } else {
                $meta.update_available = $false
            }
            
            $checkedCount++
        } else {
            Write-Host "[CF] Could not get update info for $modFileName"
        }
    }
    
    # Save updated metadata
    Save-CurseForgeMetadata
    
    # Refresh the mod list to show update indicators
    Refresh-ModList
    
    # Show results
    if ($updatesFound -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Update check complete!`n`n" +
            "Checked: $checkedCount mod(s)`n" +
            "Updates available: $updatesFound mod(s)`n`n" +
            "Mods with updates are marked with a '!' in orange.",
            "Updates Found!",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Update check complete!`n`n" +
            "Checked: $checkedCount mod(s)`n" +
            "All linked mods are up to date! :)`n",
            "No Updates",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
}

# =====================
# Function: Update-SelectedMod
# =====================
function Update-SelectedMod {
    # Check if a mod is selected
    if (-not $script:modListView.SelectedItems -or $script:modListView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select a mod from the list first!",
            "No Mod Selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }
    
    $selectedItem = $script:modListView.SelectedItems[0]
    $modFileName = $selectedItem.Text
    
    # Check if mod is linked
    if (-not $script:cfMetadata.ContainsKey($modFileName)) {
        [System.Windows.Forms.MessageBox]::Show(
            "This mod is not linked to CurseForge!`n`nUse 'Link to CurseForge' first.",
            "Not Linked",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }
    
    $meta = $script:cfMetadata[$modFileName]
    
    # Check if update is available
    if (-not $meta.update_available) {
        [System.Windows.Forms.MessageBox]::Show(
            "This mod is already up to date!`n`n" +
            "Installed: $($meta.installed_version)`n" +
            "Latest: $($meta.latest_version)`n`n" +
            "Click 'Check for Updates' to refresh.",
            "Already Up to Date",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }
    
    # Confirm update
    $confirmResult = [System.Windows.Forms.MessageBox]::Show(
        "Update this mod?`n`n" +
        "Mod: $($meta.cf_name)`n" +
        "Current Version: $($meta.installed_version)`n" +
        "New Version: $($meta.latest_version)`n`n" +
        "The new version will be downloaded to the disabled mods folder.`n" +
        "You can enable it manually after reviewing.",
        "Confirm Update",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    if ($confirmResult -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }
    
    # Get download URL from CurseForge
    try {
        $headers = @{
            "Accept" = "application/json"
            "x-api-key" = $script:curseForgeApiKey
        }
        
        $fileUrl = "$($script:curseForgeApiBase)/mods/$($meta.cf_project_id)/files/$($meta.latest_file_id)"
        
        Write-Host "[CF] Getting download URL for file ID: $($meta.latest_file_id)"
        
        $fileResponse = Invoke-RestMethod -Uri $fileUrl -Headers $headers -Method Get -ErrorAction Stop
        
        if (-not $fileResponse.data.downloadUrl) {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not get download URL from CurseForge.`n`nThe mod author may have disabled automatic downloads.",
                "Download Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return
        }
        
        $downloadUrl = $fileResponse.data.downloadUrl
        $newFileName = $fileResponse.data.fileName
        
        Write-Host "[CF] Download URL: $downloadUrl"
        Write-Host "[CF] New file name: $newFileName"
        
        # Download to disabled folder
        $downloadPath = Join-Path $script:modsDisabledPath $newFileName
        
        Write-Host "[CF] Downloading to: $downloadPath"
        
        # Show downloading message
        $downloadForm = New-Object System.Windows.Forms.Form
        $downloadForm.Text = "Downloading Update..."
        $downloadForm.Size = New-Object System.Drawing.Size(400, 150)
        $downloadForm.StartPosition = "CenterParent"
        $downloadForm.BackColor = $colorBack
        $downloadForm.FormBorderStyle = 'FixedDialog'
        $downloadForm.ControlBox = $false
        
        $lblDownloading = New-Object System.Windows.Forms.Label
        $lblDownloading.Text = "Downloading $newFileName...`n`nPlease wait..."
        $lblDownloading.Location = New-Object System.Drawing.Point(20, 30)
        $lblDownloading.Size = New-Object System.Drawing.Size(360, 80)
        $lblDownloading.ForeColor = $colorText
        $lblDownloading.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $downloadForm.Controls.Add($lblDownloading)
        
        $downloadForm.Show()
        $downloadForm.Refresh()
        
        # Download file
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -ErrorAction Stop
        
        $downloadForm.Close()
        
        Write-Host "[CF] Download complete!"
        
        # Ask what to do with old version
        $oldModPath = $selectedItem.Tag.Path
        $oldModName = [System.IO.Path]::GetFileName($oldModPath)
        
        $oldModResult = [System.Windows.Forms.MessageBox]::Show(
            "Update downloaded successfully!`n`n" +
            "New version: $newFileName`n" +
            "Downloaded to: mods_disabled folder`n`n" +
            "What should we do with the old version?`n" +
            "$oldModName`n`n" +
            "YES = Keep old version in disabled folder (backup)`n" +
            "NO = Delete old version permanently",
            "Old Version Handling",
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        
        if ($oldModResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            # Move old version to disabled folder
            if (Test-Path $oldModPath) {
                $oldBackupPath = Join-Path $script:modsDisabledPath $oldModName
                
                # If old file with same name exists in disabled, rename it
                if (Test-Path $oldBackupPath) {
                    $backupName = [System.IO.Path]::GetFileNameWithoutExtension($oldModName)
                    $backupExt = [System.IO.Path]::GetExtension($oldModName)
                    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    $oldBackupPath = Join-Path $script:modsDisabledPath "${backupName}_backup_${timestamp}${backupExt}"
                }
                
                Move-Item -Path $oldModPath -Destination $oldBackupPath -Force
                Write-Host "[CF] Moved old version to: $oldBackupPath"
            }
        }
        elseif ($oldModResult -eq [System.Windows.Forms.DialogResult]::No) {
            # Delete old version
            if (Test-Path $oldModPath) {
                Remove-Item -Path $oldModPath -Force
                Write-Host "[CF] Deleted old version: $oldModPath"
            }
        }
        # If Cancel, do nothing with old file
        
        # Update metadata
        $script:cfMetadata.Remove($modFileName)
        $script:cfMetadata[$newFileName] = @{
            cf_project_id = $meta.cf_project_id
            cf_slug = $meta.cf_slug
            cf_name = $meta.cf_name
            cf_author = $meta.cf_author
            installed_version = $meta.latest_version
            installed_file_id = $meta.latest_file_id
            latest_version = $meta.latest_version
            latest_file_id = $meta.latest_file_id
            update_available = $false
            last_checked = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            linked_date = $meta.linked_date
            cf_url = $meta.cf_url
        }
        
        Save-CurseForgeMetadata
        
        # Refresh mod list
        Refresh-ModList
        
        [System.Windows.Forms.MessageBox]::Show(
            "Update complete!`n`n" +
            "New version: $newFileName`n" +
            "Location: mods_disabled folder`n`n" +
            "Enable the new version when you're ready to use it!",
            "Update Successful",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error downloading update:`n`n$_",
            "Download Failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        Write-Host "[CF] Download error: $_"
    }
}

# =====================
# Function: Update-ModNotes
# =====================
# PURPOSE: Save custom notes/description for the selected mod
function Update-ModNotes {
    if (-not $script:modListView.SelectedItems -or $script:modListView.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select a mod first!",
            "No Mod Selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }
    
    $selectedItem = $script:modListView.SelectedItems[0]
    $modFileName = $selectedItem.Text
    $notes = $script:txtModNotes.Text
    
    # Load existing notes data
    $notesPath = Join-Path $PSScriptRoot "mod_notes.json"
    $notesData = @{}
    
    if (Test-Path $notesPath) {
        try {
            $json = Get-Content $notesPath -Raw -ErrorAction Stop
            $tempData = $json | ConvertFrom-Json
            
            # Convert PSCustomObject to Hashtable properly
            foreach ($property in $tempData.PSObject.Properties) {
                $notesData[$property.Name] = $property.Value
            }
        } catch {
            Write-Host "Error loading notes: $_"
        }
    }
    
    # Update or add notes for this mod
    $notesData[$modFileName] = $notes
    
    # Save back to file
    try {
        $json = $notesData | ConvertTo-Json -Depth 10
        $json | Set-Content $notesPath -Force
        
        [System.Windows.Forms.MessageBox]::Show(
            "Notes saved for '$modFileName'!",
            "Notes Saved",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error saving notes: $_",
            "Save Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# =====================
# Function: Show-ModNotes
# =====================
# PURPOSE: Display saved notes when a mod is selected
function Show-ModNotes {
    if (-not $script:modListView.SelectedItems -or $script:modListView.SelectedItems.Count -eq 0) {
        $script:txtModNotes.Text = "Select a mod to view or edit notes..."
        $script:txtModNotes.ReadOnly = $true
        return
    }
    
    $selectedItem = $script:modListView.SelectedItems[0]
    $modFileName = $selectedItem.Text
    
    # Load notes data
    $notesPath = Join-Path $PSScriptRoot "mod_notes.json"
    
    if (Test-Path $notesPath) {
        try {
            $json = Get-Content $notesPath -Raw -ErrorAction Stop
            $tempData = $json | ConvertFrom-Json
            
            # Convert PSCustomObject to Hashtable properly
            $notesData = @{}
            foreach ($property in $tempData.PSObject.Properties) {
                $notesData[$property.Name] = $property.Value
            }
            
            if ($notesData.ContainsKey($modFileName)) {
                $script:txtModNotes.Text = $notesData[$modFileName]
            } else {
                $script:txtModNotes.Text = "No notes for this mod yet. Click 'Save Notes' to add some!"
            }
        } catch {
            Write-Host "Error loading notes for ${modFileName}: $_"
            $script:txtModNotes.Text = "Error loading notes. Check the console for details."
        }
    } else {
        $script:txtModNotes.Text = "No notes for this mod yet. Click 'Save Notes' to add some!"
    }
    
    # Enable editing
    $script:txtModNotes.ReadOnly = $false
}

# =====================
# Function: Get-ModConfigFolders
# =====================
# PURPOSE:
# Scans the mods folder for mod configuration directories and their config files.
# Mods typically create folders with their config files after first run.
#
# WHY THIS EXISTS:
# - Provides a way to discover available mod config files
# - Allows browsing mod config structure without file explorer
# - Returns organized data about each mod's config files
#
# PARAMETERS:
# None
#
# RETURN VALUE:
# - Returns an array of PSCustomObjects containing:
#   - ModName: The name of the mod folder
#   - ConfigPath: Full path to the mod's config folder
#   - ConfigFiles: Array of .json, .conf, .toml files found
#   - FileCount: Number of config files found
#
# OPERATION FLOW:
# Step 1: Check if mods folder exists
# Step 2: Scan for all directories in mods folder
# Step 3: Look for config files in each directory
# Step 4: Return organized results
# =====================
function Get-ModConfigFolders {
    try {
        # Step 1: Verify mods folder exists
        if (-not (Test-Path $script:modsPath)) {
            return @()
        }

        # Step 2: Get all directories in mods folder
        $modDirectories = Get-ChildItem -Path $script:modsPath -Directory -ErrorAction SilentlyContinue

        # Step 3: Scan each directory for config files
        $modConfigs = @()
        foreach ($modDir in $modDirectories) {
            # Look for common config file extensions
            $configFiles = Get-ChildItem -Path $modDir.FullName -File -ErrorAction SilentlyContinue | 
                Where-Object { $_.Extension -match '\.(json|conf|toml|yaml|yml|properties|cfg)$' }

            if ($configFiles -or (Get-ChildItem -Path $modDir.FullName -Directory -ErrorAction SilentlyContinue).Count -gt 0) {
                $modConfigs += [PSCustomObject]@{
                    ModName = $modDir.Name
                    ConfigPath = $modDir.FullName
                    ConfigFiles = $configFiles
                    FileCount = if ($configFiles) { $configFiles.Count } else { 0 }
                    HasSubfolders = (Get-ChildItem -Path $modDir.FullName -Directory -ErrorAction SilentlyContinue).Count -gt 0
                }
            }
        }

        return $modConfigs
    } catch {
        Write-Host "Error getting mod config folders: $_"
        return @()
    }
}

# =====================
# Function: Open-ModConfigFolder
# =====================
# PURPOSE:
# Opens the selected mod's config folder in Windows File Explorer.
# Allows users to browse and manage mod config files directly.
#
# WHY THIS EXISTS:
# - Some users prefer managing configs in File Explorer
# - Allows viewing folder structure and all mod-related files
# - Lets users use their preferred config editors
#
# PARAMETERS:
# - $modName ([string])
#   The name of the mod folder to open
#
# OPERATION FLOW:
# Step 1: Construct the full path to the mod folder
# Step 2: Verify the folder exists
# Step 3: Open in File Explorer
# Step 4: Log action and show error if needed
# =====================
function Open-ModConfigFolder {
    param([string]$modName)

    try {
        # Step 1: Build the path
        $modPath = Join-Path $script:modsPath $modName

        # Step 2: Check if folder exists
        if (-not (Test-Path $modPath)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Mod folder not found: $modPath",
                "Folder Not Found",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }

        # Step 3: Open with explorer
        Start-Process -FilePath "explorer.exe" -ArgumentList $modPath
        $txtConsole.AppendText("[INFO] Opened mod config folder: $modName`r`n")
    } catch {
        # Step 4: Error handling
        [System.Windows.Forms.MessageBox]::Show(
            "Error opening mod folder: $_",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        $txtConsole.AppendText("[ERR] Failed to open mod folder: $_`r`n")
    }
}

# =====================
# Function: Show-ModConfigPicker
# =====================
# PURPOSE:
# Displays a dialog to browse and select mod config files for editing.
# Allows users to pick which mod config to load into the editor.
#
# WHY THIS EXISTS:
# - Provides a UI for discovering available mod configs
# - Allows browsing mod folder structure within the GUI
# - Makes it easy to load mod configs into the editor without file explorer
#
# PARAMETERS:
# None
#
# OPERATION FLOW:
# Step 1: Get all mod config folders
# Step 2: Build a dialog to display them
# Step 3: Allow user to select a mod
# Step 4: Load selected config into editor
# Step 5: Handle cancellation or no selection
# =====================
function Show-ModConfigPicker {
    try {
        # Step 1: Get available mod configs
        $modConfigs = Get-ModConfigFolders

        if ($modConfigs.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "No mod config folders found. Make sure mods have been run at least once to generate their config folders.",
                "No Mods Found",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }

        # Step 2: Create dialog form
        $configPickerForm = New-Object System.Windows.Forms.Form
        $configPickerForm.Text = "Select Mod Config to Edit"
        $configPickerForm.Size = New-Object System.Drawing.Size(500, 400)
        $configPickerForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
        $configPickerForm.BackColor = $colorBack
        $configPickerForm.ForeColor = $colorText
        $configPickerForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $configPickerForm.MaximizeBox = $false
        $configPickerForm.MinimizeBox = $false

        # Label
        $lblSelectMod = New-Object System.Windows.Forms.Label
        $lblSelectMod.Text = "Select a mod to view its config folder:"
        $lblSelectMod.Location = New-Object System.Drawing.Point(10, 10)
        $lblSelectMod.Size = New-Object System.Drawing.Size(470, 25)
        $lblSelectMod.ForeColor = $colorText
        $configPickerForm.Controls.Add($lblSelectMod)

        # ListBox for mod configs
        $lstMods = New-Object System.Windows.Forms.ListBox
        $lstMods.Location = New-Object System.Drawing.Point(10, 40)
        $lstMods.Size = New-Object System.Drawing.Size(470, 250)
        $lstMods.BackColor = $colorTextboxBack
        $lstMods.ForeColor = $colorTextboxText
        $lstMods.Font = New-Object System.Drawing.Font("Consolas", 9)

        # Populate with mod names
        foreach ($mod in $modConfigs) {
            $lstMods.Items.Add("$($mod.ModName) ($($mod.FileCount) config files)")
        }

        $configPickerForm.Controls.Add($lstMods)

        # Info label
        $lblInfo = New-Object System.Windows.Forms.Label
        $lblInfo.Text = "Double-click to open folder, or select and click 'Open Folder'"
        $lblInfo.Location = New-Object System.Drawing.Point(10, 300)
        $lblInfo.Size = New-Object System.Drawing.Size(470, 30)
        $lblInfo.ForeColor = [System.Drawing.Color]::LightGray
        $lblInfo.Font = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Italic)
        $configPickerForm.Controls.Add($lblInfo)

        # Buttons
        $btnOpenFolder = New-Object System.Windows.Forms.Button
        $btnOpenFolder.Text = "Open Folder"
        $btnOpenFolder.Location = New-Object System.Drawing.Point(150, 340)
        $btnOpenFolder.Size = New-Object System.Drawing.Size(150, 30)
        Style-Button $btnOpenFolder
        $btnOpenFolder.Add_Click({
            if ($lstMods.SelectedIndex -ge 0) {
                $selectedMod = $modConfigs[$lstMods.SelectedIndex].ModName
                Open-ModConfigFolder $selectedMod
                $configPickerForm.Close()
            }
        })
        $configPickerForm.Controls.Add($btnOpenFolder)

        $btnCancel = New-Object System.Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Location = New-Object System.Drawing.Point(310, 340)
        $btnCancel.Size = New-Object System.Drawing.Size(150, 30)
        Style-Button $btnCancel
        $btnCancel.Add_Click({ $configPickerForm.Close() })
        $configPickerForm.Controls.Add($btnCancel)

        # Double-click to open
        $lstMods.Add_DoubleClick({
            if ($lstMods.SelectedIndex -ge 0) {
                $selectedMod = $modConfigs[$lstMods.SelectedIndex].ModName
                Open-ModConfigFolder $selectedMod
                $configPickerForm.Close()
            }
        })

        # Show the form
        $configPickerForm.ShowDialog() | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Error opening mod config picker: $_",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# ==========================================================================================
# SECTION: PRIMARY GUI COMPONENTS
# ==========================================================================================
# This section creates the main application window and tab control, which serve as the
# foundation for all other UI elements.
#
# Key elements:
# 1. FORM: The main application window with consistent dimensions and styling
# 2. TAB CONTROL: Container that organizes functionality into separate tabbed pages
#    - Control Tab: Server start/stop, console, commands
#    - Configuration Tab: JSON editors for config/permissions
#    - Maintenance Tab: Update tools, file checking, backup management
# ==========================================================================================

# ------------------------------------------------------------------------------------------
# MAIN APPLICATION WINDOW SETUP
# ------------------------------------------------------------------------------------------
# Creates the primary window (Form) that houses all other UI components
$form = New-Object System.Windows.Forms.Form
$form.Text = "Hytale Server Manager"            # Window title in the titlebar
$form.StartPosition = "CenterScreen"            # Center window on screen when launched
$form.ClientSize = New-Object System.Drawing.Size(1200, 650)  # Inner dimensions excluding borders
$form.MinimumSize = New-Object System.Drawing.Size(1200, 650) # Prevent resizing smaller than this
$form.BackColor = $colorBack                    # Apply dark theme background
$form.AutoScaleMode = "None"                    # Prevent Windows DPI scaling from breaking layout
$form.MaximizeBox = $false                      # Disable maximize button to maintain fixed layout

# ------------------------------------------------------------------------------------------
# TAB CONTROL INITIALIZATION
# ------------------------------------------------------------------------------------------
# Creates the main tab container that separates the UI into logical sections
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill  # Fill the entire form client area
$form.Controls.Add($tabs)                            # Add to main window


# =====================
# TOOLTIP UX CONFIGURATION (GLOBAL)
# =====================
# Creates a tooltip object that will be used throughout the UI to provide helpful hover text

# Create a new tooltip controller object
$toolTip = New-Object System.Windows.Forms.ToolTip

# Configure how long the tooltip remains visible after mouse hover (20 seconds)
$toolTip.AutoPopDelay = 20000     

# Set delay before tooltip appears when hovering (700 milliseconds)
$toolTip.InitialDelay = 700       

# Set delay before showing a different tooltip when moving between controls (300 milliseconds)
$toolTip.ReshowDelay  = 300       

# Use balloon-style tooltips with a pointer instead of plain rectangles
$toolTip.IsBalloon    = $true     

# Always show tooltips even when the form doesn't have focus
$toolTip.ShowAlways   = $true     

# =====================
# COMBINED SERVER CONTROL TAB
# =====================
# Creates the main server control tab containing console output and control buttons

# Create a new tab page for server controls
$tabServer = New-Object System.Windows.Forms.TabPage

# Set the tab header text
$tabServer.Text = "Control"

# Apply the dark theme background color defined earlier
$tabServer.BackColor = $colorBack

# Add this tab to the main tab control
$tabs.TabPages.Add($tabServer)

# =====================
# LAYOUT PANELS - TOP SECTION
# =====================
# Creates container panels to organize UI elements in the server control tab

# Top panel: Contains server control buttons and status information
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Location = New-Object System.Drawing.Point(10, 10)
$panelTop.Size = New-Object System.Drawing.Size(350, 220) # Reduced height slightly
$panelTop.BackColor = $colorBack
$tabServer.Controls.Add($panelTop)

# Commands panel: Contains all server commands in one unified panel
$panelCommands = New-Object System.Windows.Forms.Panel
$panelCommands.Location = New-Object System.Drawing.Point(370, 10)
$panelCommands.Size = New-Object System.Drawing.Size(800, 220) # Matched height
$panelCommands.BackColor = $colorBack
$tabServer.Controls.Add($panelCommands)

# =====================
# SERVER CONTROL BUTTONS
# =====================

# Row 1: Server control buttons
# Create a new Start Server button
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Server"
$btnStart.Size = New-Object System.Drawing.Size(100, 30)
$btnStart.Location = New-Object System.Drawing.Point(10, 10)
Style-Button $btnStart
$btnStart.Add_Click({ Start-Server })
$panelTop.Controls.Add($btnStart)

# Create a new Stop Server button
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop Server"
$btnStop.Size = New-Object System.Drawing.Size(100, 30)
$btnStop.Location = New-Object System.Drawing.Point(120, 10)
Style-Button $btnStop
$btnStop.Add_Click({ Stop-Server })
$panelTop.Controls.Add($btnStop)

# Create a new Restart Server button
$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = "Restart Server"
$btnRestart.Size = New-Object System.Drawing.Size(100, 30)
$btnRestart.Location = New-Object System.Drawing.Point(230, 10)
Style-Button $btnRestart
$btnRestart.Add_Click({ Restart-Server })
$panelTop.Controls.Add($btnRestart)

# Row 2: Console management buttons
# Clear Console Button
$btnClearConsole = New-Object System.Windows.Forms.Button
$btnClearConsole.Text = "Clear Console"
$btnClearConsole.Size = New-Object System.Drawing.Size(100, 30)
$btnClearConsole.Location = New-Object System.Drawing.Point(10, 50)
Style-Button $btnClearConsole
$btnClearConsole.Add_Click({ Clear-Console })
$panelTop.Controls.Add($btnClearConsole)

# Save Console Button
$btnSaveConsole = New-Object System.Windows.Forms.Button
$btnSaveConsole.Text = "Save Console"
$btnSaveConsole.Size = New-Object System.Drawing.Size(100, 30)
$btnSaveConsole.Location = New-Object System.Drawing.Point(120, 50)
Style-Button $btnSaveConsole
$btnSaveConsole.Add_Click({ Save-ConsoleToFile })
$panelTop.Controls.Add($btnSaveConsole)

# Copy Console Button
$btnCopyConsole = New-Object System.Windows.Forms.Button
$btnCopyConsole.Text = "Copy Console"
$btnCopyConsole.Size = New-Object System.Drawing.Size(100, 30)
$btnCopyConsole.Location = New-Object System.Drawing.Point(230, 50)
Style-Button $btnCopyConsole
$btnCopyConsole.Add_Click({ Copy-ConsoleToClipboard })
$panelTop.Controls.Add($btnCopyConsole)

# =====================
# LEFT STATUS LABELS COLUMN
# =====================
$statusLeftCol = New-Object System.Windows.Forms.Panel
$statusLeftCol.Location = New-Object System.Drawing.Point(10, 90)
$statusLeftCol.Size = New-Object System.Drawing.Size(165, 120)
$statusLeftCol.BackColor = $colorBack
$panelTop.Controls.Add($statusLeftCol)

# Uptime
$lblUptime = New-Object System.Windows.Forms.Label
$lblUptime.Text = "Uptime: N/A"
$lblUptime.ForeColor = $colorText
$lblUptime.AutoSize = $true
$lblUptime.Location = New-Object System.Drawing.Point(0, 0)
$statusLeftCol.Controls.Add($lblUptime)

# Players Online
$lblServerPing = New-Object System.Windows.Forms.Label
$lblServerPing.Text = "Players Online: 0"
$lblServerPing.ForeColor = [System.Drawing.Color]::Gray
$lblServerPing.AutoSize = $true
$lblServerPing.Location = New-Object System.Drawing.Point(0, 20)
$statusLeftCol.Controls.Add($lblServerPing)

# Status
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Stopped"
$lblStatus.ForeColor = [System.Drawing.Color]::Red
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(0, 40)
$statusLeftCol.Controls.Add($lblStatus)

Update-StartButtonState

# CPU Usage
$lblCPU = New-Object System.Windows.Forms.Label
$lblCPU.Text = "CPU Usage: 0%"
$lblCPU.ForeColor = $colorText
$lblCPU.AutoSize = $true
$lblCPU.Location = New-Object System.Drawing.Point(0, 60)
$statusLeftCol.Controls.Add($lblCPU)

# RAM Usage
$lblRAM = New-Object System.Windows.Forms.Label
$lblRAM.Text = "RAM Usage: 0 MB"
$lblRAM.ForeColor = $colorText
$lblRAM.AutoSize = $true
$lblRAM.Location = New-Object System.Drawing.Point(0, 80)
$statusLeftCol.Controls.Add($lblRAM)

# =====================
# RIGHT RAM CONTROLS COLUMN
# =====================
$ramControlCol = New-Object System.Windows.Forms.Panel
$ramControlCol.Location = New-Object System.Drawing.Point(175, 90)
$ramControlCol.Size = New-Object System.Drawing.Size(165, 120)
$ramControlCol.BackColor = $colorBack
$panelTop.Controls.Add($ramControlCol)

# MINIMUM RAM ALLOCATION CONTROLS
$lblMinRam = New-Object System.Windows.Forms.Label
$lblMinRam.Text = "Min RAM (GB): 4"
$lblMinRam.ForeColor = $colorText
$lblMinRam.AutoSize = $true
$lblMinRam.Location = New-Object System.Drawing.Point(20, 0)
$ramControlCol.Controls.Add($lblMinRam)

$trkMinRam = New-Object System.Windows.Forms.TrackBar
$trkMinRam.Minimum = 4
$trkMinRam.Maximum = 16
$trkMinRam.Value = 4
$trkMinRam.Size = New-Object System.Drawing.Size(165, 30) # Made slider narrower
$trkMinRam.Location = New-Object System.Drawing.Point(20, 20)
$trkMinRam.TickStyle = [System.Windows.Forms.TickStyle]::BottomRight
$trkMinRam.TickFrequency = 2 # Add ticks every 2GB for better visual feedback
$trkMinRam.Add_Scroll({
    $script:minRamGB = $trkMinRam.Value
    $lblMinRam.Text = "Min RAM (GB): $($trkMinRam.Value)"
})
$ramControlCol.Controls.Add($trkMinRam)

# MAXIMUM RAM ALLOCATION CONTROLS
$lblMaxRam = New-Object System.Windows.Forms.Label
$lblMaxRam.Text = "Max RAM (GB): 16"
$lblMaxRam.ForeColor = $colorText
$lblMaxRam.AutoSize = $true
$lblMaxRam.Location = New-Object System.Drawing.Point(20, 80)
$ramControlCol.Controls.Add($lblMaxRam)

$trkMaxRam = New-Object System.Windows.Forms.TrackBar
$trkMaxRam.Minimum = 8
$trkMaxRam.Maximum = 32
$trkMaxRam.Value = 16
$trkMaxRam.Size = New-Object System.Drawing.Size(165, 30) # Made slider narrower
$trkMaxRam.Location = New-Object System.Drawing.Point(20, 100)
$trkMaxRam.TickStyle = [System.Windows.Forms.TickStyle]::BottomRight
$trkMaxRam.TickFrequency = 4 # Add ticks every 4GB for better visual feedback
$trkMaxRam.Add_Scroll({
    $script:maxRamGB = $trkMaxRam.Value
    $lblMaxRam.Text = "Max RAM (GB): $($trkMaxRam.Value)"
})
$ramControlCol.Controls.Add($trkMaxRam)

# =====================
# MAIN CONSOLE OUTPUT
# =====================

$txtConsole = New-Object System.Windows.Forms.TextBox
$txtConsole.Multiline = $true
$txtConsole.ScrollBars = "Vertical"
$txtConsole.ReadOnly = $true
$txtConsole.BackColor = $colorConsoleBack
$txtConsole.ForeColor = $colorConsoleText
$txtConsole.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtConsole.Location = New-Object System.Drawing.Point(10, 240) # Moved up to match shorter panel
$txtConsole.Size = New-Object System.Drawing.Size(1150, 270)  # Slightly taller to compensate
$tabServer.Controls.Add($txtConsole)

# =====================
# COMMAND INPUT AREA
# =====================

# Command input textbox
$txtCommandInput = New-Object System.Windows.Forms.TextBox
$txtCommandInput.Location = New-Object System.Drawing.Point(10, 520)
$txtCommandInput.Size = New-Object System.Drawing.Size(1060, 25)
$tabServer.Controls.Add($txtCommandInput)

# Send command button
$btnSendCommand = New-Object System.Windows.Forms.Button
$btnSendCommand.Text = "Send"
$btnSendCommand.Location = New-Object System.Drawing.Point(1080, 520)
$btnSendCommand.Size = New-Object System.Drawing.Size(80, 25)
Style-Button $btnSendCommand
$btnSendCommand.Add_Click({
    $cmdText = $txtCommandInput.Text.Trim()
    if ($cmdText) {
        Send-ServerCommand $cmdText
        Add-ToCommandHistory $cmdText
    }
    $txtCommandInput.Text = ""
})
$tabServer.Controls.Add($btnSendCommand)

# =====================
# AUTH LOGIN DEVICE BUTTON
# =====================
$btnAuthLogin = New-Object System.Windows.Forms.Button
$btnAuthLogin.Text = "Get Auth Link"
$btnAuthLogin.Location = New-Object System.Drawing.Point(10, 555)
$btnAuthLogin.Size = New-Object System.Drawing.Size(150, 25)
Style-Button $btnAuthLogin
$btnAuthLogin.Add_Click({
    Send-ServerCommand "/auth login device"
    $txtConsole.AppendText("[INFO] Authentication login device request sent. Check console for auth link.`r`n")
})
$tabServer.Controls.Add($btnAuthLogin)
$toolTip.SetToolTip($btnAuthLogin, "Click to generate authentication link via /auth login device")

# Enter key support and command history navigation
$txtCommandInput.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        $cmdText = $txtCommandInput.Text.Trim()
        if ($cmdText) {
            Send-ServerCommand $cmdText
            Add-ToCommandHistory $cmdText
        }
        $txtCommandInput.Text = ""
    } elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Up) {
        $_.SuppressKeyPress = $true
        if ($script:commandHistory.Count -gt 0) {
            if ($script:commandHistoryIndex -gt 0) { $script:commandHistoryIndex-- }
            if ($script:commandHistoryIndex -lt 0) { $script:commandHistoryIndex = 0 }
            $txtCommandInput.Text = $script:commandHistory[$script:commandHistoryIndex]
            $txtCommandInput.SelectionStart = $txtCommandInput.Text.Length
        }
    } elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::Down) {
        $_.SuppressKeyPress = $true
        if ($script:commandHistory.Count -gt 0) {
            if ($script:commandHistoryIndex -lt ($script:commandHistory.Count - 1)) { $script:commandHistoryIndex++ } else { $script:commandHistoryIndex = $script:commandHistory.Count }
            if ($script:commandHistoryIndex -ge 0 -and $script:commandHistoryIndex -lt $script:commandHistory.Count) {
                $txtCommandInput.Text = $script:commandHistory[$script:commandHistoryIndex]
            } else {
                $txtCommandInput.Text = ""
            }
            $txtCommandInput.SelectionStart = $txtCommandInput.Text.Length
        }
    }
})



# =====================
# COMMAND BUTTONS SECTION (COMBINED INTO ONE)
# =====================

# Create a single combined commands group box
$grpAllCommands = New-Object System.Windows.Forms.GroupBox
$grpAllCommands.Text = "Server Commands"
$grpAllCommands.Location = New-Object System.Drawing.Point(10, 10)
$grpAllCommands.Size = New-Object System.Drawing.Size(780, 200)  # Slightly reduced height
$grpAllCommands.ForeColor = $colorText
$panelCommands.Controls.Add($grpAllCommands)

# Ensure Hytale command dictionary exists (aliases and sub-commands with detailed tooltips)
if (-not (Get-Variable -Name hytaleCommands -Scope Script -ErrorAction SilentlyContinue)) {
    $script:hytaleCommands = [ordered]@{

        # =====================
        # WORLD / SERVER
        # =====================
        "/addworld"            = "Add a new world instance."
        "/loadworld"           = "Load a world."
        "/unloadworld"         = "Unload a world."
        "/world"               = "World management commands."
        "/worlds"              = "List available worlds."
        "/worldmap"            = "Toggle or manage world map view."
        "/worldgen"            = "World generation controls."
        "/weather"             = "Set or query weather state."
        "/pause"               = "Pause the game world."
        "/pausetime"           = "Pause or resume time progression."
        "/noon"                = "Set time to midday."
        "/sleepoffset"         = "Adjust sleep time offset."
        "/tps"                 = "Display server ticks per second."
        "/pidcheck"            = "Check server process health."
        "/logs"                = "View or manage server logs."
        "/maxviewradius"       = "Set max player view distance."
        "/backup list"         = "List available backups."
        "/backup restore"      = "Restore a backup."
        "/say"                 = "Broadcast to all players."

        # =====================
        # PLAYER / ADMIN
        # =====================
        "/ban"                 = "Ban a player."
        "/unban"               = "Unban a player."
        "/kick"                = "Kick a player from the server."
        "/mute"                = "Mute a player."
        "/unmute"              = "Unmute a player."
        "/sudo"                = "Execute a command as another player."
        "/perm"                = "Permission management."
        "/testperm"            = "Test player permissions."
        "/displayname"         = "Change player display name."
        "/heal"                = "Heal a player."
        "/kill"                = "Kill a player or entity."
        "/unstuck"             = "Teleport player to a safe location."
        "/top"                 = "Teleport to highest solid block."
        "/tpall"               = "Teleport all players."
        "/setpvp"              = "Enable or disable PvP."

        # =====================
        # INVENTORY / ITEMS
        # =====================
        "/give"                = "Give items to a player."
        "/spawnitem"           = "Spawn an item in the world."
        "/inventoryitem"       = "Modify inventory items."
        "/inventorybackpack"   = "Access backpack inventory."
        "/recipe"              = "Manage crafting recipes."
        "/droplist"            = "Show or edit drop tables."

        # =====================
        # ENTITY / NPC
        # =====================
        "/summon"              = "Summon an entity."
        "/despawn"             = "Remove entities."
        "/dismount"            = "Force dismount from mounts."
        "/npcpath"             = "Control NPC pathing."
        "/reputation"          = "Adjust NPC reputation."
        "/neardeath"           = "Trigger near-death state."
        "/checkpoint"          = "Set or load player checkpoints."

        # =====================
        # BUILDING / BLOCKS
        # =====================
        "/blockselect"         = "Select blocks using filters."
        "/blockset"            = "Set blocks using parameters."
        "/blockspawner"        = "Spawn blocks programmatically."
        "/spawnblock"          = "Spawn a specific block."
        "/chunk"               = "Chunk operations."
        "/chunklighting"       = "Recalculate chunk lighting."
        "/copychunk"           = "Copy chunk data."
        "/forcechunktick"      = "Force chunk updates."
        "/invalidatelighting"  = "Invalidate lighting cache."
        "/lightingcalculation" = "Trigger lighting calculation."
        "/toggleBlockPlacementOverride" = "Override block placement rules."

        # =====================
        # PREFABS / EDITING
        # =====================
        "/convertprefabs"      = "Convert prefab formats."
        "/prefabspawner"       = "Spawn prefabs."
        "/edit"                = "Advanced edit tools."
        "/editselection"       = "Edit current selection."
        "/clearhistory"        = "Clear edit history."

        # =====================
        # CAMERA / UI / FX
        # =====================
        "/camera"              = "Camera controls."
        "/camshake"            = "Trigger camera shake."
        "/hudtest"             = "Test HUD elements."
        "/eventtitle"          = "Display event title on screen."
        "/notify"              = "Send notifications."
        "/particle"            = "Spawn particle effects."
        "/ambience"            = "Control ambient audio."
        "/play"                = "Play a sound or animation."

        # =====================
        # SYSTEM / DEBUG
        # =====================
        "/auth"                = "Authentication debugging."
        "/assets"              = "Asset management tools."
        "/i18n"                = "Localization testing."
        "/instances"           = "Instance management."
        "/packetStats"         = "Network packet statistics."
        "/packs"               = "Resource pack controls."
        "/setticking"          = "Adjust tick behavior."
        "/tagpattern"          = "Apply tag patterns."
        "/toggleTmpTags"       = "Toggle temporary tags."
        "/validatecpb"         = "Validate clipboard buffer."
        "/voidevent"           = "Trigger void events."

    }
}

# Create a single flow layout panel for all commands
$flowAllButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$flowAllButtons.Location = New-Object System.Drawing.Point(10, 20)
$flowAllButtons.Size = New-Object System.Drawing.Size(760, 170)  # Slightly reduced height
$flowAllButtons.AutoScroll = $true
$flowAllButtons.WrapContents = $true
# Optional: uncomment to make it resize automatically with the group box
# $flowAllButtons.Dock = 'Fill'
$grpAllCommands.Controls.Add($flowAllButtons)

# Combine all commands into one dictionary
$allCommands = [ordered]@{}

# Add Hytale Commands first (so aliases/subcommands appear before generic ones)
foreach ($cmd in $hytaleCommands.Keys) {
    $allCommands[$cmd] = $hytaleCommands[$cmd]
}

# Add Admin Commands (keep priority for duplicates)
foreach ($cmd in $adminCommands.Keys) {
    $allCommands[$cmd] = $adminCommands[$cmd]
}

# Add Multiplayer Commands (skip if already added)
foreach ($cmd in $multiCommands.Keys) {
    if (-not $allCommands.Contains($cmd)) {
        $allCommands[$cmd] = $multiCommands[$cmd]
    }
}

# Add World Commands (skip if already added)
foreach ($cmd in $worldCommands.Keys) {
    if (-not $allCommands.Contains($cmd)) {
        $allCommands[$cmd] = $worldCommands[$cmd]
    }
}

# Add Other Commands (skip if already added)
foreach ($cmd in $otherCommands.Keys) {
    if (-not $allCommands.Contains($cmd)) {
        $allCommands[$cmd] = $otherCommands[$cmd]
    }
}

# Create buttons for all commands (alphabetical order)
foreach ($cmd in ($allCommands.Keys | Sort-Object)) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $cmd
    $btn.Size = New-Object System.Drawing.Size(90, 26)  # Slightly smaller buttons to fit more
    $btn.Tag = $cmd
    Style-Button $btn
    $btn.Add_Click({
        $txtCommandInput.Text = $this.Tag + " "
        $txtCommandInput.Focus()
        $txtCommandInput.SelectionStart = $txtCommandInput.Text.Length
    })
    $toolTip.SetToolTip($btn, $allCommands[$cmd])
    $flowAllButtons.Controls.Add($btn)
}

# =====================
# CONFIG EDITOR TAB (ENHANCED)
# =====================

$tabConfig = New-Object System.Windows.Forms.TabPage
$tabConfig.Text = "Configuration"
$tabConfig.BackColor = $colorBack
$tabs.TabPages.Add($tabConfig)

# =====================
# MAIN EDITOR SECTION
# =====================

$grpConfigEditor = New-Object System.Windows.Forms.GroupBox
$grpConfigEditor.Text = "Configuration Editor"
$grpConfigEditor.Location = New-Object System.Drawing.Point(10, 10)
$grpConfigEditor.Size = New-Object System.Drawing.Size(760, 480)
$grpConfigEditor.ForeColor = $colorText
$tabConfig.Controls.Add($grpConfigEditor)

$txtConfigEditor = New-Object System.Windows.Forms.RichTextBox
$txtConfigEditor.Multiline = $true
$txtConfigEditor.ScrollBars = "Both"          # Vertical + horizontal scrollbars
$txtConfigEditor.BackColor = $colorTextboxBack
$txtConfigEditor.ForeColor = $colorTextboxText
$txtConfigEditor.Font = New-Object System.Drawing.Font("Consolas", 10)  # Monospaced font
$txtConfigEditor.WordWrap = $false            # Prevent line breaking
$txtConfigEditor.AcceptsTab = $true           # Tabs work for indentation
$txtConfigEditor.EnableAutoDragDrop = $false
$txtConfigEditor.DetectUrls = $false
$txtConfigEditor.Location = New-Object System.Drawing.Point(12, 25)
$txtConfigEditor.Size = New-Object System.Drawing.Size(735, 440)
$grpConfigEditor.Controls.Add($txtConfigEditor)

# Info label for JSON syntax highlighting
$lblSyntaxInfo = New-Object System.Windows.Forms.Label
$lblSyntaxInfo.Text = "Tip: Edit JSON files directly. Use Ctrl+A to select all, Ctrl+Z to undo"
$lblSyntaxInfo.Location = New-Object System.Drawing.Point(10, 495)
$lblSyntaxInfo.Size = New-Object System.Drawing.Size(760, 20)
$lblSyntaxInfo.ForeColor = [System.Drawing.Color]::LightGray
$lblSyntaxInfo.Font = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Italic)
$tabConfig.Controls.Add($lblSyntaxInfo)

# =====================
# FILE OPERATIONS SECTION
# =====================

$grpFileOps = New-Object System.Windows.Forms.GroupBox
$grpFileOps.Text = "File Operations"
$grpFileOps.Location = New-Object System.Drawing.Point(790, 10)
$grpFileOps.Size = New-Object System.Drawing.Size(185, 150)
$grpFileOps.ForeColor = $colorText
$tabConfig.Controls.Add($grpFileOps)

$btnLoadConfig = New-Object System.Windows.Forms.Button
$btnLoadConfig.Text = "Load Configuration"
$btnLoadConfig.Location = New-Object System.Drawing.Point(8, 25)
$btnLoadConfig.Size = New-Object System.Drawing.Size(169, 30)
Style-Button $btnLoadConfig
$btnLoadConfig.Add_Click({ Load-Config })
$grpFileOps.Controls.Add($btnLoadConfig)
$toolTip.SetToolTip($btnLoadConfig, "Load the current config.json file into the editor")

$btnSaveConfig = New-Object System.Windows.Forms.Button
$btnSaveConfig.Text = "Save Configuration"
$btnSaveConfig.Location = New-Object System.Drawing.Point(8, 62)
$btnSaveConfig.Size = New-Object System.Drawing.Size(169, 30)
Style-Button $btnSaveConfig
$btnSaveConfig.Add_Click({ Save-Config })
$grpFileOps.Controls.Add($btnSaveConfig)
$toolTip.SetToolTip($btnSaveConfig, "Save changes from the editor back to config.json")

$btnOpenConfig = New-Object System.Windows.Forms.Button
$btnOpenConfig.Text = "Open Config File"
$btnOpenConfig.Location = New-Object System.Drawing.Point(8, 99)
$btnOpenConfig.Size = New-Object System.Drawing.Size(169, 30)
Style-Button $btnOpenConfig
$btnOpenConfig.Add_Click({ Open-ConfigFile })
$grpFileOps.Controls.Add($btnOpenConfig)
$toolTip.SetToolTip($btnOpenConfig, "Open config.json in your default text editor")

# =====================
# PERMISSIONS SECTION
# =====================

$grpPermissions = New-Object System.Windows.Forms.GroupBox
$grpPermissions.Text = "Permissions Management"
$grpPermissions.Location = New-Object System.Drawing.Point(790, 170)
$grpPermissions.Size = New-Object System.Drawing.Size(185, 150)
$grpPermissions.ForeColor = $colorText
$tabConfig.Controls.Add($grpPermissions)

$btnLoadPermissions = New-Object System.Windows.Forms.Button
$btnLoadPermissions.Text = "Load Permissions"
$btnLoadPermissions.Location = New-Object System.Drawing.Point(8, 25)
$btnLoadPermissions.Size = New-Object System.Drawing.Size(169, 30)
Style-Button $btnLoadPermissions
$btnLoadPermissions.Add_Click({ Load-Permissions })
$grpPermissions.Controls.Add($btnLoadPermissions)
$toolTip.SetToolTip($btnLoadPermissions, "Load the current permissions.json file into the editor")

$btnSavePermissions = New-Object System.Windows.Forms.Button
$btnSavePermissions.Text = "Save Permissions"
$btnSavePermissions.Location = New-Object System.Drawing.Point(8, 62)
$btnSavePermissions.Size = New-Object System.Drawing.Size(169, 30)
Style-Button $btnSavePermissions
$btnSavePermissions.Add_Click({ Save-Permissions })
$grpPermissions.Controls.Add($btnSavePermissions)
$toolTip.SetToolTip($btnSavePermissions, "Save changes from the editor back to permissions.json")

$btnOpenPermissions = New-Object System.Windows.Forms.Button
$btnOpenPermissions.Text = "Open Permissions File"
$btnOpenPermissions.Location = New-Object System.Drawing.Point(8, 99)
$btnOpenPermissions.Size = New-Object System.Drawing.Size(169, 30)
Style-Button $btnOpenPermissions
$btnOpenPermissions.Add_Click({ Open-PermissionsFile })
$grpPermissions.Controls.Add($btnOpenPermissions)
$toolTip.SetToolTip($btnOpenPermissions, "Open permissions.json in your default text editor")

# =====================
# THEME SWITCHER SECTION
# =====================

$grpTheme = New-Object System.Windows.Forms.GroupBox
$grpTheme.Text = "Theme Selector"
$grpTheme.Location = New-Object System.Drawing.Point(790, 330)
$grpTheme.Size = New-Object System.Drawing.Size(185, 165)
$grpTheme.ForeColor = $colorText
$tabConfig.Controls.Add($grpTheme)

$lblThemeLabel = New-Object System.Windows.Forms.Label
$lblThemeLabel.Text = "Choose Theme:"
$lblThemeLabel.Location = New-Object System.Drawing.Point(8, 20)
$lblThemeLabel.Size = New-Object System.Drawing.Size(169, 16)
$lblThemeLabel.ForeColor = $colorText
$lblThemeLabel.Font = New-Object System.Drawing.Font("Arial", 9)
$grpTheme.Controls.Add($lblThemeLabel)

$cmbTheme = New-Object System.Windows.Forms.ComboBox
$cmbTheme.Location = New-Object System.Drawing.Point(8, 40)
$cmbTheme.Size = New-Object System.Drawing.Size(169, 25)
$cmbTheme.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbTheme.BackColor = $colorTextboxBack
$cmbTheme.ForeColor = $colorTextboxText
$cmbTheme.Items.AddRange(@("Dark", "Light", "Blue", "Purple"))
$cmbTheme.SelectedItem = "Dark"
$grpTheme.Controls.Add($cmbTheme)
$toolTip.SetToolTip($cmbTheme, "Select from available color themes")

$btnApplyTheme = New-Object System.Windows.Forms.Button
$btnApplyTheme.Text = "Apply Theme"
$btnApplyTheme.Location = New-Object System.Drawing.Point(8, 72)
$btnApplyTheme.Size = New-Object System.Drawing.Size(169, 35)
$btnApplyTheme.BackColor = [System.Drawing.Color]::FromArgb(100, 50, 150)
$btnApplyTheme.ForeColor = [System.Drawing.Color]::White
$btnApplyTheme.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnApplyTheme.Add_Click({ 
    $selectedTheme = $cmbTheme.SelectedItem
    if ($selectedTheme) {
        Apply-Theme $selectedTheme
    }
})
$grpTheme.Controls.Add($btnApplyTheme)
$toolTip.SetToolTip($btnApplyTheme, "Apply the selected theme to the entire application")

$lblThemeInfo = New-Object System.Windows.Forms.Label
$lblThemeInfo.Text = "Available: Dark, Light, Blue, Purple"
$lblThemeInfo.Location = New-Object System.Drawing.Point(8, 115)
$lblThemeInfo.Size = New-Object System.Drawing.Size(169, 40)
$lblThemeInfo.ForeColor = [System.Drawing.Color]::LightGray
$lblThemeInfo.Font = New-Object System.Drawing.Font("Arial", 8)
$lblThemeInfo.AutoSize = $false
$grpTheme.Controls.Add($lblThemeInfo)

# =====================
# SERVER MAINTENANCE TAB (REORGANIZED LAYOUT)
# =====================

$tabMaintenance = New-Object System.Windows.Forms.TabPage
$tabMaintenance.Text = "Server Maintenance"
$tabMaintenance.BackColor = $colorBack
$tabs.TabPages.Add($tabMaintenance)

# =====================
# GROUP 1: SERVER UPDATE SECTION (TOP LEFT)
# =====================

$groupUpdate = New-Object System.Windows.Forms.GroupBox
$groupUpdate.Text = "Server Update"
$groupUpdate.Location = New-Object System.Drawing.Point(10, 10)
$groupUpdate.Size = New-Object System.Drawing.Size(470, 150)
$groupUpdate.ForeColor = $colorText
$tabMaintenance.Controls.Add($groupUpdate)

$lblUpdateInfo = New-Object System.Windows.Forms.Label
$lblUpdateInfo.Text = "Download and install the latest Hytale server files"
$lblUpdateInfo.Location = New-Object System.Drawing.Point(10, 20)
$lblUpdateInfo.Size = New-Object System.Drawing.Size(450, 20)
$lblUpdateInfo.ForeColor = $colorText
$groupUpdate.Controls.Add($lblUpdateInfo)

$lblDownloaderPath = New-Object System.Windows.Forms.Label
$lblDownloaderPath.Text = "Downloader:"
$lblDownloaderPath.Location = New-Object System.Drawing.Point(10, 50)
$lblDownloaderPath.Size = New-Object System.Drawing.Size(80, 20)
$lblDownloaderPath.ForeColor = $colorText
$groupUpdate.Controls.Add($lblDownloaderPath)

$txtDownloaderPath = New-Object System.Windows.Forms.TextBox
$txtDownloaderPath.Location = New-Object System.Drawing.Point(100, 48)
$txtDownloaderPath.Size = New-Object System.Drawing.Size(340, 20)
$txtDownloaderPath.ReadOnly = $true
$txtDownloaderPath.BackColor = $colorTextboxBack
$txtDownloaderPath.ForeColor = $colorTextboxText
$txtDownloaderPath.Text = $script:downloaderPath
$groupUpdate.Controls.Add($txtDownloaderPath)

$btnUpdateServer = New-Object System.Windows.Forms.Button
$btnUpdateServer.Text = "Update Server"
$btnUpdateServer.Location = New-Object System.Drawing.Point(10, 80)
$btnUpdateServer.Size = New-Object System.Drawing.Size(140, 30)
$btnUpdateServer.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
$btnUpdateServer.ForeColor = $colorText
$btnUpdateServer.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$btnUpdateServer.Add_Click({ Update-Server })
$groupUpdate.Controls.Add($btnUpdateServer)

$chkAutoRestart = New-Object System.Windows.Forms.CheckBox
$chkAutoRestart.Text = "Auto-restart after update"
$chkAutoRestart.Location = New-Object System.Drawing.Point(160, 85)
$chkAutoRestart.Size = New-Object System.Drawing.Size(190, 20)
$chkAutoRestart.ForeColor = $colorText
$chkAutoRestart.Checked = $true
$groupUpdate.Controls.Add($chkAutoRestart)

$lblUpdateWarning = New-Object System.Windows.Forms.Label
$lblUpdateWarning.Text = "[!] Server will stop during update"
$lblUpdateWarning.Location = New-Object System.Drawing.Point(10, 115)
$lblUpdateWarning.Size = New-Object System.Drawing.Size(450, 20)
$lblUpdateWarning.ForeColor = [System.Drawing.Color]::Orange
$lblUpdateWarning.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$groupUpdate.Controls.Add($lblUpdateWarning)

# =====================
# GROUP 2: SERVER INFO SECTION (TOP RIGHT)
# =====================

$groupServerInfo = New-Object System.Windows.Forms.GroupBox
$groupServerInfo.Text = "Server Information"
$groupServerInfo.Location = New-Object System.Drawing.Point(490, 10)
$groupServerInfo.Size = New-Object System.Drawing.Size(470, 150)
$groupServerInfo.ForeColor = $colorText
$tabMaintenance.Controls.Add($groupServerInfo)

$lblServerIPTitle = New-Object System.Windows.Forms.Label
$lblServerIPTitle.Text = "Server IP Address:"
$lblServerIPTitle.Location = New-Object System.Drawing.Point(10, 25)
$lblServerIPTitle.Size = New-Object System.Drawing.Size(150, 20)
$lblServerIPTitle.ForeColor = $colorText
$lblServerIPTitle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$groupServerInfo.Controls.Add($lblServerIPTitle)

$btnCopyServerIP = New-Object System.Windows.Forms.Button
$btnCopyServerIP.Text = "Copy Server IP"
$btnCopyServerIP.Location = New-Object System.Drawing.Point(10, 50)
$btnCopyServerIP.Size = New-Object System.Drawing.Size(450, 35)
$btnCopyServerIP.BackColor = [System.Drawing.Color]::FromArgb(50, 150, 50)
$btnCopyServerIP.ForeColor = [System.Drawing.Color]::White
$btnCopyServerIP.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$btnCopyServerIP.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopyServerIP.Add_Click({ Copy-ServerIP })
$groupServerInfo.Controls.Add($btnCopyServerIP)

$btnRestoreBackup = New-Object System.Windows.Forms.Button
$btnRestoreBackup.Text = "Restore from Backup"
$btnRestoreBackup.Location = New-Object System.Drawing.Point(10, 100)
$btnRestoreBackup.Size = New-Object System.Drawing.Size(450, 35)
$btnRestoreBackup.BackColor = [System.Drawing.Color]::FromArgb(180, 70, 70)
$btnRestoreBackup.ForeColor = $colorText
$btnRestoreBackup.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$btnRestoreBackup.Add_Click({ Restore-ServerBackup })
$groupServerInfo.Controls.Add($btnRestoreBackup)

# =====================
# GROUP 3: DOWNLOADER UTILITIES SECTION (FULL WIDTH)
# =====================

$groupDownloaderUtils = New-Object System.Windows.Forms.GroupBox
$groupDownloaderUtils.Text = "Downloader Utilities"
$groupDownloaderUtils.Location = New-Object System.Drawing.Point(10, 170)
$groupDownloaderUtils.Size = New-Object System.Drawing.Size(950, 60)
$groupDownloaderUtils.ForeColor = $colorText
$tabMaintenance.Controls.Add($groupDownloaderUtils)

$btnPrintVersion = New-Object System.Windows.Forms.Button
$btnPrintVersion.Text = "Check for Update"
$btnPrintVersion.Location = New-Object System.Drawing.Point(10, 20)
$btnPrintVersion.Size = New-Object System.Drawing.Size(150, 25)
$btnPrintVersion.BackColor = $colorButtonBack
$btnPrintVersion.ForeColor = $colorText
$btnPrintVersion.Add_Click({
    $output = Run-DownloaderCommand "-print-version" "Checking server version"
    if (-not $output) {
        [System.Windows.Forms.MessageBox]::Show("Could not get server version from downloader.", "Error")
        return
    }
    if ($output -match '(\d{4}\.\d{2}\.\d{2})-(\w+)') {
        $datePart = $matches[1]
        $hashPart = $matches[2]
        $exeVersion = $hashPart
    } else {
        $exeVersion = $output.Trim()
    }
    $zipVersion = Get-ZipServerVersion
    if (-not $zipVersion) {
        [System.Windows.Forms.MessageBox]::Show("No server update ZIP found to compare against.", "No Update Package")
        return
    }
    if ($exeVersion -ne $zipVersion) {
        [System.Windows.Forms.MessageBox]::Show("Update Available!`n`nInstalled (Server): $exeVersion`nZIP Package: $zipVersion", "Update Available",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
    } else {
        [System.Windows.Forms.MessageBox]::Show("No update available.`n`nVersion: $exeVersion", "Up To Date",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
    }
})
$groupDownloaderUtils.Controls.Add($btnPrintVersion)

$btnDownloaderVersion = New-Object System.Windows.Forms.Button
$btnDownloaderVersion.Text = "Downloader Version"
$btnDownloaderVersion.Location = New-Object System.Drawing.Point(170, 20)
$btnDownloaderVersion.Size = New-Object System.Drawing.Size(150, 25)
$btnDownloaderVersion.BackColor = $colorButtonBack
$btnDownloaderVersion.ForeColor = $colorText
$btnDownloaderVersion.Add_Click({ Run-DownloaderCommand "-version" "Checking downloader version" })
$groupDownloaderUtils.Controls.Add($btnDownloaderVersion)

$btnCheckUpdate = New-Object System.Windows.Forms.Button
$btnCheckUpdate.Text = "Check Downloader Update"
$btnCheckUpdate.Location = New-Object System.Drawing.Point(330, 20)
$btnCheckUpdate.Size = New-Object System.Drawing.Size(150, 25)
$btnCheckUpdate.BackColor = $colorButtonBack
$btnCheckUpdate.ForeColor = $colorText
$btnCheckUpdate.Add_Click({ Run-DownloaderCommand "-check-update" "Checking for downloader updates" })
$groupDownloaderUtils.Controls.Add($btnCheckUpdate)

$btnUpdateDownloader = New-Object System.Windows.Forms.Button
$btnUpdateDownloader.Text = "Update Downloader"
$btnUpdateDownloader.Location = New-Object System.Drawing.Point(490, 20)
$btnUpdateDownloader.Size = New-Object System.Drawing.Size(150, 25)
$btnUpdateDownloader.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
$btnUpdateDownloader.ForeColor = [System.Drawing.Color]::White
$btnUpdateDownloader.Add_Click({ Download-LatestDownloader })
$groupDownloaderUtils.Controls.Add($btnUpdateDownloader)

$btnCheckFiles = New-Object System.Windows.Forms.Button
$btnCheckFiles.Text = "Check Files"
$btnCheckFiles.Location = New-Object System.Drawing.Point(650, 20)
$btnCheckFiles.Size = New-Object System.Drawing.Size(150, 25)
Style-Button $btnCheckFiles
$btnCheckFiles.Add_Click({ Check-ServerFiles })
$groupDownloaderUtils.Controls.Add($btnCheckFiles)

$toolTip.SetToolTip($btnUpdateDownloader, "Download the latest version of the Hytale downloader tool")

# =====================
# GROUP 4: FILE STATUS SECTION (FULL WIDTH)
# =====================

$groupFileStatus = New-Object System.Windows.Forms.GroupBox
$groupFileStatus.Text = "Required Files Status"
$groupFileStatus.Location = New-Object System.Drawing.Point(10, 240)
$groupFileStatus.Size = New-Object System.Drawing.Size(950, 120)
$groupFileStatus.ForeColor = $colorText
$tabMaintenance.Controls.Add($groupFileStatus)

# Row 1: HytaleServer.jar and Assets.zip
$lblJarFile = New-Object System.Windows.Forms.Label
$lblJarFile.Text = "HytaleServer.jar"
$lblJarFile.Location = New-Object System.Drawing.Point(10, 25)
$lblJarFile.Size = New-Object System.Drawing.Size(200, 20)
$lblJarFile.ForeColor = [System.Drawing.Color]::Red
$groupFileStatus.Controls.Add($lblJarFile)

$lblJarStatus = New-Object System.Windows.Forms.Label
$lblJarStatus.Text = "[MISSING]"
$lblJarStatus.Location = New-Object System.Drawing.Point(220, 25)
$lblJarStatus.Size = New-Object System.Drawing.Size(80, 20)
$lblJarStatus.ForeColor = [System.Drawing.Color]::Red
$groupFileStatus.Controls.Add($lblJarStatus)

$lblAssetsFile = New-Object System.Windows.Forms.Label
$lblAssetsFile.Text = "Assets.zip"
$lblAssetsFile.Location = New-Object System.Drawing.Point(480, 25)
$lblAssetsFile.Size = New-Object System.Drawing.Size(200, 20)
$lblAssetsFile.ForeColor = [System.Drawing.Color]::Red
$groupFileStatus.Controls.Add($lblAssetsFile)

$lblAssetsStatus = New-Object System.Windows.Forms.Label
$lblAssetsStatus.Text = "[MISSING]"
$lblAssetsStatus.Location = New-Object System.Drawing.Point(690, 25)
$lblAssetsStatus.Size = New-Object System.Drawing.Size(80, 20)
$lblAssetsStatus.ForeColor = [System.Drawing.Color]::Red
$groupFileStatus.Controls.Add($lblAssetsStatus)

# Row 2: Server/ and mods/
$lblServerFolder = New-Object System.Windows.Forms.Label
$lblServerFolder.Text = "Server/"
$lblServerFolder.Location = New-Object System.Drawing.Point(10, 55)
$lblServerFolder.Size = New-Object System.Drawing.Size(200, 20)
$lblServerFolder.ForeColor = [System.Drawing.Color]::Red
$groupFileStatus.Controls.Add($lblServerFolder)

$lblServerFolderStatus = New-Object System.Windows.Forms.Label
$lblServerFolderStatus.Text = "[MISSING]"
$lblServerFolderStatus.Location = New-Object System.Drawing.Point(220, 55)
$lblServerFolderStatus.Size = New-Object System.Drawing.Size(80, 20)
$lblServerFolderStatus.ForeColor = [System.Drawing.Color]::Red
$groupFileStatus.Controls.Add($lblServerFolderStatus)

$lblModsFolder = New-Object System.Windows.Forms.Label
$lblModsFolder.Text = "mods/"
$lblModsFolder.Location = New-Object System.Drawing.Point(480, 55)
$lblModsFolder.Size = New-Object System.Drawing.Size(200, 20)
$lblModsFolder.ForeColor = [System.Drawing.Color]::Red
$groupFileStatus.Controls.Add($lblModsFolder)

$lblModsFolderStatus = New-Object System.Windows.Forms.Label
$lblModsFolderStatus.Text = "[MISSING]"
$lblModsFolderStatus.Location = New-Object System.Drawing.Point(690, 55)
$lblModsFolderStatus.Size = New-Object System.Drawing.Size(80, 20)
$lblModsFolderStatus.ForeColor = [System.Drawing.Color]::Red
$groupFileStatus.Controls.Add($lblModsFolderStatus)

# Row 3: config.json and Overall Status
$lblConfigFile = New-Object System.Windows.Forms.Label
$lblConfigFile.Text = "config.json"
$lblConfigFile.Location = New-Object System.Drawing.Point(10, 85)
$lblConfigFile.Size = New-Object System.Drawing.Size(200, 20)
$lblConfigFile.ForeColor = [System.Drawing.Color]::Red
$groupFileStatus.Controls.Add($lblConfigFile)

$lblConfigStatus = New-Object System.Windows.Forms.Label
$lblConfigStatus.Text = "[MISSING]"
$lblConfigStatus.Location = New-Object System.Drawing.Point(220, 85)
$lblConfigStatus.Size = New-Object System.Drawing.Size(80, 20)
$lblConfigStatus.ForeColor = [System.Drawing.Color]::Red
$groupFileStatus.Controls.Add($lblConfigStatus)

$lblOverallStatus = New-Object System.Windows.Forms.Label
$lblOverallStatus.Text = "[WARN] Missing required files"
$lblOverallStatus.Location = New-Object System.Drawing.Point(480, 85)
$lblOverallStatus.Size = New-Object System.Drawing.Size(250, 20)
$lblOverallStatus.ForeColor = [System.Drawing.Color]::Orange
$groupFileStatus.Controls.Add($lblOverallStatus)

# =====================
# GROUP 5: UPDATE LOG SECTION (FULL WIDTH) - PERFECT MIDDLE GROUND
# =====================

$groupUpdateLog = New-Object System.Windows.Forms.GroupBox
$groupUpdateLog.Text = "Update Log"
$groupUpdateLog.Location = New-Object System.Drawing.Point(10, 370)
$groupUpdateLog.Size = New-Object System.Drawing.Size(950, 220)
$groupUpdateLog.ForeColor = $colorText
$tabMaintenance.Controls.Add($groupUpdateLog)

$txtUpdateLog = New-Object System.Windows.Forms.TextBox
$txtUpdateLog.Multiline = $true
$txtUpdateLog.ScrollBars = "Vertical"
$txtUpdateLog.ReadOnly = $true
$txtUpdateLog.BackColor = $colorConsoleBack
$txtUpdateLog.ForeColor = $colorConsoleText
$txtUpdateLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtUpdateLog.Location = New-Object System.Drawing.Point(10, 25)
$txtUpdateLog.Size = New-Object System.Drawing.Size(930, 155)
$groupUpdateLog.Controls.Add($txtUpdateLog)

# Log Action Buttons (Bottom of Log Group)
$btnClearUpdateLog = New-Object System.Windows.Forms.Button
$btnClearUpdateLog.Text = "Clear"
$btnClearUpdateLog.Location = New-Object System.Drawing.Point(10, 185)
$btnClearUpdateLog.Size = New-Object System.Drawing.Size(100, 25)
Style-Button $btnClearUpdateLog
$btnClearUpdateLog.Add_Click({ Clear-UpdateLog })
$groupUpdateLog.Controls.Add($btnClearUpdateLog)

$btnSaveUpdateLog = New-Object System.Windows.Forms.Button
$btnSaveUpdateLog.Text = "Save to File"
$btnSaveUpdateLog.Location = New-Object System.Drawing.Point(120, 185)
$btnSaveUpdateLog.Size = New-Object System.Drawing.Size(100, 25)
Style-Button $btnSaveUpdateLog
$btnSaveUpdateLog.Add_Click({ Save-UpdateLogToFile })
$groupUpdateLog.Controls.Add($btnSaveUpdateLog)

$btnCopyUpdateLog = New-Object System.Windows.Forms.Button
$btnCopyUpdateLog.Text = "Copy to Clipboard"
$btnCopyUpdateLog.Location = New-Object System.Drawing.Point(230, 185)
$btnCopyUpdateLog.Size = New-Object System.Drawing.Size(120, 25)
Style-Button $btnCopyUpdateLog
$btnCopyUpdateLog.Add_Click({ Copy-UpdateLogToClipboard })
$groupUpdateLog.Controls.Add($btnCopyUpdateLog)

# =====================
# MOD MANAGER TAB (REORGANIZED FOR 720P - 2 COLUMN LAYOUT)
# =====================

$tabModManager = New-Object System.Windows.Forms.TabPage
$tabModManager.Text = "Mod Manager"
$tabModManager.BackColor = $colorBack
$tabs.TabPages.Add($tabModManager)


# =====================
# INSTALLED MODS LIST (ListView)
# =====================

$script:modListView = New-Object System.Windows.Forms.ListView
$script:modListView.Location = New-Object System.Drawing.Point(10, 75)
$script:modListView.Size = New-Object System.Drawing.Size(750, 520)
$script:modListView.View = [System.Windows.Forms.View]::Details
$script:modListView.FullRowSelect = $true
$script:modListView.GridLines = $true
$script:modListView.BackColor = $colorTextboxBack
$script:modListView.ForeColor = $colorTextboxText
$script:modListView.Font = New-Object System.Drawing.Font("Consolas", 9)

# Enable drag-and-drop
$script:modListView.AllowDrop = $true
$script:modListView.Add_DragEnter({ Handle-ModDragEnter $_ $args[1] })
$script:modListView.Add_DragDrop({ Handle-ModDragDrop $_ $args[1] })

# Add columns
$script:modListView.Columns.Add("Mod Name", 250) | Out-Null
$script:modListView.Columns.Add("Status", 100) | Out-Null
$script:modListView.Columns.Add("Version", 80) | Out-Null
$script:modListView.Columns.Add("CF Status", 150) | Out-Null
$script:modListView.Columns.Add("File Size", 80) | Out-Null
$script:modListView.Columns.Add("File Path", 200) | Out-Null

$tabModManager.Controls.Add($script:modListView)

# =====================
# LEFT COLUMN BUTTONS (X=770, Width=95)
# =====================

$btnRefreshMods = New-Object System.Windows.Forms.Button
$btnRefreshMods.Text = "Refresh"
$btnRefreshMods.Location = New-Object System.Drawing.Point(770, 75)
$btnRefreshMods.Size = New-Object System.Drawing.Size(95, 35)
Style-Button $btnRefreshMods
$btnRefreshMods.Add_Click({ Refresh-ModList })
$tabModManager.Controls.Add($btnRefreshMods)
$toolTip.SetToolTip($btnRefreshMods, "Refresh the mod list")

$btnToggleMod = New-Object System.Windows.Forms.Button
$btnToggleMod.Text = "Toggle Mod"
$btnToggleMod.Location = New-Object System.Drawing.Point(770, 115)
$btnToggleMod.Size = New-Object System.Drawing.Size(95, 35)
Style-Button $btnToggleMod
$btnToggleMod.Add_Click({ Toggle-ModState })
$tabModManager.Controls.Add($btnToggleMod)
$toolTip.SetToolTip($btnToggleMod, "Enable or disable selected mod")

$btnOpenModsFolder = New-Object System.Windows.Forms.Button
$btnOpenModsFolder.Text = "Mod Folder"
$btnOpenModsFolder.Location = New-Object System.Drawing.Point(770, 155)
$btnOpenModsFolder.Size = New-Object System.Drawing.Size(95, 35)
Style-Button $btnOpenModsFolder
$btnOpenModsFolder.Add_Click({ Open-ModsFolder })
$tabModManager.Controls.Add($btnOpenModsFolder)
$toolTip.SetToolTip($btnOpenModsFolder, "Open mods folder in explorer")

$btnRemoveMod = New-Object System.Windows.Forms.Button
$btnRemoveMod.Text = "Delete Mod"
$btnRemoveMod.Location = New-Object System.Drawing.Point(770, 195)
$btnRemoveMod.Size = New-Object System.Drawing.Size(95, 35)
$btnRemoveMod.BackColor = [System.Drawing.Color]::FromArgb(120, 40, 40)
$btnRemoveMod.ForeColor = $colorButtonText
$btnRemoveMod.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRemoveMod.Add_Click({ Remove-SelectedMod })
$tabModManager.Controls.Add($btnRemoveMod)
$toolTip.SetToolTip($btnRemoveMod, "Permanently delete selected mod")

$btnCheckConflicts = New-Object System.Windows.Forms.Button
$btnCheckConflicts.Text = "Check Conflicts"
$btnCheckConflicts.Location = New-Object System.Drawing.Point(770, 235)
$btnCheckConflicts.Size = New-Object System.Drawing.Size(95, 35)
$btnCheckConflicts.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 40)
$btnCheckConflicts.ForeColor = $colorButtonText
$btnCheckConflicts.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCheckConflicts.Add_Click({ Check-ModConflicts })
$tabModManager.Controls.Add($btnCheckConflicts)
$toolTip.SetToolTip($btnCheckConflicts, "Check for mod conflicts")

# Mod Config Buttons
$btnBrowseModConfigs = New-Object System.Windows.Forms.Button
$btnBrowseModConfigs.Text = "Browse Configs"
$btnBrowseModConfigs.Location = New-Object System.Drawing.Point(770, 280)
$btnBrowseModConfigs.Size = New-Object System.Drawing.Size(95, 35)
$btnBrowseModConfigs.BackColor = [System.Drawing.Color]::FromArgb(50, 100, 150)
$btnBrowseModConfigs.ForeColor = [System.Drawing.Color]::White
$btnBrowseModConfigs.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseModConfigs.Add_Click({ Show-ModConfigPicker })
$tabModManager.Controls.Add($btnBrowseModConfigs)
$toolTip.SetToolTip($btnBrowseModConfigs, "Browse mod config folders")

$btnOpenSelectedModConfig = New-Object System.Windows.Forms.Button
$btnOpenSelectedModConfig.Text = "Open Selected"
$btnOpenSelectedModConfig.Location = New-Object System.Drawing.Point(770, 320)
$btnOpenSelectedModConfig.Size = New-Object System.Drawing.Size(95, 35)
Style-Button $btnOpenSelectedModConfig
$btnOpenSelectedModConfig.Add_Click({
    if ($script:modListView.SelectedItems.Count -gt 0) {
        $selectedModName = $script:modListView.SelectedItems[0].SubItems[0].Text
        # Remove .jar extension if present
        $modName = $selectedModName -replace '\.jar$', ''
        Open-ModConfigFolder $modName
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select a mod from the list first.",
            "No Selection",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
})
$tabModManager.Controls.Add($btnOpenSelectedModConfig)
$toolTip.SetToolTip($btnOpenSelectedModConfig, "Open selected mod's config")

# =====================
# RIGHT COLUMN BUTTONS (X=875, Width=95)
# =====================

# CurseForge Buttons
$btnLinkToCurseForge = New-Object System.Windows.Forms.Button
$btnLinkToCurseForge.Text = "Link Mod CF"
$btnLinkToCurseForge.Location = New-Object System.Drawing.Point(875, 75)
$btnLinkToCurseForge.Size = New-Object System.Drawing.Size(95, 35)
$btnLinkToCurseForge.BackColor = [System.Drawing.Color]::FromArgb(100, 65, 165)
$btnLinkToCurseForge.ForeColor = $colorButtonText
$btnLinkToCurseForge.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLinkToCurseForge.Add_Click({ Show-CurseForgeLinkDialog })
$tabModManager.Controls.Add($btnLinkToCurseForge)
$toolTip.SetToolTip($btnLinkToCurseForge, "Link mod to CurseForge")

$btnCheckUpdates = New-Object System.Windows.Forms.Button
$btnCheckUpdates.Text = "Check Updates"
$btnCheckUpdates.Location = New-Object System.Drawing.Point(875, 115)
$btnCheckUpdates.Size = New-Object System.Drawing.Size(95, 35)
$btnCheckUpdates.BackColor = [System.Drawing.Color]::FromArgb(64, 96, 224)
$btnCheckUpdates.ForeColor = $colorButtonText
$btnCheckUpdates.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCheckUpdates.Add_Click({ Check-AllModUpdates })
$tabModManager.Controls.Add($btnCheckUpdates)
$toolTip.SetToolTip($btnCheckUpdates, "Check for mod updates")

$btnUpdateMod = New-Object System.Windows.Forms.Button
$btnUpdateMod.Text = "Update Mod"
$btnUpdateMod.Location = New-Object System.Drawing.Point(875, 155)
$btnUpdateMod.Size = New-Object System.Drawing.Size(95, 35)
$btnUpdateMod.BackColor = [System.Drawing.Color]::FromArgb(255, 140, 0)
$btnUpdateMod.ForeColor = $colorButtonText
$btnUpdateMod.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnUpdateMod.Add_Click({ Update-SelectedMod })
$tabModManager.Controls.Add($btnUpdateMod)
$toolTip.SetToolTip($btnUpdateMod, "Update selected mod")

$btnCurseForge = New-Object System.Windows.Forms.Button
$btnCurseForge.Text = "Get More Mods"
$btnCurseForge.Location = New-Object System.Drawing.Point(875, 195)
$btnCurseForge.Size = New-Object System.Drawing.Size(95, 35)
$btnCurseForge.BackColor = [System.Drawing.Color]::FromArgb(240, 100, 20)
$btnCurseForge.ForeColor = [System.Drawing.Color]::White
$btnCurseForge.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCurseForge.Add_Click({ Open-CurseForge })
$tabModManager.Controls.Add($btnCurseForge)
$toolTip.SetToolTip($btnCurseForge, "Browse CurseForge website")

# Separator
$lblSeparator = New-Object System.Windows.Forms.Label
$lblSeparator.Text = "---"
$lblSeparator.Location = New-Object System.Drawing.Point(770, 360)
$lblSeparator.Size = New-Object System.Drawing.Size(200, 15)
$lblSeparator.ForeColor = [System.Drawing.Color]::Gray
$tabModManager.Controls.Add($lblSeparator)

# =====================
# MOD NOTES SECTION (Bottom)
# =====================

$lblNotesTitle = New-Object System.Windows.Forms.Label
$lblNotesTitle.Text = "Mod Notes / Description:"
$lblNotesTitle.Location = New-Object System.Drawing.Point(770, 380)
$lblNotesTitle.Size = New-Object System.Drawing.Size(200, 20)
$lblNotesTitle.ForeColor = $colorText
$lblNotesTitle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabModManager.Controls.Add($lblNotesTitle)

$script:txtModNotes = New-Object System.Windows.Forms.TextBox
$script:txtModNotes.Multiline = $true
$script:txtModNotes.ScrollBars = "Vertical"
$script:txtModNotes.Location = New-Object System.Drawing.Point(770, 405)
$script:txtModNotes.Size = New-Object System.Drawing.Size(200, 120)
$script:txtModNotes.BackColor = $colorTextboxBack
$script:txtModNotes.ForeColor = $colorTextboxText
$script:txtModNotes.Font = New-Object System.Drawing.Font("Consolas", 8)
$script:txtModNotes.Text = "Select a mod to view or edit notes..."
$script:txtModNotes.ReadOnly = $true
$tabModManager.Controls.Add($script:txtModNotes)

$btnSaveNotes = New-Object System.Windows.Forms.Button
$btnSaveNotes.Text = "Save Notes"
$btnSaveNotes.Location = New-Object System.Drawing.Point(770, 530)
$btnSaveNotes.Size = New-Object System.Drawing.Size(200, 25)
Style-Button $btnSaveNotes
$btnSaveNotes.Add_Click({ Update-ModNotes })
$tabModManager.Controls.Add($btnSaveNotes)
$toolTip.SetToolTip($btnSaveNotes, "Save notes for the selected mod")

# Add event to show notes when mod is selected
$script:modListView.Add_SelectedIndexChanged({ Show-ModNotes })

# =====================
# QUICK TIPS (Bottom)
# =====================

$lblQuickTips = New-Object System.Windows.Forms.Label
$lblQuickTips.Text = "TIP: Drag .jar files into list | GREEN=Enabled | RED=Disabled | YELLOW=Conflict | ORANGE=Update"
$lblQuickTips.Location = New-Object System.Drawing.Point(10, 605)
$lblQuickTips.Size = New-Object System.Drawing.Size(750, 20)
$lblQuickTips.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
$lblQuickTips.Font = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Italic)
$tabModManager.Controls.Add($lblQuickTips)

# =====================
# RUN GUI SETUP
# =====================

# Disable maximize and minimize buttons since resizing breaks the UI
$form.MinimizeBox = $true
$form.MaximizeBox = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.AutoScroll = $true
$tabServer.AutoScroll = $true
$tabConfig.AutoScroll = $true
$tabMaintenance.AutoScroll = $true
$tabModManager.AutoScroll = $true

# Load initial config if present
Load-Config

# Initial file check
Check-ServerFiles

# Create tray icon (for minimize-to-tray)
Create-TrayIcon

# Initialize system CPU counter & start persistent stats timer if not already started
if (-not $script:systemCpuCounter) {
    try {
        $script:systemCpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor","% Processor Time","_Total",$true)
        $null = $script:systemCpuCounter.NextValue()
    } catch {
        $script:systemCpuCounter = $null
    }
}

if (-not $script:statsTimer) {
    $script:statsTimer = New-Object System.Windows.Forms.Timer
    $script:statsTimer.Interval = 1000
    $script:statsTimer.Add_Tick({ Update-CPUAndRAMUsage })
    $script:statsTimer.Start()
}

# Load saved settings
Load-Settings

# Load CurseForge metadata
Load-CurseForgeMetadata

# Refresh mod list to show CF status
Refresh-ModList


# Clean shutdown when GUI is closed: stop server, unregister events, dispose timers/counters/watchers, save settings
$form.Add_FormClosing({
    try { Stop-Server } catch {}

    # Save window settings
    try { Save-Settings } catch {}

    # Unregister any remaining object events
    try { if ($script:serverOutReg) { Unregister-Event -SubscriptionId $script:serverOutReg.Id -ErrorAction SilentlyContinue } } catch {}
    try { if ($script:serverErrReg) { Unregister-Event -SubscriptionId $script:serverErrReg.Id -ErrorAction SilentlyContinue } } catch {}
    try { if ($script:logWatcherRegistration) { Unregister-Event -SubscriptionId $script:logWatcherRegistration.Id -ErrorAction SilentlyContinue } } catch {}

    # Dispose performance counters and timers
    try { if ($script:cpuCounter) { $script:cpuCounter.Dispose() } } catch {}
    try { if ($script:systemCpuCounter) { $script:systemCpuCounter.Dispose() } } catch {}
    try { if ($script:statsTimer) { $script:statsTimer.Stop(); $script:statsTimer.Dispose() } } catch {}
    try { if ($script:logFallbackTimer) { $script:logFallbackTimer.Stop(); $script:logFallbackTimer.Dispose() } } catch {}
    try { if ($script:logTimer) { $script:logTimer.Stop(); $script:logTimer.Dispose() } } catch {}
    try { if ($script:healthMonitorTimer) { $script:healthMonitorTimer.Stop(); $script:healthMonitorTimer.Dispose() } } catch {}
	
    # Dispose watcher
    try { if ($script:logWatcher) { $script:logWatcher.EnableRaisingEvents = $false; $script:logWatcher.Dispose() } } catch {}

    # Dispose notify icon
    try { if ($script:notifyIcon) { $script:notifyIcon.Visible = $false; $script:notifyIcon.Dispose() } } catch {}
})

# Show the form
$form.ShowDialog()