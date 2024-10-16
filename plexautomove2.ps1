# Define the paths
$sourceFolder = "C:\Users\vonwa\AppData\Local\Plex\Plex Media Server\Sync\1\1"
$primaryDestination = "L:\james"
$secondaryDestination = "m:\james"
$logFile = "PlexFolderMover.log"
$allowedExtensions = @(".mkv", ".mp4", ".avi") # Add or remove extensions as needed
$spaceThreshold = 50GB # 50 gigabytes

# Function to log messages
function Log-Message($message) {
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message"
    Add-Content -Path $logFile -Value $logMessage
    Write-Host $logMessage
}

# Function to check available space on a drive
function Get-DriveSpace($driveLetter) {
    $drive = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$driveLetter'"
    return $drive.FreeSpace
}

# Function to determine the current destination folder
function Get-CurrentDestination {
    $primarySpace = Get-DriveSpace($primaryDestination.Substring(0, 2))
    if ($primarySpace -gt $spaceThreshold) {
        return $primaryDestination
    } else {
        return $secondaryDestination
    }
}

# Function to check if a file is still being written to
function Is-FileReady($filePath) {
    try {
        $fileInfo = New-Object System.IO.FileInfo($filePath)
        $fileStream = $fileInfo.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        if ($fileStream) {
            $fileStream.Close()
            return $true
        }
    }
    catch {
        return $false
    }
}

# Function to wait for all files in a folder to be ready
function Wait-ForFolderReady($folderPath) {
    $allFilesReady = $false
    while (-not $allFilesReady) {
        $allFilesReady = $true
        Get-ChildItem -Path $folderPath -Recurse | ForEach-Object {
            if (-not (Is-FileReady $_.FullName)) {
                $allFilesReady = $false
                Start-Sleep -Seconds 5
                return
            }
        }
    }
}

# Function to check if folder contains allowed file types
function Contains-AllowedFiles($folderPath) {
    $files = Get-ChildItem -Path $folderPath -Recurse -File
    foreach ($file in $files) {
        if ($allowedExtensions -contains $file.Extension.ToLower()) {
            return $true
        }
    }
    return $false
}

# Create a FileSystemWatcher to monitor the source folder
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $sourceFolder
$watcher.Filter = "*"
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

# Define the action to take when a new folder is created
$action = {
    $path = $Event.SourceEventArgs.FullPath
    $name = $Event.SourceEventArgs.Name
    $changeType = $Event.SourceEventArgs.ChangeType
    
    if ($changeType -eq [System.IO.WatcherChangeTypes]::Created -and (Test-Path $path -PathType Container))
    {
        Log-Message "Folder '$name' was created in $sourceFolder"
        $currentDestination = Get-CurrentDestination
        $destinationPath = Join-Path $currentDestination $name
        
        # Wait for all files in the folder to be ready
        Log-Message "Waiting for all files in '$name' to be ready for moving..."
        Wait-ForFolderReady $path
        
        # Check if folder contains allowed file types
        if (Contains-AllowedFiles $path) {
            # Move the folder to the destination
            try {
                Move-Item -Path $path -Destination $destinationPath -Force -ErrorAction Stop
                Log-Message "Folder '$name' has been moved to $currentDestination"
            }
            catch {
                Log-Message "Error moving folder '$name': $_"
            }
        }
        else {
            Log-Message "Folder '$name' does not contain any allowed file types. Skipping."
        }
    }
}

# Register the event handler
Register-ObjectEvent $watcher "Created" -Action $action

Log-Message "Watching for new folders in $sourceFolder..."
Log-Message "Will use $secondaryDestination when $primaryDestination has less than $spaceThreshold free space."
Log-Message "Press Ctrl+C to stop the script."

# Keep the script running
try {
    while ($true) { Start-Sleep -Seconds 10 }
}
finally {
    # Cleanup
    $watcher.Dispose()
    Log-Message "Script stopped."
}