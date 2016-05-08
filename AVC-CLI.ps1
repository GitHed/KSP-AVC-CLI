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
	}

	process {
		ForEach ($InstalledAddon in $InstalledAddons) {
			$JSONERROR = $False
			write-host "Checking: $($InstalledAddon.Name)"
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
			if (-not $JSONERROR) {
				#Build Numbers
				if (-not (Get-Member -inputobject $InstalledAddon_AVC.Version -name "Build" -Membertype Properties)) {
					$InstalledAddon_AVC.Version = $InstalledAddon_AVC.Version | Add-Member @{Build = 0} -PassThru
				}
				if (-not (Get-Member -inputobject $InternetAddon_AVC.Version -name "Build" -Membertype Properties)) {
					$InternetAddon_AVC.Version = $InternetAddon_AVC.Version | Add-Member @{Build = 0} -PassThru
				}

				$Update = $False
				$InstalledVersion = [version]"$($InstalledAddon_AVC.Version.Major).$($InstalledAddon_AVC.Version.Minor).$($InstalledAddon_AVC.Version.Patch).$($InstalledAddon_AVC.Version.Build)"
				$InternetVersion  = [version]"$($InternetAddon_AVC.Version.Major).$($InternetAddon_AVC.Version.Minor).$($InternetAddon_AVC.Version.Patch).$($InternetAddon_AVC.Version.Build)"
				$Update = $InstalledVersion -lt $InternetVersion


				if ($Update) {
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

function Get-KSPAddon {
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory=$True, ValueFromPipeline=$true)]
		[PSObject]$AVC
	)

	begin {
	}

	process {
		$URI = $($AVC.Download)
		if ($URI -match "spacedock.info") {
			$URI = "$URI/download/$($AVC.Version.Major).$($AVC.Version.Minor).$($AVC.Version.Patch)"
			$OutFile = "$DownloadPath\$($AVC.Name)-$($AVC.Version.Major).$($AVC.Version.Minor).$($AVC.Version.Patch)"

			if (Get-Member -inputobject $AVC.Version -name "Build" -Membertype Properties) {
				if ($AVC.Version.Build -ne 0) {
					$OutFile = "$OutFile-$($AVC.Version.Build)"
					$URI = "$URI-$($AVC.Version.Build)"
				}
			}
			$OutFile = "$OutFile.zip"
		}

		write-host -foreground green "Downloading: $URI"
		Invoke-WebRequest -Uri $URI -OutFile $OutFile
		write-host -foreground green "Saved to $OutFile"
	}

	end {
	}
}



write-verbose "Finding KSP"
$KSPInstallLocation = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 220200").InstallLocation

write-verbose "Finding Addons with a version file."
$InstalledAddons = Get-ChildItem -Path $KSPInstallLocation\GameData -Include *.version -Recurse

Compare-KSPAddOns -InstalledAddon $InstalledAddons

if ($StartKSP) {
	if (Get-WmiObject Win32_OperatingSystem  | select OSArchitecture -eq "64-bit") {
		$KSPEXE = "KSP_x64.exe"
	} else {
		$KSPEXE = "KSP.exe"
	}
	
	start-process -FilePath $KSPInstallLocation\$KSPEXE
}
