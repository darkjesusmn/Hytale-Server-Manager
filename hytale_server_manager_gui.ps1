# =====================
# IMPORT REQUIRED .NET ASSEMBLIES
# =====================
# Hide the PowerShell console window

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

# Constants: 0 = hide, 5 = show
$consolePtr = [Win32]::GetConsoleWindow()
[Win32]::ShowWindow($consolePtr, 0)  # 0 = hide

# Add System.Windows.Forms to allow creation of GUI elements like forms, buttons, labels, textboxes, etc.
Add-Type -AssemblyName System.Windows.Forms

# Add System.Drawing to allow colors, fonts, and other graphical manipulations for the GUI
Add-Type -AssemblyName System.Drawing

# =====================
# GLOBAL VARIABLES
# =====================

# Stores the Process object of the running server so we can stop or monitor it
$script:serverProcess = $null

# Tracks whether the server is currently running
$script:serverRunning = $false

# Path to the Hytale server JAR file relative to the script
$script:jarPath        = Join-Path $PSScriptRoot "HytaleServer.jar"

# Path to the configuration file for the server
$script:configPath     = Join-Path $PSScriptRoot "config.json"

# Path to the main server log file
$script:logFilePath    = Join-Path $PSScriptRoot "logs\latest.log"

# Timer object used for polling the log file and monitoring CPU/RAM usage
$script:logTimer = $null

# Keeps track of the last read size of the log file so we only read new lines
$script:lastLogSize = 0

# Minimum RAM (in GB) allocated to the server
$script:minRamGB = 4

# Maximum RAM (in GB) allocated to the server
$script:maxRamGB = 8

# =====================
# DARK MODE COLORS
# =====================

# Background color of the main GUI
$colorBack = [System.Drawing.Color]::FromArgb(30,30,30)

# Default text color for labels and other text
$colorText = [System.Drawing.Color]::White

# Background color for textboxes
$colorTextboxBack = [System.Drawing.Color]::FromArgb(50,50,50)

# Text color inside textboxes
$colorTextboxText = [System.Drawing.Color]::White

# Background color for buttons
$colorButtonBack = [System.Drawing.Color]::FromArgb(70,70,70)

# Text color for buttons
$colorButtonText = [System.Drawing.Color]::White

# Background color for the server console textbox
$colorConsoleBack = [System.Drawing.Color]::Black

# Text color for the server console output
$colorConsoleText = [System.Drawing.Color]::LightGreen

# =====================
# FUNCTIONS
# =====================

function Check-ServerFiles {

    # Directory containing the script (and server files)
    $serverDir = $PSScriptRoot

    # Flag to track if all files exist
    $allValid = $true

    # Array of required files and directories with associated labels
    $items = @(
        @{Path="HytaleServer.jar"; Status=$lblJarStatus; Label=$lblJarFile; Type="File"; Name="HytaleServer.jar"},
        @{Path="Assets.zip"; Status=$lblAssetsStatus; Label=$lblAssetsFile; Type="File"; Name="Assets.zip"},
        @{Path="Server"; Status=$lblServerFolderStatus; Label=$lblServerFolder; Type="Directory"; Name="Server/"},
        @{Path="mods"; Status=$lblModsFolderStatus; Label=$lblModsFolder; Type="Directory"; Name="mods/"},
        @{Path="config.json"; Status=$lblConfigStatus; Label=$lblConfigFile; Type="File"; Name="config.json"}
    )

    # Loop through each required item
    foreach ($item in $items) {
        $fullPath = Join-Path $serverDir $item.Path

        # Check if the path exists
        $exists = if ($item.Type -eq "File") {
            Test-Path $fullPath
        } else {
            Test-Path $fullPath -PathType Container
        }

        # Update GUI labels based on existence
        if ($exists) {
            $item.Status.Text = "[OK]" # Status indicator
            $item.Status.ForeColor = [System.Drawing.Color]::LightGreen
            $item.Label.Text = "$($item.Name) - Found"
            $item.Label.ForeColor = [System.Drawing.Color]::LightGreen
        } else {
            $item.Status.Text = "[!!]" # Warning indicator
            $item.Status.ForeColor = [System.Drawing.Color]::Red
            $item.Label.Text = "$($item.Name) - Missing"
            $item.Label.ForeColor = [System.Drawing.Color]::Red
            $allValid = $false
        }
    }

    # Update overall status label and console output
    if ($allValid) {
        $lblOverallStatus.Text = "[OK] All required files present"
        $lblOverallStatus.ForeColor = [System.Drawing.Color]::LightGreen
        $txtConsole.AppendText("[INFO] All required files present`r`n")
    } else {
        $lblOverallStatus.Text = "[WARN] Missing required files"
        $lblOverallStatus.ForeColor = [System.Drawing.Color]::Orange
        $txtConsole.AppendText("[WARN] Missing required files`r`n")
    }
}

function Start-Server {
    if ($script:serverRunning) { return }

    if (-not (Test-Path $script:jarPath)) {
        [System.Windows.Forms.MessageBox]::Show("HytaleServer.jar missing","Error")
        return
    }

    # Ensure RAM values are valid integers
    $minRam = if ($script:minRamGB -and $script:minRamGB -gt 0) { $script:minRamGB } else { 4 }
    $maxRam = if ($script:maxRamGB -and $script:maxRamGB -gt 0) { $script:maxRamGB } else { 8 }

    # Ensure Min RAM <= Max RAM
    if ($minRam -gt $maxRam) {
        [System.Windows.Forms.MessageBox]::Show("Min RAM cannot exceed Max RAM","Error")
        return
    }

    $txtConsole.AppendText("[INFO] RAM: Min=${minRam}GB Max=${maxRam}GB`r`n")
    $txtConsole.AppendText("[INFO] Starting server...`r`n")

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "java"
    $psi.Arguments = "-Xms${minRam}G -Xmx${maxRam}G -jar `"$script:jarPath`" --assets Assets.zip --backup --backup-dir backup"
    $psi.WorkingDirectory = $PSScriptRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true  # Needed for sending commands
    $psi.CreateNoWindow = $true

    try {
        $script:serverProcess = New-Object System.Diagnostics.Process
        $script:serverProcess.StartInfo = $psi
        $script:serverProcess.EnableRaisingEvents = $true

        # Start the process
        $script:serverProcess.Start() | Out-Null
        $script:serverProcess.BeginOutputReadLine()
        $script:serverProcess.BeginErrorReadLine()

        # Subscribe to async output events for BOTH consoles
        Register-ObjectEvent -InputObject $script:serverProcess -EventName "OutputDataReceived" -Action {
            if ($Event.SourceEventArgs.Data) { 
                $txtConsole.AppendText("$($Event.SourceEventArgs.Data)`r`n")          # Control tab
                $txtCommandConsole.AppendText("$($Event.SourceEventArgs.Data)`r`n")   # Console tab
            }
        } | Out-Null

        Register-ObjectEvent -InputObject $script:serverProcess -EventName "ErrorDataReceived" -Action {
            if ($Event.SourceEventArgs.Data) { 
                $txtConsole.AppendText("[ERR] $($Event.SourceEventArgs.Data)`r`n")          # Control tab
                $txtCommandConsole.AppendText("[ERR] $($Event.SourceEventArgs.Data)`r`n")   # Console tab
            }
        } | Out-Null

        $script:serverRunning = $true
        $lblStatus.Text = "Status: Running"
        $lblStatus.ForeColor = [System.Drawing.Color]::LightGreen

        # Start existing log polling and CPU/RAM updater
        Start-LogPolling
        Update-CPUAndRAMUsage
    } catch {
        $txtConsole.AppendText("[ERROR] Failed to start server: $_`r`n")
        $lblStatus.Text = "Status: Error"
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
    }
}

function Stop-Server {
    if (-not $script:serverRunning) { return }
    try {
        if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
            $script:serverProcess.Kill()
            $script:serverProcess.WaitForExit()
        }
    } catch {}
    if ($script:logTimer) { $script:logTimer.Stop() }
    $script:serverRunning = $false
    $script:serverProcess = $null
    $lblStatus.Text = "Status: Stopped"
    $lblStatus.ForeColor = [System.Drawing.Color]::Red
    $txtConsole.AppendText("[INFO] Server stopped`r`n")
}

function Restart-Server {
    Stop-Server
    Start-Sleep 2
    Start-Server
}

function Update-CPUAndRAMUsage {
    if (-not $script:serverRunning) { return }
    try {
        $process = Get-Process -Id $script:serverProcess.Id
        $cpuUsage = [math]::Round($process.CPU, 1)
        $memoryUsageMB = [math]::Round($process.WorkingSet / 1MB, 2)
        $lblCPU.Text = "CPU Usage: ${cpuUsage}%"
        $lblRAM.Text = "RAM Usage: ${memoryUsageMB} MB"
    } catch {}
}

function Start-LogPolling {
    if ($script:logTimer) {
        $script:logTimer.Stop()
        $script:logTimer.Dispose()
    }
    $script:lastLogSize = 0
    $script:logTimer = New-Object System.Windows.Forms.Timer
    $script:logTimer.Interval = 500
    $script:logTimer.Add_Tick({
        if (-not (Test-Path $script:logFilePath)) { return }
        try {
            $info = Get-Item $script:logFilePath
            if ($info.Length -gt $script:lastLogSize) {
                $fs = [System.IO.File]::Open($script:logFilePath,'Open','Read','ReadWrite')
                $fs.Seek($script:lastLogSize, 'Begin') | Out-Null
                $sr = New-Object System.Windows.Forms.StreamReader($fs)
                while (-not $sr.EndOfStream) {
                    $txtConsole.AppendText($sr.ReadLine() + "`r`n")
                }
                $script:lastLogSize = $fs.Position
                $sr.Close()
                $fs.Close()
            }
        } catch {}
    })
    $script:logTimer.Start()
}

function Load-Config {
    if (-not (Test-Path $script:configPath)) { return }
    $txtConfigEditor.Text = Get-Content $script:configPath -Raw
}

function Save-Config {
    try {
        $txtConfigEditor.Text | ConvertFrom-Json # Validate JSON format
        Set-Content -Path $script:configPath -Value $txtConfigEditor.Text
        [System.Windows.Forms.MessageBox]::Show("Configuration saved successfully", "Success")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Invalid JSON format. Please check your configuration.", "Error")
    }
}

# =====================
# GUI COMPONENTS
# =====================

$form = New-Object System.Windows.Forms.Form
$form.Text = "Hytale Server Manager"
$form.Size = New-Object System.Drawing.Size(1000, 600)
$form.BackColor = $colorBack

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$form.Controls.Add($tabs)

# =====================
# SERVER CONTROL TAB
# =====================

$tabServer = New-Object System.Windows.Forms.TabPage
$tabServer.Text = "Control"
$tabServer.BackColor = $colorBack
$tabs.TabPages.Add($tabServer)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Server"
$btnStart.Location = New-Object System.Drawing.Point(10, 20)
$btnStart.Add_Click({ Start-Server })
$tabServer.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop Server"
$btnStop.Location = New-Object System.Drawing.Point(120, 20)
$btnStop.Add_Click({ Stop-Server })
$tabServer.Controls.Add($btnStop)

$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = "Restart Server"
$btnRestart.Location = New-Object System.Drawing.Point(230, 20)
$btnRestart.Add_Click({ Restart-Server })
$tabServer.Controls.Add($btnRestart)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Stopped"
$lblStatus.Location = New-Object System.Drawing.Point(400, 25)
$lblStatus.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblStatus)

$txtConsole = New-Object System.Windows.Forms.TextBox
$txtConsole.Multiline = $true
$txtConsole.ScrollBars = "Vertical"
$txtConsole.ReadOnly = $true
$txtConsole.BackColor = $colorConsoleBack
$txtConsole.ForeColor = $colorConsoleText
$txtConsole.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtConsole.Location = New-Object System.Drawing.Point(10, 80)
$txtConsole.Size = New-Object System.Drawing.Size(930, 410)
$tabServer.Controls.Add($txtConsole)

$lblCPU = New-Object System.Windows.Forms.Label
$lblCPU.Text = "CPU Usage: 0%"
$lblCPU.Location = New-Object System.Drawing.Point(10, 520)
$lblCPU.ForeColor = $colorText
$tabServer.Controls.Add($lblCPU)

$lblRAM = New-Object System.Windows.Forms.Label
$lblRAM.Text = "RAM Usage: 0 MB"
$lblRAM.Location = New-Object System.Drawing.Point(150, 520)
$lblRAM.ForeColor = $colorText
$tabServer.Controls.Add($lblRAM)

# =====================
# RAM CONTROLS
# =====================

$lblMinRam = New-Object System.Windows.Forms.Label
$lblMinRam.Text = "Min RAM (GB): 4"
$lblMinRam.Location = New-Object System.Drawing.Point(10, 560)
$lblMinRam.ForeColor = $colorText
$tabServer.Controls.Add($lblMinRam)

$trkMinRam = New-Object System.Windows.Forms.TrackBar
$trkMinRam.Minimum = 1
$trkMinRam.Maximum = 32
$trkMinRam.Value = $script:minRamGB
$trkMinRam.Location = New-Object System.Drawing.Point(10, 580)
$trkMinRam.Size = New-Object System.Drawing.Size(200, 45)
$trkMinRam.Add_Scroll({
    $script:minRamGB = $trkMinRam.Value
    $lblMinRam.Text = "Min RAM (GB): $($script:minRamGB)"
})
$tabServer.Controls.Add($trkMinRam)

$lblMaxRam = New-Object System.Windows.Forms.Label
$lblMaxRam.Text = "Max RAM (GB): 8"
$lblMaxRam.Location = New-Object System.Drawing.Point(230, 560)
$lblMaxRam.ForeColor = $colorText
$tabServer.Controls.Add($lblMaxRam)

$trkMaxRam = New-Object System.Windows.Forms.TrackBar
$trkMaxRam.Minimum = 1
$trkMaxRam.Maximum = 64
$trkMaxRam.Value = $script:maxRamGB
$trkMaxRam.Location = New-Object System.Drawing.Point(230, 580)
$trkMaxRam.Size = New-Object System.Drawing.Size(200, 45)
$trkMaxRam.Add_Scroll({
    $script:maxRamGB = $trkMaxRam.Value
    $lblMaxRam.Text = "Max RAM (GB): $($script:maxRamGB)"
})
$tabServer.Controls.Add($trkMaxRam)

# =====================
# CONFIG EDITOR TAB
# =====================

$tabConfig = New-Object System.Windows.Forms.TabPage
$tabConfig.Text = "Configuration"
$tabConfig.BackColor = $colorBack
$tabs.TabPages.Add($tabConfig)

$txtConfigEditor = New-Object System.Windows.Forms.TextBox
$txtConfigEditor.Multiline = $true
$txtConfigEditor.ScrollBars = "Vertical"
$txtConfigEditor.BackColor = $colorTextboxBack
$txtConfigEditor.ForeColor = $colorTextboxText
$txtConfigEditor.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtConfigEditor.Location = New-Object System.Drawing.Point(10, 20)
$txtConfigEditor.Size = New-Object System.Drawing.Size(760, 450)
$tabConfig.Controls.Add($txtConfigEditor)

$btnLoadConfig = New-Object System.Windows.Forms.Button
$btnLoadConfig.Text = "Load Configuration"
$btnLoadConfig.Location = New-Object System.Drawing.Point(790, 20)
$btnLoadConfig.Size = New-Object System.Drawing.Size(180, 30)
$btnLoadConfig.Add_Click({ Load-Config })
$tabConfig.Controls.Add($btnLoadConfig)

$btnSaveConfig = New-Object System.Windows.Forms.Button
$btnSaveConfig.Text = "Save Configuration"
$btnSaveConfig.Location = New-Object System.Drawing.Point(790, 60)
$btnSaveConfig.Size = New-Object System.Drawing.Size(180, 30)
$btnSaveConfig.Add_Click({ Save-Config })
$tabConfig.Controls.Add($btnSaveConfig)

# =====================
# UPDATE TAB
# =====================

$tabUpdate = New-Object System.Windows.Forms.TabPage
$tabUpdate.Text = "Update"
$tabUpdate.BackColor = $colorBack
$tabs.TabPages.Add($tabUpdate)

$lblUpdateStatus = New-Object System.Windows.Forms.Label
$lblUpdateStatus.Text = "Please wait..."
$lblUpdateStatus.Location = New-Object System.Drawing.Point(10, 20)
$lblUpdateStatus.ForeColor = $colorText
$tabUpdate.Controls.Add($lblUpdateStatus)

$btnUpdateServer = New-Object System.Windows.Forms.Button
$btnUpdateServer.Text = "Update Server"
$btnUpdateServer.Location = New-Object System.Drawing.Point(10, 60)
$btnUpdateServer.Add_Click({
    $lblUpdateStatus.Text = "Updating server..."
    Start-Sleep -Seconds 5 # Simulate update process
    $lblUpdateStatus.Text = "Update complete!"
})
$tabUpdate.Controls.Add($btnUpdateServer)

# =====================
# CHECK FILES TAB
# =====================

$tabCheckFiles = New-Object System.Windows.Forms.TabPage
$tabCheckFiles.Text = "Check Files"
$tabCheckFiles.BackColor = $colorBack
$tabs.TabPages.Add($tabCheckFiles)

$lblJarFile = New-Object System.Windows.Forms.Label
$lblJarFile.Text = "HytaleServer.jar - Missing"
$lblJarFile.Location = New-Object System.Drawing.Point(10, 20)
$lblJarFile.ForeColor = [System.Drawing.Color]::Red
$tabCheckFiles.Controls.Add($lblJarFile)

$lblJarStatus = New-Object System.Windows.Forms.Label
$lblJarStatus.Text = "[!!]"
$lblJarStatus.Location = New-Object System.Drawing.Point(400, 25)
$lblJarStatus.ForeColor = [System.Drawing.Color]::Red
$tabCheckFiles.Controls.Add($lblJarStatus)

$lblAssetsFile = New-Object System.Windows.Forms.Label
$lblAssetsFile.Text = "Assets.zip - Missing"
$lblAssetsFile.Location = New-Object System.Drawing.Point(10, 60)
$lblAssetsFile.ForeColor = [System.Drawing.Color]::Red
$tabCheckFiles.Controls.Add($lblAssetsFile)

$lblAssetsStatus = New-Object System.Windows.Forms.Label
$lblAssetsStatus.Text = "[!!]"
$lblAssetsStatus.Location = New-Object System.Drawing.Point(400, 65)
$lblAssetsStatus.ForeColor = [System.Drawing.Color]::Red
$tabCheckFiles.Controls.Add($lblAssetsStatus)

$lblServerFolder = New-Object System.Windows.Forms.Label
$lblServerFolder.Text = "Server/ - Missing"
$lblServerFolder.Location = New-Object System.Drawing.Point(10, 100)
$lblServerFolder.ForeColor = [System.Drawing.Color]::Red
$tabCheckFiles.Controls.Add($lblServerFolder)

$lblServerFolderStatus = New-Object System.Windows.Forms.Label
$lblServerFolderStatus.Text = "[!!]"
$lblServerFolderStatus.Location = New-Object System.Drawing.Point(400, 105)
$lblServerFolderStatus.ForeColor = [System.Drawing.Color]::Red
$tabCheckFiles.Controls.Add($lblServerFolderStatus)

$lblModsFolder = New-Object System.Windows.Forms.Label
$lblModsFolder.Text = "mods/ - Missing"
$lblModsFolder.Location = New-Object System.Drawing.Point(10, 140)
$lblModsFolder.ForeColor = [System.Drawing.Color]::Red
$tabCheckFiles.Controls.Add($lblModsFolder)

$lblModsFolderStatus = New-Object System.Windows.Forms.Label
$lblModsFolderStatus.Text = "[!!]"
$lblModsFolderStatus.Location = New-Object System.Drawing.Point(400, 145)
$lblModsFolderStatus.ForeColor = [System.Drawing.Color]::Red
$tabCheckFiles.Controls.Add($lblModsFolderStatus)

$lblConfigFile = New-Object System.Windows.Forms.Label
$lblConfigFile.Text = "config.json - Missing"
$lblConfigFile.Location = New-Object System.Drawing.Point(10, 180)
$lblConfigFile.ForeColor = [System.Drawing.Color]::Red
$tabCheckFiles.Controls.Add($lblConfigFile)

$lblConfigStatus = New-Object System.Windows.Forms.Label
$lblConfigStatus.Text = "[!!]"
$lblConfigStatus.Location = New-Object System.Drawing.Point(400, 185)
$lblConfigStatus.ForeColor = [System.Drawing.Color]::Red
$tabCheckFiles.Controls.Add($lblConfigStatus)

$btnCheckFiles = New-Object System.Windows.Forms.Button
$btnCheckFiles.Text = "Check Files"
$btnCheckFiles.Location = New-Object System.Drawing.Point(10, 220)
$btnCheckFiles.Add_Click({ Check-ServerFiles })
$tabCheckFiles.Controls.Add($btnCheckFiles)

$lblOverallStatus = New-Object System.Windows.Forms.Label
$lblOverallStatus.Text = "[WARN] Missing required files"
$lblOverallStatus.Location = New-Object System.Drawing.Point(400, 225)
$lblOverallStatus.ForeColor = [System.Drawing.Color]::Orange
$tabCheckFiles.Controls.Add($lblOverallStatus)

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
$txtCommandConsole.Size = New-Object System.Drawing.Size(930, 300)
$tabCommand.Controls.Add($txtCommandConsole)

# Command input
$txtCommandInput = New-Object System.Windows.Forms.TextBox
$txtCommandInput.Location = New-Object System.Drawing.Point(10, 320)
$txtCommandInput.Size = New-Object System.Drawing.Size(800, 25)
$tabCommand.Controls.Add($txtCommandInput)

# Send button
$btnSendCommand = New-Object System.Windows.Forms.Button
$btnSendCommand.Text = "Send"
$btnSendCommand.Location = New-Object System.Drawing.Point(820, 320)
$btnSendCommand.Size = New-Object System.Drawing.Size(120, 25)
$btnSendCommand.Add_Click({
    Send-ServerCommand $txtCommandInput.Text
    $txtCommandInput.Text = ""
})
$tabCommand.Controls.Add($btnSendCommand)

# Enter key support
$txtCommandInput.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        Send-ServerCommand $txtCommandInput.Text
        $txtCommandInput.Text = ""
    }
})

# Function to send commands
function Send-ServerCommand {
    param($command)
    if ($script:serverRunning -and $script:serverProcess -and -not $script:serverProcess.HasExited) {
        $script:serverProcess.StandardInput.WriteLine($command)
    } else {
        [System.Windows.Forms.MessageBox]::Show("Server is not running.","Error")
    }
}

# Tooltip object
$toolTip = New-Object System.Windows.Forms.ToolTip

# FLOWLAYOUTPANEL for buttons (bottom of tab)
$flowButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$flowButtons.Location = New-Object System.Drawing.Point(10, 360)   # below input
$flowButtons.Size = New-Object System.Drawing.Size(930, 180)
$flowButtons.AutoScroll = $true
$tabCommand.Controls.Add($flowButtons)

# Admin Commands
$adminCommands = @{
    "/spawning"  = "Commands related to NPC spawning."
    "/ban"       = "Ban a player from the server."
    "/unban"     = "Unban a player from the server."
    "/gamemode"  = "Change a player’s gamemode."
    "/give"      = "Spawn items for a player in-game."
    "/heal"      = "Heals up to max health and stamina."
    "/kick"      = "Kicks a player from the server."
    "/op"        = "Gives admin permissions to a player."
    "/perm"      = "Permissions command for groups or users."
    "/plugin"    = "Manage plugins."
    "/stop"      = "Shut down the server."
    "/sudo"      = "Run a command as another player."
    "/tp"        = "Teleport to location or player."
    "/whitelist" = "Manage server whitelist."
    "/ping"      = "Check server latency."
}

foreach ($cmd in $adminCommands.Keys) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $cmd
    $btn.Size = New-Object System.Drawing.Size(80, 25)
    $btn.Add_Click({ Send-ServerCommand $cmd })
    $toolTip.SetToolTip($btn, $adminCommands[$cmd])
    $flowButtons.Controls.Add($btn)
}

# World Commands
$worldCommands = @{
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
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $cmd
    $btn.Size = New-Object System.Drawing.Size(80, 25)
    $btn.Add_Click({ Send-ServerCommand $cmd })
    $toolTip.SetToolTip($btn, $worldCommands[$cmd])
    $flowButtons.Controls.Add($btn)
}

# =====================
# RUN GUI
# =====================

$form.ShowDialog()