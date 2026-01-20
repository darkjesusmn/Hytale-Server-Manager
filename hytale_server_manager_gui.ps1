# ==========================================================================================
# Hytale Server Manager GUI - Version 2.1
# ==========================================================================================
# Made with AI  
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

    # Check if process actually exists
    if (-not $script:serverProcess -or $script:serverProcess.HasExited) {
        $txtConsole.AppendText("[WARN] Server process not found - attempting restart...`r`n")
        Restart-Server
        return
    }

    try {
        # Step 1: Send ping command
        $script:serverProcess.StandardInput.WriteLine("ping")
        
        # Step 2: Wait briefly for response (ping is usually instant)
        Start-Sleep -Milliseconds 500
        
        # Step 3: Check if we got a response by looking at recent console output
        $recentOutput = $txtConsole.Text.Split("`n") | Select-Object -Last 10
        $pingFound = $false
        
        foreach ($line in $recentOutput) {
            # Treat standard ping responses OR "player required" message as success
            if ($line -match "pong|ping|latency|\d+ms" -or $line -match "Sender must be a player or provide the --player option!") {
                $pingFound = $true
                break
            }
        }
        
        if ($pingFound) {
            # Server responded - reset failure counter
            if ($script:pingFailCount -gt 0) {
                $txtConsole.AppendText("[INFO] Server ping restored`r`n")
            }
            $script:pingFailCount = 0
        } else {
            # No response - increment failure counter
            $script:pingFailCount++
            $txtConsole.AppendText("[WARN] Server ping attempt $($script:pingFailCount)/5 failed`r`n")
            
            # After 5 failures, restart server
            if ($script:pingFailCount -ge 5) {
                $txtConsole.AppendText("[ERROR] Server not responding - initiating auto-restart...`r`n")
                $script:pingFailCount = 0
                Restart-Server
            }
        }
    } catch {
        $txtConsole.AppendText("[ERROR] Health monitor error: $_`r`n")
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
        $error = $process.StandardError.ReadToEnd()

        # Step 5: Wait for process to finish
        $process.WaitForExit()

        # Step 6: Append stdout and stderr to Update Log
        if ($output) { $txtUpdateLog.AppendText($output + "`r`n") }
        if ($error) { $txtUpdateLog.AppendText("[ERROR] $error`r`n") }

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
# Provides a simple mechanism to restart the Hytale server by stopping it and then starting it again.
# Useful for applying new configuration changes, clearing memory, or recovering from an error state.
#
# OPERATION FLOW:
# Step 1: Stop the server gracefully using Stop-Server (cleans up process, timers, and events)
# Step 2: Wait for 5 seconds to allow resources to fully release and prevent startup conflicts
# Step 3: Start the server using Start-Server (launches Java process, sets up events, starts timers)
#
# PARAMETERS: None
#
# RETURN: None
# =====================
function Restart-Server {
    # Step 1: Stop server
    Stop-Server

    # Step 2: Wait briefly to ensure shutdown completes
    Start-Sleep 5

    # Step 3: Start server
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
        $error = $updateProcess.StandardError.ReadToEnd()
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
    if ($lblStatus.Text -match "Stopped") {
        # Start button enabled — normal dark theme
        $btnStart.Enabled = $true
        $btnStart.BackColor = $colorButtonBack
        $btnStart.ForeColor = $colorButtonText
        $btnStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    }
    elseif ($lblStatus.Text -match "Running") {
        # Start button disabled — fully blacked out
        $btnStart.Enabled = $false
        $btnStart.BackColor = [System.Drawing.Color]::Black       # completely black background
        $btnStart.ForeColor = [System.Drawing.Color]::DarkGray   # very dim text
        $btnStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnStart.FlatAppearance.BorderColor = [System.Drawing.Color]::Black
    }
}

# =====================
# GUI COMPONENTS
# =====================

$form = New-Object System.Windows.Forms.Form
$form.Text = "Hytale Server Manager"
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object System.Drawing.Size(1200, 650)
$form.MinimumSize = New-Object System.Drawing.Size(1200, 650)
$form.BackColor = $colorBack
$form.AutoScaleMode = "None"
$form.MaximizeBox = $false

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$form.Controls.Add($tabs)

# =====================
# SERVER CONTROL TAB
# =====================

$tabServer = New-Object System.Windows.Forms.TabPage
$tabServer.Text = "Control"
$tabServer.BackColor = $colorBack
$tabServer.AutoScroll = $true
$tabs.TabPages.Add($tabServer)

# =====================
# LAYOUT PANELS
# =====================

# Top panel: Server buttons, RAM sliders, console buttons
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Location = New-Object System.Drawing.Point(10, 10)
$panelTop.Size = New-Object System.Drawing.Size(1150, 100)
$panelTop.BackColor = $colorBack
$tabServer.Controls.Add($panelTop)

# Status panel: Server info (Status/CPU/RAM) + Session info (Uptime/Players)
$panelStatus = New-Object System.Windows.Forms.Panel
$panelStatus.Location = New-Object System.Drawing.Point(10, 120)
$panelStatus.Size = New-Object System.Drawing.Size(1150, 80)  # enough height for all labels
$panelStatus.BackColor = $colorBack
$tabServer.Controls.Add($panelStatus)

# =====================
# SERVER CONTROL BUTTONS
# =====================

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Server"
$btnStart.Size = New-Object System.Drawing.Size(100, 30)
$btnStart.Location = New-Object System.Drawing.Point(0, 20)
Style-Button $btnStart
$btnStart.Add_Click({ Start-Server })
$panelTop.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop Server"
$btnStop.Size = New-Object System.Drawing.Size(100, 30)
$btnStop.Location = New-Object System.Drawing.Point(110, 20)
Style-Button $btnStop
$btnStop.Add_Click({ Stop-Server })
$panelTop.Controls.Add($btnStop)

$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = "Restart Server"
$btnRestart.Size = New-Object System.Drawing.Size(100, 30)
$btnRestart.Location = New-Object System.Drawing.Point(220, 20)
Style-Button $btnRestart
$btnRestart.Add_Click({ Restart-Server })
$panelTop.Controls.Add($btnRestart)

# =====================
# RAM CONTROLS
# =====================

$lblMinRam = New-Object System.Windows.Forms.Label
$lblMinRam.Text = "Min RAM (GB): 4"
$lblMinRam.ForeColor = $colorText
$lblMinRam.AutoSize = $true
$lblMinRam.Location = New-Object System.Drawing.Point(380, 5)
$panelTop.Controls.Add($lblMinRam)

$trkMinRam = New-Object System.Windows.Forms.TrackBar
$trkMinRam.Minimum = 4
$trkMinRam.Maximum = 16
$trkMinRam.Value = 4
$trkMinRam.Size = New-Object System.Drawing.Size(140, 45)
$trkMinRam.Location = New-Object System.Drawing.Point(380, 25)
$trkMinRam.TickStyle = [System.Windows.Forms.TickStyle]::BottomRight
$trkMinRam.Add_Scroll({
    $lblMinRam.Text = "Min RAM (GB): $($trkMinRam.Value)"
})
$panelTop.Controls.Add($trkMinRam)

$lblMaxRam = New-Object System.Windows.Forms.Label
$lblMaxRam.Text = "Max RAM (GB): 16"
$lblMaxRam.ForeColor = $colorText
$lblMaxRam.AutoSize = $true
$lblMaxRam.Location = New-Object System.Drawing.Point(600, 5)
$panelTop.Controls.Add($lblMaxRam)

$trkMaxRam = New-Object System.Windows.Forms.TrackBar
$trkMaxRam.Minimum = 8
$trkMaxRam.Maximum = 32
$trkMaxRam.Value = 16
$trkMaxRam.Size = New-Object System.Drawing.Size(140, 45)
$trkMaxRam.Location = New-Object System.Drawing.Point(600, 25)
$trkMaxRam.TickStyle = [System.Windows.Forms.TickStyle]::BottomRight
$trkMaxRam.Add_Scroll({
    $lblMaxRam.Text = "Max RAM (GB): $($trkMaxRam.Value)"
})
$panelTop.Controls.Add($trkMaxRam)

# =====================
# CONSOLE MANAGEMENT BUTTONS (TOP RIGHT)
# =====================

$btnClearConsole = New-Object System.Windows.Forms.Button
$btnClearConsole.Text = "Clear Console"
$btnClearConsole.Size = New-Object System.Drawing.Size(100, 30)
$btnClearConsole.Location = New-Object System.Drawing.Point(820, 20)
Style-Button $btnClearConsole
$btnClearConsole.Add_Click({ Clear-Console })
$panelTop.Controls.Add($btnClearConsole)

$btnSaveConsole = New-Object System.Windows.Forms.Button
$btnSaveConsole.Text = "Save Console"
$btnSaveConsole.Size = New-Object System.Drawing.Size(100, 30)
$btnSaveConsole.Location = New-Object System.Drawing.Point(930, 20)
Style-Button $btnSaveConsole
$btnSaveConsole.Add_Click({ Save-ConsoleToFile })
$panelTop.Controls.Add($btnSaveConsole)

$btnCopyConsole = New-Object System.Windows.Forms.Button
$btnCopyConsole.Text = "Copy Console"
$btnCopyConsole.Size = New-Object System.Drawing.Size(100, 30)
$btnCopyConsole.Location = New-Object System.Drawing.Point(1040, 20)
Style-Button $btnCopyConsole
$btnCopyConsole.Add_Click({ Copy-ConsoleToClipboard })
$panelTop.Controls.Add($btnCopyConsole)

# =====================
# STATUS LABELS (GROUPED SERVER INFO + SESSION INFO)
# =====================

# Server info (grouped vertically, left side)
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Stopped"
$lblStatus.ForeColor = [System.Drawing.Color]::Red
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(10, 7)
$panelStatus.Controls.Add($lblStatus)

Update-StartButtonState

$lblCPU = New-Object System.Windows.Forms.Label
$lblCPU.Text = "CPU Usage: 0%"
$lblCPU.ForeColor = $colorText
$lblCPU.AutoSize = $true
$lblCPU.Location = New-Object System.Drawing.Point(10, 30)
$panelStatus.Controls.Add($lblCPU)

$lblRAM = New-Object System.Windows.Forms.Label
$lblRAM.Text = "RAM Usage: 0 MB"
$lblRAM.ForeColor = $colorText
$lblRAM.AutoSize = $true
$lblRAM.Location = New-Object System.Drawing.Point(10, 53)
$panelStatus.Controls.Add($lblRAM)

# Session info (center/right)
$lblUptime = New-Object System.Windows.Forms.Label
$lblUptime.Text = "Uptime: N/A"
$lblUptime.ForeColor = $colorText
$lblUptime.AutoSize = $true
$lblUptime.Location = New-Object System.Drawing.Point(450, 20)
$panelStatus.Controls.Add($lblUptime)

$lblServerPing = New-Object System.Windows.Forms.Label
$lblServerPing.Text = "Players Online: 0"
$lblServerPing.ForeColor = [System.Drawing.Color]::Gray
$lblServerPing.AutoSize = $true
$lblServerPing.Location = New-Object System.Drawing.Point(600, 20)
$panelStatus.Controls.Add($lblServerPing)

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
$txtConsole.Location = New-Object System.Drawing.Point(10, 210)  # moved down slightly to fit status panel
$txtConsole.Size = New-Object System.Drawing.Size(1150, 360)
$tabServer.Controls.Add($txtConsole)

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
$txtConfigEditor.AcceptsTab = $true           # Tabs work for indentation
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
# COMMAND TAB WITH BUTTONS (FLOW LAYOUT)
# =====================
$tabCommand = New-Object System.Windows.Forms.TabPage
$tabCommand.Text = "Console"
$tabCommand.BackColor = $colorBack
$tabs.TabPages.Add($tabCommand)

# Console log at top
$txtCommandConsole = New-Object System.Windows.Forms.TextBox
$txtCommandConsole.Multiline = $true
$txtCommandConsole.ScrollBars = "Vertical"
$txtCommandConsole.ReadOnly = $true
$txtCommandConsole.BackColor = $colorConsoleBack
$txtCommandConsole.ForeColor = $colorConsoleText
$txtCommandConsole.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtCommandConsole.Location = New-Object System.Drawing.Point(10, 10)
$txtCommandConsole.Size = New-Object System.Drawing.Size(1160, 300)
$tabCommand.Controls.Add($txtCommandConsole)

# Command input
$txtCommandInput = New-Object System.Windows.Forms.TextBox
$txtCommandInput.Location = New-Object System.Drawing.Point(10, 320)
$txtCommandInput.Size = New-Object System.Drawing.Size(1030, 25)
$tabCommand.Controls.Add($txtCommandInput)

# Send button
$btnSendCommand = New-Object System.Windows.Forms.Button
$btnSendCommand.Text = "Send"
$btnSendCommand.Location = New-Object System.Drawing.Point(1050, 320)
$btnSendCommand.Size = New-Object System.Drawing.Size(120, 25)
Style-Button $btnSendCommand
$btnSendCommand.Add_Click({
    $cmdText = $txtCommandInput.Text.Trim()
    if ($cmdText) {
        Send-ServerCommand $cmdText
        Add-ToCommandHistory $cmdText
    }
    $txtCommandInput.Text = ""
})
$tabCommand.Controls.Add($btnSendCommand)

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

# Tooltip object
$toolTip = New-Object System.Windows.Forms.ToolTip

# =====================
# ADMIN COMMANDS SECTION
# =====================
$lblAdminCommands = New-Object System.Windows.Forms.Label
$lblAdminCommands.Text = "Admin Commands:"
$lblAdminCommands.Location = New-Object System.Drawing.Point(10, 360)
$lblAdminCommands.Size = New-Object System.Drawing.Size(200, 20)
$lblAdminCommands.ForeColor = $colorText
$lblAdminCommands.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$tabCommand.Controls.Add($lblAdminCommands)

# FlowLayoutPanel for Admin Commands - ALPHABETICAL
$flowAdminButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$flowAdminButtons.Location = New-Object System.Drawing.Point(10, 385)
$flowAdminButtons.Size = New-Object System.Drawing.Size(1160, 100)
$flowAdminButtons.AutoScroll = $false
$tabCommand.Controls.Add($flowAdminButtons)

# Admin Commands - ALPHABETICALLY SORTED
$adminCommands = [ordered]@{
    "/backup"    = "Backs the server up right now"
    "/ban"       = "Ban a player from the server."
    "/gamemode"  = "Change a player's gamemode."
    "/give"      = "Spawn items for a player in-game."
    "/heal"      = "Heals up to max health and stamina."
    "/kick"      = "Kicks a player from the server."
    "/op"        = "Gives admin permissions to a player."
    "/perm"      = "Permissions command for groups or users."
    "/ping"      = "Check server latency."
    "/plugin"    = "Manage plugins."
    "/spawning"  = "Commands related to NPC spawning."
    "/stop"      = "Shut down the server."
    "/sudo"      = "Run a command as another player."
    "/tp"        = "Teleport to location or player."
    "/unban"     = "Unban a player from the server."
    "/whitelist" = "Manage server whitelist."
}

foreach ($cmd in $adminCommands.Keys) {
    $cmdCopy = $cmd
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $cmdCopy
    $btn.Size = New-Object System.Drawing.Size(90, 28)
    $btn.Tag = $cmdCopy
    Style-Button $btn
    $btn.Add_Click({
        $txtCommandInput.Text = $this.tag + " "
        $txtCommandInput.Focus()
        $txtCommandInput.SelectionStart = $txtCommandInput.Text.Length
    })
    $toolTip.SetToolTip($btn, $adminCommands[$cmdCopy])
    $flowAdminButtons.Controls.Add($btn)
}

# =====================
# WORLD COMMANDS SECTION
# =====================
$lblWorldCommands = New-Object System.Windows.Forms.Label
$lblWorldCommands.Text = "World Commands:"
$lblWorldCommands.Location = New-Object System.Drawing.Point(10, 495)
$lblWorldCommands.Size = New-Object System.Drawing.Size(200, 20)
$lblWorldCommands.ForeColor = $colorText
$lblWorldCommands.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$tabCommand.Controls.Add($lblWorldCommands)

# FlowLayoutPanel for World Commands - ALPHABETICAL
$flowWorldButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$flowWorldButtons.Location = New-Object System.Drawing.Point(10, 520)
$flowWorldButtons.Size = New-Object System.Drawing.Size(1160, 100)
$flowWorldButtons.AutoScroll = $false
$tabCommand.Controls.Add($flowWorldButtons)

# World Commands - ALPHABETICALLY SORTED
$worldCommands = [ordered]@{
    "/block"    = "Blockstates, debugging, etc."
    "/chunk"    = "Chunk info and loading."
    "/fluid"    = "Control fluids at location or radius."
    "/lighting" = "Control and check world lighting."
    "/path"     = "Manage NPC patrol paths."
    "/time"     = "Change the world time in-game."
    "/weather"  = "Change the world weather."
    "/world"    = "Manage worlds in the server."
}

foreach ($cmd in $worldCommands.Keys) {
    $cmdCopy = $cmd
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $cmdCopy
    $btn.Size = New-Object System.Drawing.Size(90, 28)
    $btn.Tag = $cmdCopy
    Style-Button $btn
    $btn.Add_Click({ 
        $txtCommandInput.Text = $this.tag + " "
        $txtCommandInput.Focus()
        $txtCommandInput.SelectionStart = $txtCommandInput.Text.Length
    })
    $toolTip.SetToolTip($btn, $worldCommands[$cmdCopy])
    $flowWorldButtons.Controls.Add($btn)
}

# =====================
# RUN GUI SETUP
# =====================

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

# Load saved window settings (size/position/last tab)
Load-Settings

# Minimize-to-tray behavior: hide window when minimized
$form.Add_Resize({
    try {
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $form.Hide()
            if ($script:notifyIcon) {
                $script:notifyIcon.ShowBalloonTip(1000, "Hytale Server Manager", "Application minimized to tray.", [System.Windows.Forms.ToolTipIcon]::Info)
            }
        }
    } catch {}
})

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
