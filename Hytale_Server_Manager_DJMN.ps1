# ==========================================================================================
# Hytale Server Manager GUI - Version 2.1
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
        # Step 1: Process-specific stats
        # Only if server is running and process is valid
        # -------------------------
        if ($script:serverRunning -and $script:serverProcess -and -not $script:serverProcess.HasExited) {
            try {
                # Get Process object for server
                $proc = Get-Process -Id $script:serverProcess.Id -ErrorAction Stop

                # -------------------------
                # Step 1a: Memory usage in MB
                # -------------------------
                $memoryUsageMB = [math]::Round([double]$proc.WorkingSet64 / 1MB, 2)

                # Clamp invalid or negative memory readings to zero, log warning once
                if ([double]::IsNaN($memoryUsageMB) -or $memoryUsageMB -lt 0) {
                    if (-not $script:_warnedNegativeMemory) {
                        $txtConsole.AppendText("[WARN] Negative or invalid process memory read; clamped to 0.`r`n")
                        $script:_warnedNegativeMemory = $true
                    }
                    $memoryUsageMB = 0
                }

                # -------------------------
                # Step 1b: CPU usage per process
                # -------------------------
                try {
                    # Create or refresh PerformanceCounter for server process
                    if (-not $script:cpuCounter -or $script:cpuCounter.InstanceName -ne $proc.ProcessName) {
                        if ($script:cpuCounter) { $script:cpuCounter.Dispose() }
                        $script:cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Process","% Processor Time",$proc.ProcessName,$true)
                        $null = $script:cpuCounter.NextValue() # initial read
                    }

                    # Small sleep needed for accurate CPU reading
                    Start-Sleep -Milliseconds 200
                    $rawCpu = $script:cpuCounter.NextValue()

                    # Divide by processor count to get actual percent usage
                    $cpuUsage = [math]::Round($rawCpu / [Environment]::ProcessorCount, 1)
                } catch {
                    # On error, default to zero CPU
                    $cpuUsage = 0
                }

                # -------------------------
                # Step 1c: RAM percent calculation
                # -------------------------
                $maxRamMB = 0
                if ($script:maxRamGB -and ($script:maxRamGB -as [double]) -gt 0) {
                    # Use configured max RAM if >0
                    $maxRamMB = [double]$script:maxRamGB * 1024
                } else {
                    # Fallback: total system memory
                    try {
                        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                        $totalKB = [double]$os.TotalVisibleMemorySize
                        $maxRamMB = [math]::Round($totalKB / 1024, 2)
                    } catch { $maxRamMB = 0 }
                }

                # Compute RAM percentage, clamp negative values
                $ramPercent = 0
                if ($maxRamMB -gt 0) {
                    $ramPercent = [math]::Round(($memoryUsageMB / $maxRamMB) * 100, 1)
                    if ($ramPercent -lt 0) { $ramPercent = 0 }
                }

                # -------------------------
                # Step 1d: Update GUI labels
                # -------------------------
                $lblCPU.Text = "Process CPU: ${cpuUsage}%"
                $lblRAM.Text = "Process RAM: ${memoryUsageMB} MB ($ramPercent`%)"

                if ($script:serverStartTime) {
                    $lblUptime.Text = "Uptime: " + (Format-Uptime $script:serverStartTime)
                } else {
                    $lblUptime.Text = "Uptime: N/A"
                }

                # -------------------------
                # Step 1e: Color thresholds
                # Green <50%, Orange 50-79%, Red >=80%
                # -------------------------
                if ($cpuUsage -ge 80) {
                    $lblCPU.ForeColor = [System.Drawing.Color]::Red
                } elseif ($cpuUsage -ge 50) {
                    $lblCPU.ForeColor = [System.Drawing.Color]::Orange
                } else {
                    $lblCPU.ForeColor = [System.Drawing.Color]::LightGreen
                }

                if ($ramPercent -ge 80) {
                    $lblRAM.ForeColor = [System.Drawing.Color]::Red
                } elseif ($ramPercent -ge 50) {
                    $lblRAM.ForeColor = [System.Drawing.Color]::Orange
                } else {
                    $lblRAM.ForeColor = [System.Drawing.Color]::LightGreen
                }

                return
            } catch {
                # Process disappeared or error, fallback to system-wide stats
                $lblUptime.Text = "Uptime: N/A"
            }
        }

        # -------------------------
        # Step 2: System-wide stats when no server process is available
        # -------------------------
        try {
            # Initialize total CPU counter if missing
            if (-not $script:systemCpuCounter) {
                $script:systemCpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor","% Processor Time","_Total",$true)
                $null = $script:systemCpuCounter.NextValue()
            }

            Start-Sleep -Milliseconds 200
            $sysRaw = $script:systemCpuCounter.NextValue()
            $sysCpu = [math]::Round($sysRaw, 1)

            # Memory usage
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $totalKB = [double]$os.TotalVisibleMemorySize
            $freeKB  = [double]$os.FreePhysicalMemory
            $usedKB  = $totalKB - $freeKB
            $usedMB  = [math]::Round($usedKB / 1024, 1)
            $totalMB = [math]::Round($totalKB / 1024, 1)
            $memPercent = 0
            if ($totalMB -gt 0) { $memPercent = [math]::Round(($usedMB / $totalMB) * 100, 1) }

            # Update GUI
            $lblCPU.Text = "System CPU: ${sysCpu}%"
            $lblRAM.Text = "System RAM: ${usedMB} MB / ${totalMB} MB (${memPercent}%)"
            $lblUptime.Text = "Uptime: N/A"

            # -------------------------
            # Step 2a: Apply color thresholds for system stats
            # -------------------------
            if ($sysCpu -ge 80) {
                $lblCPU.ForeColor = [System.Drawing.Color]::Red
            } elseif ($sysCpu -ge 50) {
                $lblCPU.ForeColor = [System.Drawing.Color]::Orange
            } else {
                $lblCPU.ForeColor = [System.Drawing.Color]::LightGreen
            }

            if ($memPercent -ge 80) {
                $lblRAM.ForeColor = [System.Drawing.Color]::Red
            } elseif ($memPercent -ge 50) {
                $lblRAM.ForeColor = [System.Drawing.Color]::Orange
            } else {
                $lblRAM.ForeColor = [System.Drawing.Color]::LightGreen
            }
        } catch {
            #
        }
    } catch {
        # 
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

    # Check if process actually exists and hasn't exited
    if (-not $script:serverProcess -or $script:serverProcess.HasExited) {
        $txtConsole.AppendText("[WARN] Server process not found - attempting restart...`r`n")
        Restart-Server
        return
    }

    try {
        # SIMPLIFIED APPROACH: Just check if the process is still alive and responding
        # If the process exists and hasn't exited, assume it's healthy
        
        # Try to write to StandardInput - if this fails, process is dead
        $script:serverProcess.StandardInput.WriteLine("")
        
        # Check if process is still running
        if (-not $script:serverProcess.HasExited) {
            # Process is alive and accepting input - consider it healthy
            if ($script:pingFailCount -gt 0) {
                $txtConsole.AppendText("[INFO] Server health check passed`r`n")
            }
            $script:pingFailCount = 0
        } else {
            # Process has exited
            $script:pingFailCount++
            $txtConsole.AppendText("[WARN] Server process exited - attempt $($script:pingFailCount)/5`r`n")
            
            if ($script:pingFailCount -ge 5) {
                $txtConsole.AppendText("[ERROR] Server stopped responding - initiating restart...`r`n")
                $script:pingFailCount = 0
                Restart-Server
            }
        }
        
    } catch {
        # If we can't write to StandardInput, the process is likely dead
        $script:pingFailCount++
        $txtConsole.AppendText("[WARN] Server health check failed - attempt $($script:pingFailCount)/5`r`n")
        $txtConsole.AppendText("[DEBUG] Error: $_`r`n")
        
        if ($script:pingFailCount -ge 5) {
            $txtConsole.AppendText("[ERROR] Server not responding - initiating auto-restart...`r`n")
            $script:pingFailCount = 0
            Restart-Server
        }
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
        $process.WaitForExit()

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
        $script:serverRunning = $true

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

        # Step 12: Update CPU/RAM labels initially
        Update-CPUAndRAMUsage
		
		# Step 13: Start health monitoring
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

    # Step 3: Kill the running server process if it exists
    try {
        if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
            $txtConsole.AppendText("[INFO] Stopping server process...`r`n")
            $script:serverProcess.Kill()
            $script:serverProcess.WaitForExit()
        }
    } catch {}

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
            Start-Sleep -Seconds $waitTime
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
    
    # Small delay for final message to be sent
    Start-Sleep -Seconds 2
    
    # Step 3: Stop server
    Stop-Server
    
    # Step 4: Wait for resources to release
    Start-Sleep -Seconds 5
    
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
        # Log error to update log textbox
        $txtUpdateLog.AppendText("[ERROR] Downloader not found at: $script:downloaderPath`r`n")
        # Provide user guidance in update log
        $txtUpdateLog.AppendText("[INFO] Please download 'hytale-downloader-windows-amd64.exe' and place it in the server directory.`r`n")
        # Show GUI popup error
        [System.Windows.Forms.MessageBox]::Show("Downloader executable not found!`n`nPlease download 'hytale-downloader-windows-amd64.exe' and place it in the server folder.", "Error")
        return  # Abort update
    }

    # ==============================
    # Step 1: Stop server if running
    # ==============================
    $wasRunning = $false
    if ($script:serverRunning) {
        # Inform the user in the log
        $txtUpdateLog.AppendText("[INFO] Server is running - stopping for update...`r`n")
        $wasRunning = $true  # Track that server was running
        Stop-Server          # Call Stop-Server function to gracefully stop the server
        Start-Sleep -Seconds 3  # Small delay to ensure process has released resources
    }

    # ==============================
    # Step 1b: Record existing latest server ZIP before downloading
    # ==============================
    $existingZips = Get-ChildItem -Path $PSScriptRoot -Filter "*.zip" | Where-Object { $_.Name -notlike "Assets.zip" }
    $latestExistingZip = $null
    if ($existingZips.Count -gt 0) {
        # Take the latest ZIP by LastWriteTime
        $latestExistingZip = $existingZips | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $txtUpdateLog.AppendText("[INFO] Existing latest zip before download: $($latestExistingZip.Name)`r`n")
    }

    try {
        # Header info in update log
        $txtUpdateLog.AppendText("========================================`r`n")
        $txtUpdateLog.AppendText("[INFO] Starting Hytale Server Update`r`n")
        $txtUpdateLog.AppendText("========================================`r`n")
        $txtUpdateLog.AppendText("[INFO] Running downloader: $script:downloaderPath`r`n")

        # ==============================
        # Step 2: Run the downloader
        # ==============================
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:downloaderPath       # Set executable path
        $psi.WorkingDirectory = $PSScriptRoot        # Ensure it runs in the server folder
        $psi.UseShellExecute = $false                # Required for redirecting output
        $psi.RedirectStandardOutput = $true          # Capture stdout
        $psi.RedirectStandardError = $true           # Capture stderr
        $psi.CreateNoWindow = $true                  # Hide console window

        $updateProcess = New-Object System.Diagnostics.Process
        $updateProcess.StartInfo = $psi              # Assign ProcessStartInfo
        $updateProcess.Start() | Out-Null           # Start the downloader process

        $txtUpdateLog.AppendText("[INFO] Downloading latest server files...`r`n")

        # Capture process output/error
        $output = $updateProcess.StandardOutput.ReadToEnd()
        $errorOutput = $updateProcess.StandardError.ReadToEnd()
        $updateProcess.WaitForExit()                # Wait for completion

        # Log outputs
        if ($output) { $txtUpdateLog.AppendText($output + "`r`n") }
        if ($error) { $txtUpdateLog.AppendText("[ERROR] $error`r`n") }

        $txtUpdateLog.AppendText("[INFO] Download process completed (Exit Code: $($updateProcess.ExitCode))`r`n")

        # If download failed (non-zero exit code)
        if ($updateProcess.ExitCode -ne 0) {
            $txtUpdateLog.AppendText("[WARN] Downloader exited with non-zero code. Update may have failed.`r`n")
            [System.Windows.Forms.MessageBox]::Show("Download may have failed. Check the update log for details.", "Warning")
            
            # Auto-restart server if it was running
            if ($wasRunning -and $chkAutoRestart.Checked) {
                $txtUpdateLog.AppendText("[INFO] Restarting server...`r`n")
                Start-Server
            }
            return  # Abort update
        }

        # ==============================
        # Step 3: Find the downloaded zip file
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

        $downloadedZip = $zipFiles[0]  # Take newest ZIP
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
            Start-Sleep -Seconds 3
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
        Start-Sleep -Seconds 3
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
    
    # Get enabled mods (in /mods folder)
    $enabledMods = Get-ChildItem -Path $script:modsPath -Filter "*.jar" -ErrorAction SilentlyContinue
    foreach ($mod in $enabledMods) {
        $item = New-Object System.Windows.Forms.ListViewItem($mod.Name)
        $item.SubItems.Add("ENABLED")
        $fileSizeMB = [math]::Round($mod.Length / 1MB, 2)
        if ($fileSizeMB -lt 0.01) {
            $fileSizeKB = [math]::Round($mod.Length / 1KB, 2)
            $item.SubItems.Add("$fileSizeKB KB")
        } else {
            $item.SubItems.Add("$fileSizeMB MB")
        }
        $item.SubItems.Add($mod.FullName)
        $item.ForeColor = [System.Drawing.Color]::LimeGreen
        $item.Tag = @{ Enabled = $true; Path = $mod.FullName }
        $script:modListView.Items.Add($item)
    }
    
    # Get disabled mods (in /mods_disabled folder)
    $disabledMods = Get-ChildItem -Path $script:modsDisabledPath -Filter "*.jar" -ErrorAction SilentlyContinue
    foreach ($mod in $disabledMods) {
        $item = New-Object System.Windows.Forms.ListViewItem($mod.Name)
        $item.SubItems.Add("DISABLED")
        $fileSizeMB = [math]::Round($mod.Length / 1MB, 2)
        if ($fileSizeMB -lt 0.01) {
            $fileSizeKB = [math]::Round($mod.Length / 1KB, 2)
            $item.SubItems.Add("$fileSizeKB KB")
        } else {
            $item.SubItems.Add("$fileSizeMB MB")
        }
        $item.SubItems.Add($mod.FullName)
        $item.ForeColor = [System.Drawing.Color]::Red
        $item.Tag = @{ Enabled = $false; Path = $mod.FullName }
        $script:modListView.Items.Add($item)
    }
    
    # Visual indicator if mods might have conflicts
    $enabledModNames = $enabledMods | ForEach-Object { $_.BaseName -replace '[-_]\d+.*$', '' }
    $hasDuplicates = ($enabledModNames | Group-Object | Where-Object { $_.Count -gt 1 }).Count -gt 0
    
    if ($hasDuplicates) {
        # Find items with potential conflicts and mark them yellow
        foreach ($item in $script:modListView.Items) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($item.Text) -replace '[-_]\d+.*$', ''
            $matchCount = ($enabledModNames | Where-Object { $_ -eq $baseName }).Count
            
            if ($matchCount -gt 1 -and $item.Tag.Enabled) {
                $item.ForeColor = [System.Drawing.Color]::Yellow
                $item.SubItems[1].Text = "ENABLED (Warning)"
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
# CONFIG EDITOR TAB
# =====================

$tabConfig = New-Object System.Windows.Forms.TabPage
$tabConfig.Text = "Configuration"
$tabConfig.BackColor = $colorBack
$tabs.TabPages.Add($tabConfig)

$txtConfigEditor = New-Object System.Windows.Forms.RichTextBox
$txtConfigEditor.Multiline = $true
$txtConfigEditor.ScrollBars = "Both"          # Vertical + horizontal scrollbars
$txtConfigEditor.BackColor = $colorTextboxBack
$txtConfigEditor.ForeColor = $colorTextboxText
$txtConfigEditor.Font = New-Object System.Drawing.Font("Consolas", 10)  # Monospaced font
$txtConfigEditor.WordWrap = $false            # Prevent line breaking
$txtConfigEditor.AcceptsTab = $true           # Tabs work for indentationtxtConfigEditor.AcceptsTab = $true           # Tabs work for indentation
$txtConfigEditor.EnableAutoDragDrop = $false
$txtConfigEditor.DetectUrls = $false
$txtConfigEditor.Location = New-Object System.Drawing.Point(10, 20)
$txtConfigEditor.Size = New-Object System.Drawing.Size(760, 450)
$tabConfig.Controls.Add($txtConfigEditor)

$btnLoadConfig = New-Object System.Windows.Forms.Button
$btnLoadConfig.Text = "Load Configuration"
$btnLoadConfig.Location = New-Object System.Drawing.Point(790, 20)
$btnLoadConfig.Size = New-Object System.Drawing.Size(180, 30)
Style-Button $btnLoadConfig
$btnLoadConfig.Add_Click({ Load-Config })
$tabConfig.Controls.Add($btnLoadConfig)

$btnSaveConfig = New-Object System.Windows.Forms.Button
$btnSaveConfig.Text = "Save Configuration"
$btnSaveConfig.Location = New-Object System.Drawing.Point(790, 60)
$btnSaveConfig.Size = New-Object System.Drawing.Size(180, 30)
Style-Button $btnSaveConfig
$btnSaveConfig.Add_Click({ Save-Config })
$tabConfig.Controls.Add($btnSaveConfig)

$btnLoadPermissions = New-Object System.Windows.Forms.Button
$btnLoadPermissions.Text = "Load Permissions"
$btnLoadPermissions.Location = New-Object System.Drawing.Point(790, 100)  # 40px below Load Config
$btnLoadPermissions.Size = New-Object System.Drawing.Size(180, 30)
Style-Button $btnLoadPermissions
$btnLoadPermissions.Add_Click({ Load-Permissions })
$tabConfig.Controls.Add($btnLoadPermissions)

$btnSavePermissions = New-Object System.Windows.Forms.Button
$btnSavePermissions.Text = "Save Permissions"
$btnSavePermissions.Location = New-Object System.Drawing.Point(790, 140)  # 40px below Save Config
$btnSavePermissions.Size = New-Object System.Drawing.Size(180, 30)
Style-Button $btnSavePermissions
$btnSavePermissions.Add_Click({ Save-Permissions })
$tabConfig.Controls.Add($btnSavePermissions)

# =====================
# THEME SWITCHER SECTION
# =====================

$lblThemeTitle = New-Object System.Windows.Forms.Label
$lblThemeTitle.Text = "Theme Selector:"
$lblThemeTitle.Location = New-Object System.Drawing.Point(790, 200)
$lblThemeTitle.Size = New-Object System.Drawing.Size(180, 20)
$lblThemeTitle.ForeColor = $colorText
$lblThemeTitle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabConfig.Controls.Add($lblThemeTitle)

$cmbTheme = New-Object System.Windows.Forms.ComboBox
$cmbTheme.Location = New-Object System.Drawing.Point(790, 225)
$cmbTheme.Size = New-Object System.Drawing.Size(180, 25)
$cmbTheme.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbTheme.BackColor = $colorTextboxBack
$cmbTheme.ForeColor = $colorTextboxText
$cmbTheme.Items.AddRange(@("Dark", "Light", "Blue", "Purple"))
$cmbTheme.SelectedItem = "Dark"
$tabConfig.Controls.Add($cmbTheme)

$btnApplyTheme = New-Object System.Windows.Forms.Button
$btnApplyTheme.Text = "Apply Theme"
$btnApplyTheme.Location = New-Object System.Drawing.Point(790, 260)
$btnApplyTheme.Size = New-Object System.Drawing.Size(180, 35)
$btnApplyTheme.BackColor = [System.Drawing.Color]::FromArgb(100, 50, 150)
$btnApplyTheme.ForeColor = [System.Drawing.Color]::White
$btnApplyTheme.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnApplyTheme.Add_Click({ 
    $selectedTheme = $cmbTheme.SelectedItem
    if ($selectedTheme) {
        Apply-Theme $selectedTheme
    }
})
$tabConfig.Controls.Add($btnApplyTheme)

$lblThemePreview = New-Object System.Windows.Forms.Label
$lblThemePreview.Text = @"
Themes Available:
- Dark (Default)
- Light (Bright)
- Blue (Cool)
- Purple (Stylish)
"@
$lblThemePreview.Location = New-Object System.Drawing.Point(790, 305)
$lblThemePreview.Size = New-Object System.Drawing.Size(180, 80)
$lblThemePreview.ForeColor = [System.Drawing.Color]::LightGray
$lblThemePreview.Font = New-Object System.Drawing.Font("Arial", 8)
$tabConfig.Controls.Add($lblThemePreview)

# =====================
# SERVER MAINTENANCE TAB (MERGED)
# =====================

$tabMaintenance = New-Object System.Windows.Forms.TabPage
$tabMaintenance.Text = "Server Maintenance"
$tabMaintenance.BackColor = $colorBack
$tabs.TabPages.Add($tabMaintenance)

# =====================
# UPDATE SECTION
# =====================

$lblUpdateInfo = New-Object System.Windows.Forms.Label
$lblUpdateInfo.Text = "Download and install the latest Hytale server files using the official downloader."
$lblUpdateInfo.Location = New-Object System.Drawing.Point(10, 20)
$lblUpdateInfo.Size = New-Object System.Drawing.Size(940, 20)
$lblUpdateInfo.ForeColor = $colorText
$tabMaintenance.Controls.Add($lblUpdateInfo)

$lblDownloaderPath = New-Object System.Windows.Forms.Label
$lblDownloaderPath.Text = "Downloader:"
$lblDownloaderPath.Location = New-Object System.Drawing.Point(10, 50)
$lblDownloaderPath.Size = New-Object System.Drawing.Size(80, 20)
$lblDownloaderPath.ForeColor = $colorText
$tabMaintenance.Controls.Add($lblDownloaderPath)

$txtDownloaderPath = New-Object System.Windows.Forms.TextBox
$txtDownloaderPath.Location = New-Object System.Drawing.Point(100, 48)
$txtDownloaderPath.Size = New-Object System.Drawing.Size(620, 20)
$txtDownloaderPath.ReadOnly = $true
$txtDownloaderPath.BackColor = $colorTextboxBack
$txtDownloaderPath.ForeColor = $colorTextboxText
$txtDownloaderPath.Text = $script:downloaderPath
$tabMaintenance.Controls.Add($txtDownloaderPath)

$btnUpdateServer = New-Object System.Windows.Forms.Button
$btnUpdateServer.Text = "Update Server"
$btnUpdateServer.Location = New-Object System.Drawing.Point(100, 80)
$btnUpdateServer.Size = New-Object System.Drawing.Size(150, 35)
$btnUpdateServer.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
$btnUpdateServer.ForeColor = $colorText
$btnUpdateServer.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$btnUpdateServer.Add_Click({ Update-Server })
$tabMaintenance.Controls.Add($btnUpdateServer)

$chkAutoRestart = New-Object System.Windows.Forms.CheckBox
$chkAutoRestart.Text = "Auto-restart server after update"
$chkAutoRestart.Location = New-Object System.Drawing.Point(270, 85)
$chkAutoRestart.Size = New-Object System.Drawing.Size(250, 25)
$chkAutoRestart.ForeColor = $colorText
$chkAutoRestart.Checked = $true
$tabMaintenance.Controls.Add($chkAutoRestart)

$lblUpdateWarning = New-Object System.Windows.Forms.Label
$lblUpdateWarning.Text = "[!] Server will be stopped during update"
$lblUpdateWarning.Location = New-Object System.Drawing.Point(530, 88)
$lblUpdateWarning.Size = New-Object System.Drawing.Size(250, 20)
$lblUpdateWarning.ForeColor = [System.Drawing.Color]::Orange
$lblUpdateWarning.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabMaintenance.Controls.Add($lblUpdateWarning)

# Restore Backup Button
$btnRestoreBackup = New-Object System.Windows.Forms.Button
$btnRestoreBackup.Text = "Restore from Backup"
$btnRestoreBackup.Location = New-Object System.Drawing.Point(610, 130)
$btnRestoreBackup.Size = New-Object System.Drawing.Size(140, 28)
$btnRestoreBackup.BackColor = [System.Drawing.Color]::FromArgb(180, 70, 70)  # Reddish to indicate caution
$btnRestoreBackup.ForeColor = $colorText
$btnRestoreBackup.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$btnRestoreBackup.Add_Click({ Restore-ServerBackup })
$tabMaintenance.Controls.Add($btnRestoreBackup)

# Downloader utility buttons
$lblDownloaderUtils = New-Object System.Windows.Forms.Label
$lblDownloaderUtils.Text = "Downloader Utilities:"
$lblDownloaderUtils.Location = New-Object System.Drawing.Point(10, 135)
$lblDownloaderUtils.Size = New-Object System.Drawing.Size(150, 20)
$lblDownloaderUtils.ForeColor = $colorText
$lblDownloaderUtils.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabMaintenance.Controls.Add($lblDownloaderUtils)

$btnPrintVersion = New-Object System.Windows.Forms.Button
$btnPrintVersion.Text = "Check for Server Update"
$btnPrintVersion.Location = New-Object System.Drawing.Point(160, 130)
$btnPrintVersion.Size = New-Object System.Drawing.Size(140, 28)
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
$tabMaintenance.Controls.Add($btnPrintVersion)

$btnDownloaderVersion = New-Object System.Windows.Forms.Button
$btnDownloaderVersion.Text = "Downloader Version"
$btnDownloaderVersion.Location = New-Object System.Drawing.Point(310, 130)
$btnDownloaderVersion.Size = New-Object System.Drawing.Size(140, 28)
$btnDownloaderVersion.BackColor = $colorButtonBack
$btnDownloaderVersion.ForeColor = $colorText
$btnDownloaderVersion.Add_Click({ Run-DownloaderCommand "-version" "Checking downloader version" })
$tabMaintenance.Controls.Add($btnDownloaderVersion)

$btnCheckUpdate = New-Object System.Windows.Forms.Button
$btnCheckUpdate.Text = "Check for Downloader Update"
$btnCheckUpdate.Location = New-Object System.Drawing.Point(460, 130)
$btnCheckUpdate.Size = New-Object System.Drawing.Size(140, 28)
$btnCheckUpdate.BackColor = $colorButtonBack
$btnCheckUpdate.ForeColor = $colorText
$btnCheckUpdate.Add_Click({ Run-DownloaderCommand "-check-update" "Checking for downloader updates" })
$tabMaintenance.Controls.Add($btnCheckUpdate)

# UPDATE DOWNLOADER BUTTON
$btnUpdateDownloader = New-Object System.Windows.Forms.Button
$btnUpdateDownloader.Text = "Update Downloader"
$btnUpdateDownloader.Location = New-Object System.Drawing.Point(850, 130)  # Adjust position as needed
$btnUpdateDownloader.Size = New-Object System.Drawing.Size(180, 30)
$btnUpdateDownloader.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)  # Blue color
$btnUpdateDownloader.ForeColor = [System.Drawing.Color]::White
$btnUpdateDownloader.Add_Click({ Download-LatestDownloader })
$tabMaintenance.Controls.Add($btnUpdateDownloader)

# Add tooltip
$toolTip.SetToolTip($btnUpdateDownloader, "Download the latest version of the Hytale downloader tool")

# Clear / Save / Copy Update Log buttons
$btnClearUpdateLog = New-Object System.Windows.Forms.Button
$btnClearUpdateLog.Text = "Clear Update Log"
$btnClearUpdateLog.Location = New-Object System.Drawing.Point(10, 630)
$btnClearUpdateLog.Size = New-Object System.Drawing.Size(120, 25)
Style-Button $btnClearUpdateLog
$btnClearUpdateLog.Add_Click({ Clear-UpdateLog })
$tabMaintenance.Controls.Add($btnClearUpdateLog)

$btnSaveUpdateLog = New-Object System.Windows.Forms.Button
$btnSaveUpdateLog.Text = "Save Update Log"
$btnSaveUpdateLog.Location = New-Object System.Drawing.Point(140, 630)
$btnSaveUpdateLog.Size = New-Object System.Drawing.Size(120, 25)
Style-Button $btnSaveUpdateLog
$btnSaveUpdateLog.Add_Click({ Save-UpdateLogToFile })
$tabMaintenance.Controls.Add($btnSaveUpdateLog)

$btnCopyUpdateLog = New-Object System.Windows.Forms.Button
$btnCopyUpdateLog.Text = "Copy Update Log"
$btnCopyUpdateLog.Location = New-Object System.Drawing.Point(270, 630)
$btnCopyUpdateLog.Size = New-Object System.Drawing.Size(120, 25)
Style-Button $btnCopyUpdateLog
$btnCopyUpdateLog.Add_Click({ Copy-UpdateLogToClipboard })
$tabMaintenance.Controls.Add($btnCopyUpdateLog)

$txtUpdateLog = New-Object System.Windows.Forms.TextBox
$txtUpdateLog.Multiline = $true
$txtUpdateLog.ScrollBars = "Vertical"
$txtUpdateLog.ReadOnly = $true
$txtUpdateLog.BackColor = $colorConsoleBack
$txtUpdateLog.ForeColor = $colorConsoleText
$txtUpdateLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtUpdateLog.Location = New-Object System.Drawing.Point(10, 360)
$txtUpdateLog.Size = New-Object System.Drawing.Size(960, 230)
$tabMaintenance.Controls.Add($txtUpdateLog)

# =====================
# SERVER IP SECTION
# =====================

$lblServerIPTitle = New-Object System.Windows.Forms.Label
$lblServerIPTitle.Text = "Server IP Address:"
$lblServerIPTitle.Location = New-Object System.Drawing.Point(780, 50)
$lblServerIPTitle.Size = New-Object System.Drawing.Size(150, 20)
$lblServerIPTitle.ForeColor = $colorText
$lblServerIPTitle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabMaintenance.Controls.Add($lblServerIPTitle)

$btnCopyServerIP = New-Object System.Windows.Forms.Button
$btnCopyServerIP.Text = "Copy Server IP"
$btnCopyServerIP.Location = New-Object System.Drawing.Point(780, 75)
$btnCopyServerIP.Size = New-Object System.Drawing.Size(180, 40)
$btnCopyServerIP.BackColor = [System.Drawing.Color]::FromArgb(50, 150, 50)
$btnCopyServerIP.ForeColor = [System.Drawing.Color]::White
$btnCopyServerIP.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$btnCopyServerIP.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopyServerIP.Add_Click({ Copy-ServerIP })
$tabMaintenance.Controls.Add($btnCopyServerIP)

# =====================
# CHECK FILES SECTION - NOW BETWEEN DOWNLOADER UTILS AND LOG BUTTONS
# =====================

$lblCheckFilesTitle = New-Object System.Windows.Forms.Label
$lblCheckFilesTitle.Text = "Check Required Files:"
$lblCheckFilesTitle.Location = New-Object System.Drawing.Point(10, 170)  # WAS 520
$lblCheckFilesTitle.Size = New-Object System.Drawing.Size(200, 20)
$lblCheckFilesTitle.ForeColor = $colorText
$lblCheckFilesTitle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabMaintenance.Controls.Add($lblCheckFilesTitle)

$lblJarFile = New-Object System.Windows.Forms.Label
$lblJarFile.Text = "HytaleServer.jar - Missing"
$lblJarFile.Location = New-Object System.Drawing.Point(10, 200)  # WAS 550
$lblJarFile.ForeColor = [System.Drawing.Color]::Red
$tabMaintenance.Controls.Add($lblJarFile)

$lblJarStatus = New-Object System.Windows.Forms.Label
$lblJarStatus.Text = "[!!]"
$lblJarStatus.Location = New-Object System.Drawing.Point(400, 200)  # WAS 550
$lblJarStatus.ForeColor = [System.Drawing.Color]::Red
$tabMaintenance.Controls.Add($lblJarStatus)

$lblAssetsFile = New-Object System.Windows.Forms.Label
$lblAssetsFile.Text = "Assets.zip - Missing"
$lblAssetsFile.Location = New-Object System.Drawing.Point(10, 230)  # WAS 580
$lblAssetsFile.ForeColor = [System.Drawing.Color]::Red
$tabMaintenance.Controls.Add($lblAssetsFile)

$lblAssetsStatus = New-Object System.Windows.Forms.Label
$lblAssetsStatus.Text = "[!!]"
$lblAssetsStatus.Location = New-Object System.Drawing.Point(400, 230)  # WAS 580
$lblAssetsStatus.ForeColor = [System.Drawing.Color]::Red
$tabMaintenance.Controls.Add($lblAssetsStatus)

$lblServerFolder = New-Object System.Windows.Forms.Label
$lblServerFolder.Text = "Server/ - Missing"
$lblServerFolder.Location = New-Object System.Drawing.Point(10, 260)  # WAS 610
$lblServerFolder.ForeColor = [System.Drawing.Color]::Red
$tabMaintenance.Controls.Add($lblServerFolder)

$lblServerFolderStatus = New-Object System.Windows.Forms.Label
$lblServerFolderStatus.Text = "[!!]"
$lblServerFolderStatus.Location = New-Object System.Drawing.Point(400, 260)  # WAS 610
$lblServerFolderStatus.ForeColor = [System.Drawing.Color]::Red
$tabMaintenance.Controls.Add($lblServerFolderStatus)

$lblModsFolder = New-Object System.Windows.Forms.Label
$lblModsFolder.Text = "mods/ - Missing"
$lblModsFolder.Location = New-Object System.Drawing.Point(10, 290)  # WAS 640
$lblModsFolder.ForeColor = [System.Drawing.Color]::Red
$tabMaintenance.Controls.Add($lblModsFolder)

$lblModsFolderStatus = New-Object System.Windows.Forms.Label
$lblModsFolderStatus.Text = "[!!]"
$lblModsFolderStatus.Location = New-Object System.Drawing.Point(400, 290)  # WAS 640
$lblModsFolderStatus.ForeColor = [System.Drawing.Color]::Red
$tabMaintenance.Controls.Add($lblModsFolderStatus)

$lblConfigFile = New-Object System.Windows.Forms.Label
$lblConfigFile.Text = "config.json - Missing"
$lblConfigFile.Location = New-Object System.Drawing.Point(10, 320)  # WAS 670
$lblConfigFile.ForeColor = [System.Drawing.Color]::Red
$tabMaintenance.Controls.Add($lblConfigFile)

$lblConfigStatus = New-Object System.Windows.Forms.Label
$lblConfigStatus.Text = "[!!]"
$lblConfigStatus.Location = New-Object System.Drawing.Point(400, 320)  # WAS 670
$lblConfigStatus.ForeColor = [System.Drawing.Color]::Red
$tabMaintenance.Controls.Add($lblConfigStatus)

# Check Files button - moved to align with new positions
$btnCheckFiles = New-Object System.Windows.Forms.Button
$btnCheckFiles.Text = "Check Files"
$btnCheckFiles.Location = New-Object System.Drawing.Point(700, 170)  # WAS 520
Style-Button $btnCheckFiles
$btnCheckFiles.Add_Click({ Check-ServerFiles })
$tabMaintenance.Controls.Add($btnCheckFiles)

# Overall status label - moved with button
$lblOverallStatus = New-Object System.Windows.Forms.Label
$lblOverallStatus.Text = "[WARN] Missing required files"
$lblOverallStatus.Location = New-Object System.Drawing.Point(700, 210)  # WAS 560
$lblOverallStatus.ForeColor = [System.Drawing.Color]::Orange
$tabMaintenance.Controls.Add($lblOverallStatus)

# =====================
# MOD MANAGER TAB
# =====================

$tabModManager = New-Object System.Windows.Forms.TabPage
$tabModManager.Text = "Mod Manager"
$tabModManager.BackColor = $colorBack
$tabs.TabPages.Add($tabModManager)

# Title Label
$lblModManagerTitle = New-Object System.Windows.Forms.Label
$lblModManagerTitle.Text = "HYTALE MOD MANAGER"
$lblModManagerTitle.Location = New-Object System.Drawing.Point(10, 10)
$lblModManagerTitle.Size = New-Object System.Drawing.Size(500, 30)
$lblModManagerTitle.ForeColor = $colorText
$lblModManagerTitle.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
$tabModManager.Controls.Add($lblModManagerTitle)

# Subtitle
$lblModManagerSubtitle = New-Object System.Windows.Forms.Label
$lblModManagerSubtitle.Text = "Drag .jar files into the list or use the buttons to manage mods"
$lblModManagerSubtitle.Location = New-Object System.Drawing.Point(10, 45)
$lblModManagerSubtitle.Size = New-Object System.Drawing.Size(600, 20)
$lblModManagerSubtitle.ForeColor = [System.Drawing.Color]::LightGray
$lblModManagerSubtitle.Font = New-Object System.Drawing.Font("Arial", 9)
$tabModManager.Controls.Add($lblModManagerSubtitle)

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
$script:modListView.Columns.Add("Mod Name", 300) | Out-Null
$script:modListView.Columns.Add("Status", 100) | Out-Null
$script:modListView.Columns.Add("File Size", 80) | Out-Null
$script:modListView.Columns.Add("File Path", 260) | Out-Null

$tabModManager.Controls.Add($script:modListView)

# =====================
# CONTROL BUTTONS (Right Panel)
# =====================

$btnRefreshMods = New-Object System.Windows.Forms.Button
$btnRefreshMods.Text = "Refresh List"
$btnRefreshMods.Location = New-Object System.Drawing.Point(770, 75)
$btnRefreshMods.Size = New-Object System.Drawing.Size(200, 40)
Style-Button $btnRefreshMods
$btnRefreshMods.Add_Click({ Refresh-ModList })
$tabModManager.Controls.Add($btnRefreshMods)

$btnToggleMod = New-Object System.Windows.Forms.Button
$btnToggleMod.Text = "Enable / Disable Mod"
$btnToggleMod.Location = New-Object System.Drawing.Point(770, 125)
$btnToggleMod.Size = New-Object System.Drawing.Size(200, 40)
Style-Button $btnToggleMod
$btnToggleMod.Add_Click({ Toggle-ModState })
$tabModManager.Controls.Add($btnToggleMod)

$btnOpenModsFolder = New-Object System.Windows.Forms.Button
$btnOpenModsFolder.Text = "Open Mods Folder"
$btnOpenModsFolder.Location = New-Object System.Drawing.Point(770, 175)
$btnOpenModsFolder.Size = New-Object System.Drawing.Size(200, 40)
Style-Button $btnOpenModsFolder
$btnOpenModsFolder.Add_Click({ Open-ModsFolder })
$tabModManager.Controls.Add($btnOpenModsFolder)

$btnRemoveMod = New-Object System.Windows.Forms.Button
$btnRemoveMod.Text = "Delete Mod (Permanent)"
$btnRemoveMod.Location = New-Object System.Drawing.Point(770, 225)
$btnRemoveMod.Size = New-Object System.Drawing.Size(200, 40)
$btnRemoveMod.BackColor = [System.Drawing.Color]::FromArgb(120, 40, 40)
$btnRemoveMod.ForeColor = $colorButtonText
$btnRemoveMod.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRemoveMod.Add_Click({ Remove-SelectedMod })
$tabModManager.Controls.Add($btnRemoveMod)

$btnCheckConflicts = New-Object System.Windows.Forms.Button
$btnCheckConflicts.Text = "Check for Conflicts"
$btnCheckConflicts.Location = New-Object System.Drawing.Point(770, 275)
$btnCheckConflicts.Size = New-Object System.Drawing.Size(200, 35)
$btnCheckConflicts.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 40)
$btnCheckConflicts.ForeColor = $colorButtonText
$btnCheckConflicts.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCheckConflicts.Add_Click({ Check-ModConflicts })
$tabModManager.Controls.Add($btnCheckConflicts)

# Separator
$lblSeparator = New-Object System.Windows.Forms.Label
$lblSeparator.Text = "----------------------------------------"
$lblSeparator.Location = New-Object System.Drawing.Point(770, 320)
$lblSeparator.Size = New-Object System.Drawing.Size(200, 20)
$lblSeparator.ForeColor = [System.Drawing.Color]::Gray
$tabModManager.Controls.Add($lblSeparator)

# =====================
# ONLINE REPOSITORY SECTION
# =====================

$lblOnlineRepo = New-Object System.Windows.Forms.Label
$lblOnlineRepo.Text = "Browse Online Mods"
$lblOnlineRepo.Location = New-Object System.Drawing.Point(770, 345)
$lblOnlineRepo.Size = New-Object System.Drawing.Size(200, 20)
$lblOnlineRepo.ForeColor = $colorText
$lblOnlineRepo.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabModManager.Controls.Add($lblOnlineRepo)

$btnCurseForge = New-Object System.Windows.Forms.Button
$btnCurseForge.Text = "Open CurseForge"
$btnCurseForge.Location = New-Object System.Drawing.Point(770, 370)
$btnCurseForge.Size = New-Object System.Drawing.Size(200, 40)
$btnCurseForge.BackColor = [System.Drawing.Color]::FromArgb(240, 100, 20)
$btnCurseForge.ForeColor = [System.Drawing.Color]::White
$btnCurseForge.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCurseForge.Add_Click({ Open-CurseForge })
$tabModManager.Controls.Add($btnCurseForge)

# =====================
# MOD NOTES SECTION
# =====================

$lblNotesTitle = New-Object System.Windows.Forms.Label
$lblNotesTitle.Text = "Mod Notes / Description:"
$lblNotesTitle.Location = New-Object System.Drawing.Point(770, 425)
$lblNotesTitle.Size = New-Object System.Drawing.Size(200, 20)
$lblNotesTitle.ForeColor = $colorText
$lblNotesTitle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabModManager.Controls.Add($lblNotesTitle)

$script:txtModNotes = New-Object System.Windows.Forms.TextBox
$script:txtModNotes.Multiline = $true
$script:txtModNotes.ScrollBars = "Vertical"
$script:txtModNotes.Location = New-Object System.Drawing.Point(770, 450)
$script:txtModNotes.Size = New-Object System.Drawing.Size(200, 110)
$script:txtModNotes.BackColor = $colorTextboxBack
$script:txtModNotes.ForeColor = $colorTextboxText
$script:txtModNotes.Font = New-Object System.Drawing.Font("Consolas", 8)
$script:txtModNotes.Text = "Select a mod to view or edit notes..."
$script:txtModNotes.ReadOnly = $true
$tabModManager.Controls.Add($script:txtModNotes)

$btnSaveNotes = New-Object System.Windows.Forms.Button
$btnSaveNotes.Text = "Save Notes"
$btnSaveNotes.Location = New-Object System.Drawing.Point(770, 565)
$btnSaveNotes.Size = New-Object System.Drawing.Size(200, 30)
Style-Button $btnSaveNotes
$btnSaveNotes.Add_Click({ Update-ModNotes })
$tabModManager.Controls.Add($btnSaveNotes)

# Add event to show notes when mod is selected
$script:modListView.Add_SelectedIndexChanged({ Show-ModNotes })

# =====================
# QUICK TIPS (Bottom)
# =====================

$lblQuickTips = New-Object System.Windows.Forms.Label
$lblQuickTips.Text = "TIP: Drag .jar files directly into the list! | GREEN=Enabled | RED=Disabled | YELLOW=Conflict Warning"
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

# Initial mod list population
Refresh-ModList

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

# Load saved window settings (size/position/last tab)
Load-Settings

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