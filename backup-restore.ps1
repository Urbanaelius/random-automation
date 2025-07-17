# Backup and Restore Utility – Oracle DB Recovery

# Get hostnames
$sourceComputer = Read-Host "Enter the Source (Working) Computer hostname"
$destiComputer = Read-Host "Enter the Destination (Broken) Computer hostname"

# Paths
$scriptPath = ".\Scripts\my-oracle-backup.ps1"
$tempDir = "C:\temp"
$backupDir = "$tempDir\backup"
$archiveDmp = "$backupDir\backup.dmp.7z"
$lastNightBackup = "xstore.bak.gz"

# Copy backup script to both systems
Copy-Item -Path $scriptPath -Destination "\\$sourceComputer\c$\temp"
Copy-Item -Path $scriptPath -Destination "\\$destiComputer\c$\temp"

# Ask user which backup method to use
$backupChoice = Read-Host "Select Backup Option:`n1. Create new Oracle backup`n2. Use last night's xstore.bak.gz backup"

# Variable to track selected method
$usedNewBackup = $false

try {
    if ($backupChoice -eq '1') {
        $usedNewBackup = $true
        Clear-Host
        Write-Host "Creating a new Oracle DB backup on $sourceComputer..." -ForegroundColor Cyan

        # Create new backup on source
        Invoke-Command -ComputerName $sourceComputer -ScriptBlock {
            $backupDir = "C:\temp\backup"
            $backupFile = "$backupDir\backup.dmp"

            if (-Not (Test-Path $backupDir)) {
                New-Item -Path $backupDir -ItemType Directory -Force
            }

            if (Test-Path $backupFile) {
                Write-Host "Removing old backup file..."
                Remove-Item -Path $backupFile -Force
            }

            cd "C:\temp"
            .\my-oracle-backup.ps1 -mode backup -filename backup.dmp
        }

        Start-Sleep -Seconds 2

        # Compress backup
        $sevenZipPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\7-Zip").Path
        if (Test-Path $archiveDmp) { Remove-Item $archiveDmp -Force }
        & "$sevenZipPath\7z.exe" a -t7z -mx=9 $archiveDmp "\\$sourceComputer\c$\temp\backup\backup.dmp"

        # Transfer to destination
        robocopy "\\$sourceComputer\c$\temp\backup" "\\$destiComputer\c$\temp\backup" "backup.dmp.7z" /ETA /E /MT:32

    } elseif ($backupChoice -eq '2') {
        Clear-Host
        Write-Host "Using last night's xstore.bak.gz from $sourceComputer..." -ForegroundColor Cyan

        robocopy "\\$sourceComputer\c$\xstoredb\backup" "\\$destiComputer\c$\Temp\backup" $lastNightBackup /ETA /E /MT:32

    } else {
        Write-Host "Invalid selection. Exiting." -ForegroundColor Red
        exit
    }

    # Restore on initial destination computer
    function Restore-Backup {
        param($computerName)

        if ($usedNewBackup) {
            Write-Host "`nExtracting and restoring Oracle DB on $computerName..." -ForegroundColor Cyan

            Invoke-Command -ComputerName $computerName -ScriptBlock {
                $backupDir = "C:\temp\backup"
                $archiveFile = "$backupDir\backup.dmp.7z"
                $sevenZipPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\7-Zip").Path

                if (Test-Path $archiveFile) {
                    & "$sevenZipPath\7z.exe" e -o"$backupDir" -y "$archiveFile"
                }

                if (Test-Path "$backupDir\backup.dmp") {
                    Write-Host "✅ Extracted backup.dmp successfully."
                    cd "C:\temp"
                    .\my-oracle-backup.ps1 -mode restore-force -filename backup.dmp
                } else {
                    Write-Host "❌ Failed to extract backup.dmp" -ForegroundColor Red
                }
            }

        } else {
            Write-Host "`nExtracting and restoring xstore.bak.gz on $computerName..." -ForegroundColor Cyan

            Invoke-Command -ComputerName $computerName -ScriptBlock {
                $zipFile = "C:\temp\backup\xstore.bak.gz"
                $sevenZipPath = (Get-ItemProperty -Path HKLM:\SOFTWARE\7-Zip).Path
                $extractPath = "C:\temp\backup"

                if (Test-Path $zipFile) {
                    & "$sevenZipPath\7z.exe" e -o"$extractPath" -y "$zipFile"
                }

                $extractedFile = Join-Path -Path $extractPath -ChildPath "xstore.bak"
                if (Test-Path $extractedFile) {
                    Write-Host "✅ Extracted xstore.bak successfully."
                    cd "C:\temp"
                    .\my-oracle-backup.ps1 -mode restore-force -filename xstore.bak
                } else {
                    Write-Host "❌ Extraction failed." -ForegroundColor Red
                }
            }
        }
    }

    # Confirm restore on initial destination
    $confirm = Read-Host "`nIs $destiComputer ready for restoration? (y/n)"
    if ($confirm -eq 'y') {
        Restore-Backup -computerName $destiComputer
    } else {
        Write-Host "⚠️ Skipping restoration on $destiComputer." -ForegroundColor Yellow
    }

    # Additional destination computers
    while ($true) {
        $more = Read-Host "`nRestore to another destination computer? (y/n)"
        if ($more -ne 'y') { break }

        $newDest = Read-Host "Enter the new destination computer hostname"

        Write-Host "`nTransferring backup to $newDest..."
        if ($usedNewBackup) {
            robocopy "\\$sourceComputer\c$\temp\backup" "\\$newDest\c$\Temp\backup" "backup.dmp.7z" /ETA /E /MT:32
        } else {
            robocopy "\\$sourceComputer\c$\xstoredb\backup" "\\$newDest\c$\Temp\backup" $lastNightBackup /ETA /E /MT:32
        }

        $confirmRestore = Read-Host "Is $newDest ready for restore? (y/n)"
        if ($confirmRestore -eq 'y') {
            Restore-Backup -computerName $newDest
        } else {
            Write-Host "⚠️ Skipping restoration on $newDest." -ForegroundColor Yellow
        }
    }

} catch {
    Write-Host "`n❌ An error occurred: $_" -ForegroundColor Red
}

Write-Host "`n✅ Process complete. Press any key to exit."
Read-Host
