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

# Path to the permissions file
$script:permissionsPath = Join-Path $PSScriptRoot "permissions.json"

# Path to the main server log file
$script:logFilePath    = Join-Path $PSScriptRoot "logs\latest.log"

# Path to the downloader executable
$script:downloaderPath = Join-Path $PSScriptRoot "hytale-downloader-windows-amd64.exe"

# Timer object used for polling the log file and monitoring CPU/RAM usage
$script:logTimer = $null

# Keeps track of the last read size of the log file so we only read new lines
$script:lastLogSize = 0

# Minimum RAM (in GB) allocated to the server
$script:minRamGB = 4

# Maximum RAM (in GB) allocated to the server
$script:maxRamGB = 16

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

# =====================
# BUTTON STYLING HELPER
# =====================

function Style-Button {
    param([System.Windows.Forms.Button]$btn)

    $btn.BackColor = $colorButtonBack
    $btn.ForeColor = $colorButtonText
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(100,100,100)
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
                $sr = New-Object System.IO.StreamReader($fs)
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

    try {
        $json = Get-Content $script:configPath -Raw | ConvertFrom-Json
        $formatted = $json | ConvertTo-Json -Depth 10 -Compress:$false  # Pretty format
        $txtConfigEditor.Text = $formatted
    } catch {
        # Fallback: raw text if JSON invalid
        $txtConfigEditor.Text = Get-Content $script:configPath -Raw
    }
}

function Save-Config {
    try {
        $txtConfigEditor.Text | ConvertFrom-Json  # Validate JSON
        # Reformat to pretty JSON on save to maintain layout
        $pretty = ($txtConfigEditor.Text | ConvertFrom-Json | ConvertTo-Json -Depth 10 -Compress:$false)
        Set-Content -Path $script:configPath -Value $pretty
        [System.Windows.Forms.MessageBox]::Show("Configuration saved successfully","Success")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Invalid JSON format. Please check your configuration.","Error")
    }
}

function Load-Permissions {
    if (-not (Test-Path $script:permissionsPath)) { return }

    try {
        $json = Get-Content $script:permissionsPath -Raw | ConvertFrom-Json
        $formatted = $json | ConvertTo-Json -Depth 10 -Compress:$false
        $txtConfigEditor.Text = $formatted
    } catch {
        $txtConfigEditor.Text = Get-Content $script:permissionsPath -Raw
    }
}

function Save-Permissions {
    try {
        $txtConfigEditor.Text | ConvertFrom-Json  # Validate JSON
        $pretty = ($txtConfigEditor.Text | ConvertFrom-Json | ConvertTo-Json -Depth 10 -Compress:$false)
        Set-Content -Path $script:permissionsPath -Value $pretty
        [System.Windows.Forms.MessageBox]::Show("Permissions saved successfully","Success")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Invalid JSON format. Please check your permissions file.","Error")
    }
}

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
        Start-Sleep -Seconds 3
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
        # Step 2: Run the downloader
        # ==============================
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:downloaderPath
        $psi.WorkingDirectory = $PSScriptRoot
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $updateProcess = New-Object System.Diagnostics.Process
        $updateProcess.StartInfo = $psi
        $updateProcess.Start() | Out-Null

        $txtUpdateLog.AppendText("[INFO] Downloading latest server files...`r`n")

        $output = $updateProcess.StandardOutput.ReadToEnd()
        $error = $updateProcess.StandardError.ReadToEnd()
        $updateProcess.WaitForExit()

        if ($output) { $txtUpdateLog.AppendText($output + "`r`n") }
        if ($error) { $txtUpdateLog.AppendText("[ERROR] $error`r`n") }

        $txtUpdateLog.AppendText("[INFO] Download process completed (Exit Code: $($updateProcess.ExitCode))`r`n")

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
        # Step 6: Extract, merge, cleanup
        # ==============================
        $txtUpdateLog.AppendText("[INFO] Extracting update files...`r`n")
        $tempExtractPath = Join-Path $PSScriptRoot "temp_update_extract"
        
        if (Test-Path $tempExtractPath) {
            $txtUpdateLog.AppendText("[INFO] Cleaning old temp directory...`r`n")
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        New-Item -Path $tempExtractPath -ItemType Directory -Force | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($downloadedZip.FullName, $tempExtractPath)
        $txtUpdateLog.AppendText("[INFO] Extraction complete.`r`n")

        # Merge files
        $txtUpdateLog.AppendText("[INFO] Merging files into server directory...`r`n")
        $filesCopied = 0
        $filesUpdated = 0
        Get-ChildItem -Path $tempExtractPath -Recurse | ForEach-Object {
            $relativePath = $_.FullName.Substring($tempExtractPath.Length + 1)
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
        $txtUpdateLog.AppendText("[INFO] Merge complete! New files: $filesCopied | Updated files: $filesUpdated`r`n")

        # Clean up temp
        $txtUpdateLog.AppendText("[INFO] Cleaning up temporary files...`r`n")
        Remove-Item -Path $tempExtractPath -Recurse -Force

        $txtUpdateLog.AppendText("========================================`r`n")
        $txtUpdateLog.AppendText("[SUCCESS] Update completed successfully!`r`n")
        $txtUpdateLog.AppendText("========================================`r`n")

        # Re-validate server files
        Check-ServerFiles

        # Restart server if it was running
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
        $txtUpdateLog.AppendText("[EXCEPTION] $($_)`r`n")
        $txtUpdateLog.AppendText("[EXCEPTION] $($_.ScriptStackTrace)`r`n")
        [System.Windows.Forms.MessageBox]::Show("Update failed: $_", "Error")

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

function Get-DownloaderServerVersion {
    $output = Run-DownloaderAndCapture "-print-version"

    if ($output -match "(\d+\.\d+\.\d+)") {
        return $matches[1]
    }

    return $null
}

function Get-ZipServerVersion {
    # Get all ZIPs in server folder, ignore Assets.zip
    $zipFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.zip" | Where-Object { $_.Name -notlike "Assets.zip" }

    if ($zipFiles.Count -eq 0) { return $null } # No zip to compare

    # Take the latest ZIP
    $latestZip = $zipFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    # Extract version from filename: e.g. "2026.01.17-4b0f30090.zip" → "4b0f30090"
    if ($latestZip.Name -match '^\d{4}\.\d{2}\.\d{2}-(.+)\.zip$') {
        return $matches[1]
    } else {
        return $null
    }
}

function Check-ServerUpdate {

    $exeVersion = Get-DownloaderServerVersion
    if (-not $exeVersion) {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not read server version from downloader.",
            "Version Error"
        )
        return
    }

    $zipVersion = Get-ZipServerVersion
    if (-not $zipVersion) {
        [System.Windows.Forms.MessageBox]::Show(
            "No server update ZIP found to compare against.",
            "No Update Package"
        )
        return
    }
	
	$txtUpdateLog.AppendText("[DEBUG] EXE=$exeVersion ZIP=$zipVersion`r`n")

    if ($exeVersion -ne $zipVersion) {
        [System.Windows.Forms.MessageBox]::Show(
            "Update Available!`n`nInstalled (EXE): $exeVersion`nZIP Package: $zipVersion",
            "Update Available",
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
    else {
        [System.Windows.Forms.MessageBox]::Show(
            "No update available.`n`nVersion: $exeVersion",
            "Up To Date",
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }
}

function Run-DownloaderCommand {
    param([string]$arguments, [string]$description)
    
    if (-not (Test-Path $script:downloaderPath)) {
        $txtUpdateLog.AppendText("[ERROR] Downloader not found at: $script:downloaderPath`r`n")
        [System.Windows.Forms.MessageBox]::Show("Downloader executable not found!", "Error")
        return
    }

    try {
        $txtUpdateLog.AppendText("========================================`r`n")
        $txtUpdateLog.AppendText("[INFO] $description`r`n")
        $txtUpdateLog.AppendText("[INFO] Command: $script:downloaderPath $arguments`r`n")
        $txtUpdateLog.AppendText("========================================`r`n")

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
        $process.Start() | Out-Null

        $output = $process.StandardOutput.ReadToEnd()
        $error = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if ($output) { $txtUpdateLog.AppendText($output + "`r`n") }
        if ($error) { $txtUpdateLog.AppendText("[ERROR] $error`r`n") }

        $txtUpdateLog.AppendText("[INFO] Command completed (Exit Code: $($process.ExitCode))`r`n")
        $txtUpdateLog.AppendText("========================================`r`n")

        return $output   # ✅ Return the raw output
    } catch {
        $txtUpdateLog.AppendText("[EXCEPTION] $($_)`r`n")
        [System.Windows.Forms.MessageBox]::Show("Command failed: $_", "Error")
        return $null
    }
}

# Function to send commands (MUST BE DEFINED BEFORE GUI COMPONENTS)
function Send-ServerCommand {
    param($command)
    if ($script:serverRunning -and $script:serverProcess -and -not $script:serverProcess.HasExited) {
        $script:serverProcess.StandardInput.WriteLine($command)
    } else {
        [System.Windows.Forms.MessageBox]::Show("Server is not running.","Error")
    }
}

function Get-VersionFromConsole {
    param([System.Windows.Forms.TextBox]$console)

    $lines = $console.Text -split "`r?`n"

    foreach ($line in ($lines | Select-Object -Last 20)) {
        if ($line -match "(\d+\.\d+\.\d+)") {
            return $matches[1]
        }
    }

    return $null
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
$tabServer.AutoScroll = $true
$tabs.TabPages.Add($tabServer)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Server"
$btnStart.Location = New-Object System.Drawing.Point(10, 20)
Style-Button $btnStart        # 👈 ADD THIS LINE
$btnStart.Add_Click({ Start-Server })
$tabServer.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop Server"
$btnStop.Location = New-Object System.Drawing.Point(120, 20)
Style-Button $btnStop
$btnStop.Add_Click({ Stop-Server })
$tabServer.Controls.Add($btnStop)

$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = "Restart Server"
$btnRestart.Location = New-Object System.Drawing.Point(230, 20)
Style-Button $btnRestart
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
$lblCPU.Location = New-Object System.Drawing.Point(10, 500)
$lblCPU.ForeColor = $colorText
$tabServer.Controls.Add($lblCPU)

$lblRAM = New-Object System.Windows.Forms.Label
$lblRAM.Text = "RAM Usage: 0 MB"
$lblRAM.Location = New-Object System.Drawing.Point(150, 500)
$lblRAM.ForeColor = $colorText
$tabServer.Controls.Add($lblRAM)

# =====================
# RAM CONTROLS (TO THE RIGHT OF STATUS)
# =====================

# Min RAM label
$lblMinRam = New-Object System.Windows.Forms.Label
$lblMinRam.Text = "Min RAM (GB): 4"
$lblMinRam.Location = New-Object System.Drawing.Point(550, 20)
$lblMinRam.ForeColor = $colorText
$lblMinRam.AutoSize = $true
$tabServer.Controls.Add($lblMinRam)

# Min RAM slider
$trkMinRam = New-Object System.Windows.Forms.TrackBar
$trkMinRam.Minimum = 4
$trkMinRam.Maximum = 16
$trkMinRam.Value = $script:minRamGB
$trkMinRam.Location = New-Object System.Drawing.Point(550, 35)
$trkMinRam.Size = New-Object System.Drawing.Size(180, 45)
$trkMinRam.TickStyle = [System.Windows.Forms.TickStyle]::BottomRight
$trkMinRam.Add_Scroll({
    $script:minRamGB = $trkMinRam.Value
    $lblMinRam.Text = "Min RAM (GB): $($script:minRamGB)"
})
$tabServer.Controls.Add($trkMinRam)

# Max RAM label
$lblMaxRam = New-Object System.Windows.Forms.Label
$lblMaxRam.Text = "Max RAM (GB): 16"
$lblMaxRam.Location = New-Object System.Drawing.Point(750, 20)
$lblMaxRam.ForeColor = $colorText
$lblMaxRam.AutoSize = $true
$tabServer.Controls.Add($lblMaxRam)

# Max RAM slider
$trkMaxRam = New-Object System.Windows.Forms.TrackBar
$trkMaxRam.Minimum = 8
$trkMaxRam.Maximum = 32
$trkMaxRam.Value = $script:maxRamGB
$trkMaxRam.Location = New-Object System.Drawing.Point(750, 35)
$trkMaxRam.Size = New-Object System.Drawing.Size(180, 45)
$trkMaxRam.TickStyle = [System.Windows.Forms.TickStyle]::BottomRight
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

$tabServer = New-Object System.Windows.Forms.TabPage
$tabServer.Text = "Server Maintenance"
$tabServer.BackColor = $colorBack
$tabs.TabPages.Add($tabServer)

# =====================
# UPDATE SECTION
# =====================

$lblUpdateInfo = New-Object System.Windows.Forms.Label
$lblUpdateInfo.Text = "Download and install the latest Hytale server files using the official downloader."
$lblUpdateInfo.Location = New-Object System.Drawing.Point(10, 20)
$lblUpdateInfo.Size = New-Object System.Drawing.Size(940, 20)
$lblUpdateInfo.ForeColor = $colorText
$tabServer.Controls.Add($lblUpdateInfo)

$lblDownloaderPath = New-Object System.Windows.Forms.Label
$lblDownloaderPath.Text = "Downloader:"
$lblDownloaderPath.Location = New-Object System.Drawing.Point(10, 50)
$lblDownloaderPath.Size = New-Object System.Drawing.Size(80, 20)
$lblDownloaderPath.ForeColor = $colorText
$tabServer.Controls.Add($lblDownloaderPath)

$txtDownloaderPath = New-Object System.Windows.Forms.TextBox
$txtDownloaderPath.Location = New-Object System.Drawing.Point(100, 48)
$txtDownloaderPath.Size = New-Object System.Drawing.Size(620, 20)
$txtDownloaderPath.ReadOnly = $true
$txtDownloaderPath.BackColor = $colorTextboxBack
$txtDownloaderPath.ForeColor = $colorTextboxText
$txtDownloaderPath.Text = $script:downloaderPath
$tabServer.Controls.Add($txtDownloaderPath)

$btnUpdateServer = New-Object System.Windows.Forms.Button
$btnUpdateServer.Text = "Update Server"
$btnUpdateServer.Location = New-Object System.Drawing.Point(100, 80)
$btnUpdateServer.Size = New-Object System.Drawing.Size(150, 35)
$btnUpdateServer.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
$btnUpdateServer.ForeColor = $colorText
$btnUpdateServer.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$btnUpdateServer.Add_Click({ Update-Server })
$tabServer.Controls.Add($btnUpdateServer)

$chkAutoRestart = New-Object System.Windows.Forms.CheckBox
$chkAutoRestart.Text = "Auto-restart server after update"
$chkAutoRestart.Location = New-Object System.Drawing.Point(270, 85)
$chkAutoRestart.Size = New-Object System.Drawing.Size(250, 25)
$chkAutoRestart.ForeColor = $colorText
$chkAutoRestart.Checked = $true
$tabServer.Controls.Add($chkAutoRestart)

$lblUpdateWarning = New-Object System.Windows.Forms.Label
$lblUpdateWarning.Text = "[!] Server will be stopped during update"
$lblUpdateWarning.Location = New-Object System.Drawing.Point(530, 88)
$lblUpdateWarning.Size = New-Object System.Drawing.Size(250, 20)
$lblUpdateWarning.ForeColor = [System.Drawing.Color]::Orange
$lblUpdateWarning.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabServer.Controls.Add($lblUpdateWarning)

# Downloader utility buttons
$lblDownloaderUtils = New-Object System.Windows.Forms.Label
$lblDownloaderUtils.Text = "Downloader Utilities:"
$lblDownloaderUtils.Location = New-Object System.Drawing.Point(10, 135)
$lblDownloaderUtils.Size = New-Object System.Drawing.Size(150, 20)
$lblDownloaderUtils.ForeColor = $colorText
$lblDownloaderUtils.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabServer.Controls.Add($lblDownloaderUtils)

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
$tabServer.Controls.Add($btnPrintVersion)

$btnDownloaderVersion = New-Object System.Windows.Forms.Button
$btnDownloaderVersion.Text = "Downloader Version"
$btnDownloaderVersion.Location = New-Object System.Drawing.Point(310, 130)
$btnDownloaderVersion.Size = New-Object System.Drawing.Size(140, 28)
$btnDownloaderVersion.BackColor = $colorButtonBack
$btnDownloaderVersion.ForeColor = $colorText
$btnDownloaderVersion.Add_Click({ Run-DownloaderCommand "-version" "Checking downloader version" })
$tabServer.Controls.Add($btnDownloaderVersion)

$btnCheckUpdate = New-Object System.Windows.Forms.Button
$btnCheckUpdate.Text = "Check for Downloader Update"
$btnCheckUpdate.Location = New-Object System.Drawing.Point(460, 130)
$btnCheckUpdate.Size = New-Object System.Drawing.Size(140, 28)
$btnCheckUpdate.BackColor = $colorButtonBack
$btnCheckUpdate.ForeColor = $colorText
$btnCheckUpdate.Add_Click({ Run-DownloaderCommand "-check-update" "Checking for downloader updates" })
$tabServer.Controls.Add($btnCheckUpdate)

$txtUpdateLog = New-Object System.Windows.Forms.TextBox
$txtUpdateLog.Multiline = $true
$txtUpdateLog.ScrollBars = "Vertical"
$txtUpdateLog.ReadOnly = $true
$txtUpdateLog.BackColor = $colorConsoleBack
$txtUpdateLog.ForeColor = $colorConsoleText
$txtUpdateLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtUpdateLog.Location = New-Object System.Drawing.Point(10, 170)
$txtUpdateLog.Size = New-Object System.Drawing.Size(960, 150)
$tabServer.Controls.Add($txtUpdateLog)

# =====================
# CHECK FILES SECTION (MINIMAL FIX)
# =====================

$lblCheckFilesTitle = New-Object System.Windows.Forms.Label
$lblCheckFilesTitle.Text = "Check Required Files:"
$lblCheckFilesTitle.Location = New-Object System.Drawing.Point(10, 330)
$lblCheckFilesTitle.Size = New-Object System.Drawing.Size(200, 20)
$lblCheckFilesTitle.ForeColor = $colorText
$lblCheckFilesTitle.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$tabServer.Controls.Add($lblCheckFilesTitle)

# Keep explicit variables for each file to match your Check-ServerFiles function
$lblJarFile = New-Object System.Windows.Forms.Label
$lblJarFile.Text = "HytaleServer.jar - Missing"
$lblJarFile.Location = New-Object System.Drawing.Point(10, 360)
$lblJarFile.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblJarFile)

$lblJarStatus = New-Object System.Windows.Forms.Label
$lblJarStatus.Text = "[!!]"
$lblJarStatus.Location = New-Object System.Drawing.Point(400, 360)
$lblJarStatus.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblJarStatus)

$lblAssetsFile = New-Object System.Windows.Forms.Label
$lblAssetsFile.Text = "Assets.zip - Missing"
$lblAssetsFile.Location = New-Object System.Drawing.Point(10, 400)
$lblAssetsFile.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblAssetsFile)

$lblAssetsStatus = New-Object System.Windows.Forms.Label
$lblAssetsStatus.Text = "[!!]"
$lblAssetsStatus.Location = New-Object System.Drawing.Point(400, 400)
$lblAssetsStatus.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblAssetsStatus)

$lblServerFolder = New-Object System.Windows.Forms.Label
$lblServerFolder.Text = "Server/ - Missing"
$lblServerFolder.Location = New-Object System.Drawing.Point(10, 440)
$lblServerFolder.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblServerFolder)

$lblServerFolderStatus = New-Object System.Windows.Forms.Label
$lblServerFolderStatus.Text = "[!!]"
$lblServerFolderStatus.Location = New-Object System.Drawing.Point(400, 440)
$lblServerFolderStatus.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblServerFolderStatus)

$lblModsFolder = New-Object System.Windows.Forms.Label
$lblModsFolder.Text = "mods/ - Missing"
$lblModsFolder.Location = New-Object System.Drawing.Point(10, 480)
$lblModsFolder.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblModsFolder)

$lblModsFolderStatus = New-Object System.Windows.Forms.Label
$lblModsFolderStatus.Text = "[!!]"
$lblModsFolderStatus.Location = New-Object System.Drawing.Point(400, 480)
$lblModsFolderStatus.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblModsFolderStatus)

$lblConfigFile = New-Object System.Windows.Forms.Label
$lblConfigFile.Text = "config.json - Missing"
$lblConfigFile.Location = New-Object System.Drawing.Point(10, 515)  # slight move up (from 520)
$lblConfigFile.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblConfigFile)

$lblConfigStatus = New-Object System.Windows.Forms.Label
$lblConfigStatus.Text = "[!!]"
$lblConfigStatus.Location = New-Object System.Drawing.Point(400, 515)  # slight move up
$lblConfigStatus.ForeColor = [System.Drawing.Color]::Red
$tabServer.Controls.Add($lblConfigStatus)

# Check Files button on the right (unchanged)
$btnCheckFiles = New-Object System.Windows.Forms.Button
$btnCheckFiles.Text = "Check Files"
$btnCheckFiles.Location = New-Object System.Drawing.Point(700, 360)
Style-Button $btnCheckFiles
$btnCheckFiles.Add_Click({ Check-ServerFiles })
$tabServer.Controls.Add($btnCheckFiles)

# Overall status label under button (unchanged)
$lblOverallStatus = New-Object System.Windows.Forms.Label
$lblOverallStatus.Text = "[WARN] Missing required files"
$lblOverallStatus.Location = New-Object System.Drawing.Point(700, 400)
$lblOverallStatus.ForeColor = [System.Drawing.Color]::Orange
$tabServer.Controls.Add($lblOverallStatus)

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
Style-Button $btnSendCommand
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

# Tooltip object
$toolTip = New-Object System.Windows.Forms.ToolTip

# FLOWLAYOUTPANEL for buttons (bottom of tab)
$flowButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$flowButtons.Location = New-Object System.Drawing.Point(10, 360)
$flowButtons.Size = New-Object System.Drawing.Size(930, 180)
$flowButtons.AutoScroll = $true
$tabCommand.Controls.Add($flowButtons)

# Admin Commands
$adminCommands = @{
    "/spawning"  = "Commands related to NPC spawning."
    "/ban"       = "Ban a player from the server."
    "/unban"     = "Unban a player from the server."
    "/gamemode"  = "Change a player's gamemode."
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
    $btn.Tag = $cmd  # Store the command in the Tag property
	Style-Button $btn    # 👈 ADD THIS LINE
    $btn.Add_Click({ 
        $txtCommandInput.Text = $this.Tag + " "  # Insert command into textbox with a space
        $txtCommandInput.Focus()  # Focus the textbox so user can type arguments
        $txtCommandInput.SelectionStart = $txtCommandInput.Text.Length  # Move cursor to end
    })
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
    $btn.Tag = $cmd  # Store the command in the Tag property
	Style-Button $btn    # 👈 ADD THIS LINE
    $btn.Add_Click({ 
        $txtCommandInput.Text = $this.Tag + " "  # Insert command into textbox with a space
        $txtCommandInput.Focus()  # Focus the textbox so user can type arguments
        $txtCommandInput.SelectionStart = $txtCommandInput.Text.Length  # Move cursor to end
    })
    $toolTip.SetToolTip($btn, $worldCommands[$cmd])
    $flowButtons.Controls.Add($btn)
}

# =====================
# RUN GUI
# =====================

$form.ShowDialog()