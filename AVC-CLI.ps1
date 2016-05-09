[CmdletBinding()]
Param (
	[Parameter(Mandatory=$False)]
	[switch]$DisplayJSONErrors,
	[switch]$Download,
	[switch]$StartKSP,
	
	[ValidateScript({ Test-Path $_ -PathType Container })]
	[string]$DownloadPath = (Get-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders").GetValue("{374DE290-123F-4565-9164-39C4925E467B}")
)



function Compare-KSPAddOns {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$True, ValueFromPipeline=$true)]
		[PSObject[]]$InstalledAddons
	)

	begin {
		$UpdateCount = 0
	}

	process {
		ForEach ($InstalledAddon in $InstalledAddons) {
			$JSONERROR = $False
			write-host "Checking: $($InstalledAddon.Name)"

			# Lots of addons have broken json files, try to fix those.
			# Also change github links to raw content, I may regret this later.
			try {
				$LocalJSON = Get-Content -literalPath $InstalledAddon -Raw | Update-BrokenJSON | Update-GitHubLinks
				$InstalledAddon_AVC = $LocalJSON | ConvertFrom-Json -ErrorAction SilentlyContinue
			}
			catch {
				write-host -foreground red "Error: $($InstalledAddon.Name)"
				if ($DisplayJSONErrors) {
					write-host -foreground red "Error: $($_.Exception.Message)"
					write-host -foreground red "$LocalJSON"
				}
				$JSONERROR = $True
			}

			# Try the URL's to get the latest version's JSON, and fix it if it's broken.
			# Don't change this to github raw links.
			try {
				$WebJSON = Invoke-WebRequest -Uri ($InstalledAddon_AVC.url) | Update-BrokenJSON
				$InternetAddon_AVC  = $WebJSON | ConvertFrom-Json -ErrorAction SilentlyContinue
			}
			catch {
				write-host -foreground red "Error: $($InstalledAddon_AVC.url)"
				if ($DisplayJSONErrors) {
					write-host -foreground red "Error: $($_.Exception.Message)"
					write-host -foreground red "$WebJSON"
				}
				$JSONERROR = $True
			}

			# If we didn't get a JSON loading error for either the local, or the internet, then lets proceed.
			if (-not $JSONERROR) {
				# Add build numbers of 0 if they don't have build numbers.
				# This is just to make comparing them work easier.
				if (-not (Get-Member -inputobject $InstalledAddon_AVC.Version -name "Build" -Membertype Properties)) {
					$InstalledAddon_AVC.Version = $InstalledAddon_AVC.Version | Add-Member @{Build = 0} -PassThru
				}
				if (-not (Get-Member -inputobject $InternetAddon_AVC.Version -name "Build" -Membertype Properties)) {
					$InternetAddon_AVC.Version = $InternetAddon_AVC.Version | Add-Member @{Build = 0} -PassThru
				}

				# Compare the versions.
				$Update = $False
				$InstalledVersion = [version]"$($InstalledAddon_AVC.Version.Major).$($InstalledAddon_AVC.Version.Minor).$($InstalledAddon_AVC.Version.Patch).$($InstalledAddon_AVC.Version.Build)"
				$InternetVersion  = [version]"$($InternetAddon_AVC.Version.Major).$($InternetAddon_AVC.Version.Minor).$($InternetAddon_AVC.Version.Patch).$($InternetAddon_AVC.Version.Build)"
				$Update = $InstalledVersion -lt $InternetVersion


				if ($Update) {
					$UpdateCount += 1
					Write-Host -foreground yellow "Out of Date: $($InstalledAddon_AVC.Name)"
					Write-Host -foreground yellow "Installed Version: $InstalledVersion"
					Write-Host -foreground yellow "Latest Version: $InternetVersion"
					if ($Download) {
						Get-KSPAddon -AVC $InternetAddon_AVC
					} else {
						Write-Host -foreground yellow "Download Latest: $($InternetAddon_AVC.Download)"
					}
					Write-Host ""
				}
			}
			$InstalledAddon = $Null
			$WebJSON = $Null
			$LocalJSON = $Null
		}
	}

	end {
	}
}


# Fix simple broken JSON layout issues.
function Update-BrokenJSON {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$True, ValueFromPipeline=$true)]
		[string]$JSON
	)

	begin {
	}

	process {
		$JSON = $JSON -replace [regex]":\s*true", ": `"true`""
		$JSON = $JSON -replace [regex]":\s*false", ": `"false`""
		$JSON = $JSON -replace ":`n", ":"
		$JSON = $JSON -replace ":`r`n", ":"
		$JSON = $JSON -replace [regex]"\r\n\s+", ""
		$JSON = $JSON -replace "`r", ""
		$JSON = $JSON -replace "`n", ""
		$JSON = $JSON -replace "`t", ""

		$JSON = $JSON -replace [regex]",\s*}", "}"
		$JSON = $JSON -replace "},}", "}}"
		$JSON = $JSON -replace "}`"", "},`""
		$JSON = $JSON -replace "`"`"", "`",`""
		

		#$JSON = $JSON -replace ",{", "{"
	}

	end {
		write-output $JSON
	}
}

# Update github.com links to raw.githubusercontent.com
function Update-GitHubLinks {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$True, ValueFromPipeline=$true)]
		[string]$JSON
	)

	begin {
	}

	process {
		$JSON = $JSON -replace "http://github.com", "https://raw.githubusercontent.com"
		$JSON = $JSON -replace "github.com", "raw.githubusercontent.com"
		$JSON = $JSON -replace "/blob/", "/"
	}

	end {
		write-output $JSON
	}
}

# Download an addon.
function Get-KSPAddon {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$True, ValueFromPipeline=$true)]
		[PSObject]$AVC
	)

	begin {
		$TryDownload = $False
	}

	process {
		$URI = $($AVC.Download)

		$OutFile = $AVC.Name | Remove-InvalidFileNameChars
		$OutFile = "$DownloadPath\$($OutFile)"

		if ($URI -ne $Null) {
			if ($URI.contains("spacedock.info")) {
				$APIURI = $URI -replace [regex]"https*:\/\/spacedock.info\/", "https://spacedock.info/api/"
				$APIURI = $APIURI -replace [regex]"\/mod\/([\d]*).*", '/mod/${1}/latest'
				$SpaceDockJSON = Invoke-WebRequest -Uri $APIURI | ConvertFrom-Json
				$URI = "https://spacedock.info$($SpaceDockJSON.download_path)"
				$OutFile = "$($OutFile)-$($SpaceDockJSON.friendly_version)"
				$TryDownload = $True
			}

			if ($URI.contains("kerbalstuff.com")) {
				Write-Host -foreground yellow "Kerbalstuff.com is dead, searching spackdock.info."
				$SearchResults = Search-SpaceDock -SearchString $($AVC.Name)
				if ($SearchResults) {
					$TryDownload = $($SearchResults.TryDownload)
					$URI = $($SearchResults.URI)
					$OutFile = "$($OutFile)-$($SearchResults.friendly_version)"
				}
			}

			if ($URI.contains("curseforge.com")) {
				$OutFile = "$($OutFile)-$($AVC.Version.Major).$($AVC.Version.Minor).$($AVC.Version.Patch)"
				if (Get-Member -inputobject $AVC.Version -name "Build" -Membertype Properties) {
					if ($AVC.Version.Build -ne 0) {
						$OutFile = "$OutFile-$($AVC.Version.Build)"
					}
				}
				$URI = "$URI/files/latest"
				$TryDownload = $True
			}

			$OutFile = "$($OutFile).zip"

			if ($TryDownload) {
				write-host -foreground green "Downloading: $URI"
				Invoke-WebRequest -Uri $URI -OutFile $OutFile
				write-host -foreground green "Saved to $OutFile"
			} else {
				write-host -foreground red "Can only download from Spacedock.info currently, sorry!"
				write-host -foreground yellow "$URI"
			}
		} else {
			write-host -foreground red "Addon has no download url available via the version file."
		}
	}

	end {
	}
}


Function Remove-InvalidFileNameChars {
	param(
		[Parameter(Mandatory=$true,	Position=0,	ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
		[String]$Name
	)

	$invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
	$re = "[{0}]" -f [RegEx]::Escape($invalidChars)
	Write-Output ($Name -replace $re)
}


function Search-SpaceDock {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$True, ValueFromPipeline=$true)]
		[String]$SearchString
	)

	begin {
		$Output = @()
	}

	process {
		$SearchURI = "https://spacedock.info/api/search/mod?query=" + $($SearchString)
		$SearchResults = Invoke-WebRequest -Uri $SearchURI | ConvertFrom-Json
		$SearchResults = $SearchResults | Where-Object { $_.Name -contains "$($SearchString)" }

		if (-not ($SearchResults)) {
			$SearchURI = "https://spacedock.info/api/search/mod?query='$($SearchString)'"
			$SearchResults = Invoke-WebRequest -Uri $SearchURI | ConvertFrom-Json
			$SearchResults = $SearchResults | Where-Object { $_.Name -contains "$($SearchString)" }		
		}

		ForEach($SearchResult in $SearchResults) {
			Write-Host -foreground yellow "Do you want to download this, $($SearchResult.Name) from the search results?"
			do { $answer = Read-Host "y or n" } 
			until ("y","n" -ccontains $answer)

			if ($Answer.tolower() -eq "y") {
				$Props = @{
					TryDownload = $True
					URI = "https://spacedock.info$($SearchResult.versions[0].download_path)"
					friendly_version = $($SearchResult.versions[0].friendly_version)
				}
				$Output += new-object psobject -Property $Props
			}
		}
	}

	end {
		write-output $Output
	}
}


write-verbose "Finding KSP"
$KSPInstallLocation = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 220200").InstallLocation

write-verbose "Finding Addons with a version file."
$InstalledAddons = Get-ChildItem -Path $KSPInstallLocation\GameData -Include *.version -Recurse

Compare-KSPAddOns -InstalledAddon $InstalledAddons

if ($StartKSP) {
	if ((Get-WmiObject Win32_OperatingSystem | select OSArchitecture).OSArchitecture -eq "64-bit") {
		$KSPEXE = "KSP_x64.exe"
	} else {
		$KSPEXE = "KSP.exe"
	}
	
	start-process -FilePath $KSPInstallLocation\$KSPEXE
}
