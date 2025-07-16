# Backup and Restore from Working Computer to Fix Broken Computer

# Get source and destination computer hostnames
$sourceComputer = Read-Host "Enter the Source/Working Computer hostname"
$destiComputer = Read-Host "Enter the Broken/Destination Computer hostname"

# Define paths for script and temporary directories
$scriptPath = ".\Scripts\my-oracle-backup.ps1"
$tempDir = "C:\temp"

# Copy the backup script to both computers' temp folders
Copy-Item -Path $scriptPath -Destination "\\$sourceComputer\c$\temp"
Copy-Item -Path $scriptPath -Destination "\\$destiComputer\c$\temp"

try {
    # Prompt user for backup option: new or last night's backup
    $condition = Read-Host "Do you want to copy from last night backup or create a new DB DMP file? `nPress 1 for New DB Backup, or 2 for Last Night DB Backup"

    # Validate user's input
    if ($condition -eq '1') {
        Clear-Host
        Write-host "You have selected to create a new Backup" -ForegroundColor Cyan
        Write-host "Creating backup from $sourceComputer ..." -ForegroundColor Green
        
        # Create a new backup
        Invoke-Command -ComputerName $sourceComputer -ScriptBlock {
		$backupDir = "C:\temp\backup"
		$backupFile = "C:\temp\backup\backup.dmp"
	
		# Ensure backup directory exists
		if (-Not (Test-Path $backupDir)) {
			New-Item -Path $backupDir -ItemType Directory -Force
		}
	
		# Remove existing backup file if found
		if (Test-Path $backupFile) {
			Write-Host "🧹 Removing old backup file..."
			Remove-Item -Path $backupFile -Force
		}

		# Run the backup script
		cd "C:\temp"
		.\my-oracle-backup.ps1 -mode backup -filename backup.dmp
	}


        Start-Sleep -Seconds 3
		$archiveFile = "$backupDir\backup.dmp.7z"

		# Dynamically fetch 7-Zip path from registry
		$sevenZipPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\7-Zip").Path
		if (Test-Path $archiveFile) { Remove-Item $archiveFile -Force }
		# Compress backup using 7-Zip
		& "$sevenZipPath\7z.exe" a -t7z -mx=9 $archiveFile $backupFile

		
        # Transfer compressed archive
		Write-Host "`n📦 Copying zipped backup.dmp.7z from $sourceComputer to $destiComputer..."
		robocopy "\\$sourceComputer\c$\temp\backup" "\\$destiComputer\c$\Temp\backup" "backup.dmp.7z" /ETA /E /MT:32

#### Next is Restore in desination Computer

        # Ask user to confirm before restoring backup
		$restoreConfirm = Read-Host "`nIs $destiComputer ready for restoration? Press 'y' to continue or 'n' to exit"
		if ($restoreConfirm -eq 'y') {
			Write-Host "📦 Extracting backup.dmp.7z on $destiComputer..."
		
			Invoke-Command -ComputerName $destiComputer -ScriptBlock {
				$backupDir = "C:\temp\backup"
				$archiveFile = "$backupDir\backup.dmp.7z"
				$extractPath = $backupDir
				$sevenZipPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\7-Zip").Path
		
				# Extract .7z archive
				& "$sevenZipPath\7z.exe" e -o"$extractPath" -y "$archiveFile"
		
				# Confirm extraction
				if (Test-Path "$backupDir\backup.dmp") {
					Write-Host "✅ backup.dmp extracted successfully."
				} else {
					Write-Host "❌ Extraction failed — backup.dmp not found." -ForegroundColor Red
					exit
				}
			}
		
			Write-Host "🔄 Restoring backup.dmp to $destiComputer..."
			Invoke-Command -ComputerName $destiComputer -ScriptBlock {
				cd "C:\temp"
				.\my-oracle-backup.ps1 -mode restore-force -filename backup.dmp
			}
		} else {
			Write-Host "⏸️ Restoration skipped. You will need to manually restore later." -ForegroundColor Yellow
			exit
		}
    } elseif ($condition -eq '2') {
        Clear-Host
        Write-host "You have selected to use the last night Backup" -ForegroundColor Cyan
        Write-Host "`nCopying xstoredb\backup\xstore.bak.gz file to $destiComputer"
        robocopy "\\$sourceComputer\c$\xstoredb\backup\" "\\$destiComputer\c$\Temp\backup\" xstore.bak.gz /ETA /E /MT:32

        # Ask user to confirm before extracting and restoring backup
        $restoreConfirm = Read-Host "`nIs $destiComputer ready for restoration? Press 'y' to continue or 'n' to exit"
        if ($restoreConfirm -eq 'y') {
            # Extract the .gz file on the destination computer using 7-Zip
            Invoke-Command -ComputerName $destiComputer -ScriptBlock {
                # Retrieve the path to 7-Zip
                $7zipPath = (Get-ItemProperty -Path HKLM:\SOFTWARE\7-Zip).Path
                $zipFile = "C:\temp\backup\xstore.bak.gz"
                $extractPath = "C:\Temp\backup"
            
                # Ensure the extraction directory exists
                if (-Not (Test-Path $extractPath)) {
                    New-Item -Path $extractPath -ItemType Directory -Force
                }

                # Validate the zip file exists
                if (Test-Path $zipFile) {
                    Write-Host "Extracting file from $zipFile to $extractPath..."
                    
                    # Use 7-Zip to extract the file
					### if you want to compress to zip[.7z] use below command
					#& "$7zipPath\7z.exe" a -t7z -mx=9 "$outputArchive.7z" "$sourcePath\*"
                    & "$7zipPath\7z.exe" e -o"$extractPath" -y "$zipFile"

                    # Validate if the extracted file exists
                    $extractedFile = Join-Path -Path $extractPath -ChildPath "xstore.bak"
                    if (Test-Path $extractedFile) {
                        Write-Host "Extraction successful. File located at $extractedFile"
                    } else {
                        Write-Host "Extraction completed, but file not found in $extractPath." -ForegroundColor Red
                    }
                } else {
                    Write-Host "The zip file does not exist at $zipFile." -ForegroundColor Red
                }

                # Restore the extracted backup
                Write-host "Restoring extracted xstore.bak to $destiComputer"
                cd "C:\temp"
                .\my-oracle-backup.ps1 -mode restore-force -filename xstore.bak
                Write-Host "`nDB Restore is completed " -ForegroundColor Green
            }
        } else {
            Write-Host "Restoration skipped. You will need to manually restore later." -ForegroundColor Yellow
            exit
        }
    } else {
        Write-Host "Invalid option selected. Please run the script again and choose 1 or 2." -ForegroundColor Red
        exit
    }

    # Ask user if there is another destination computer for restoration
    while ($true) {
        $additionalDesti = Read-Host "Do you need to restore this backup to another destination computer? Press 'y' for Yes or 'n' for No"
        if ($additionalDesti -eq 'y') {
            $newDestiComputer = Read-Host "Enter the new Destination Computer hostname"
            Write-host "`nCopying backup file to $newDestiComputer"
            robocopy "\\$sourceComputer\c$\temp\backup\" "\\$newDestiComputer\c$\Temp\backup\" backup.dmp /ETA /E /MT:32

            $restoreConfirm = Read-Host "`nIs $newDestiComputer ready for restoration? Press 'y' to continue or 'n' to exit"
            if ($restoreConfirm -eq 'y') {
                Write-host "Restoring backup.dmp to $newDestiComputer"
                Invoke-Command -ComputerName $newDestiComputer -ScriptBlock {
                    cd "C:\temp"
                    .\my-oracle-backup.ps1 -mode restore-force -filename backup.dmp
                }
            } else {
                Write-Host "Restoration skipped for $newDestiComputer. You will need to manually restore later." -ForegroundColor Yellow
            }
        } else {
            break
        }
    }

} catch {
    Write-Host "An error occurred while fetching information " -ForegroundColor Red
    Write-Host "Error Details: $_" -ForegroundColor Yellow
}

Write-host "Process complete. Press any key to exit"
Read-Host
