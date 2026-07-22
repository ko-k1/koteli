& {
	[CmdletBinding()]
	param()

	Set-StrictMode -Version Latest
	$ErrorActionPreference = 'Stop'
	$ProgressPreference = 'SilentlyContinue'

	function Write-Step {
		param([Parameter(Mandatory)][AllowEmptyString()][string] $Message)
		Write-Host $Message
	}

	function Get-KoteliArchitecture {
		$detected = $null
		try {
			$detected = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
		} catch {
			$detected = if ($env:PROCESSOR_ARCHITEW6432) {
				$env:PROCESSOR_ARCHITEW6432
			} else {
				$env:PROCESSOR_ARCHITECTURE
			}
		}

		switch ($detected.ToUpperInvariant()) {
			{ $_ -in @('X64', 'AMD64') } { return 'amd64' }
			{ $_ -in @('ARM64', 'AARCH64') } { return 'aarch64' }
			default { throw "Unsupported CPU architecture: $detected" }
		}
	}

	function Invoke-KoteliDownload {
		param(
			[Parameter(Mandatory)][uri] $Uri,
			[Parameter(Mandatory)][string] $Destination
		)

		Write-Step "Downloading $([IO.Path]::GetFileName($Destination))..."
		$request = @{
			Uri         = $Uri
			OutFile     = $Destination
			ErrorAction = 'Stop'
		}
		if ($PSVersionTable.PSVersion.Major -lt 6) {
			$request['UseBasicParsing'] = $true
		}
		Invoke-WebRequest @request
	}

	function Assert-WindowsExecutable {
		param(
			[Parameter(Mandatory)][string] $Path,
			[Parameter(Mandatory)][string] $Name,
			[Parameter(Mandatory)][string] $Architecture
		)

		$file = Get-Item -LiteralPath $Path
		if ($file.Length -lt 2) {
			throw "$Name is empty. A Windows/$Architecture build may not be published yet."
		}

		$stream = [IO.File]::OpenRead($file.FullName)
		try {
			$first = $stream.ReadByte()
			$second = $stream.ReadByte()
		} finally {
			$stream.Dispose()
		}

		if ($first -ne 0x4d -or $second -ne 0x5a) {
			throw "$Name is not a valid Windows executable. The download may be unavailable or corrupt."
		}
	}

	function Test-PathContains {
		param(
			[AllowNull()][string] $PathValue,
			[Parameter(Mandatory)][string] $Directory
		)

		if ([string]::IsNullOrWhiteSpace($PathValue)) {
			return $false
		}

		$expected = $Directory.Trim().Trim('"').TrimEnd('\')
		foreach ($entry in @($PathValue -split ';')) {
			$expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"')).TrimEnd('\')
			if ([string]::Equals($expanded, $expected, [StringComparison]::OrdinalIgnoreCase)) {
				return $true
			}
		}
		return $false
	}

	function Remove-PathEntry {
		param(
			[AllowNull()][string] $PathValue,
			[Parameter(Mandatory)][string] $Directory
		)

		if ([string]::IsNullOrWhiteSpace($PathValue)) {
			return $PathValue
		}

		$expected = $Directory.Trim().Trim('"').TrimEnd('\')
		$kept = [System.Collections.Generic.List[string]]::new()
		foreach ($entry in @($PathValue -split ';')) {
			if ([string]::IsNullOrWhiteSpace($entry)) {
				continue
			}
			$expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"')).TrimEnd('\')
			if (-not [string]::Equals($expanded, $expected, [StringComparison]::OrdinalIgnoreCase)) {
				$kept.Add($entry)
			}
		}
		return $kept -join ';'
	}

	function Resolve-KoteliAction {
		param(
			[Parameter(Mandatory)][string] $InstallDirectory,
			[Parameter(Mandatory)][string[]] $ManagedNames
		)

		$existing = @(
			$ManagedNames | Where-Object { Test-Path -LiteralPath (Join-Path $InstallDirectory $_) }
		)
		if ($existing.Count -eq 0) {
			return 'install'
		}
		if ($existing.Count -lt $ManagedNames.Count) {
			Write-Step "An incomplete Koteli installation was found in $InstallDirectory."
		}

		if ($env:KOTELI_ACTION) {
			switch ($env:KOTELI_ACTION.ToLowerInvariant()) {
				'update' { return 'update' }
				'repair' { return 'repair' }
				'install' { return 'repair' }
				'uninstall' { return 'uninstall' }
				'cancel' { return 'cancel' }
				default {
					throw "Invalid KOTELI_ACTION '$env:KOTELI_ACTION'. Use update, repair, uninstall, or cancel."
				}
			}
		}

		while ($true) {
			Write-Step ''
			Write-Step "Koteli is already installed in $InstallDirectory."
			Write-Step '  1) Update'
			Write-Step '  2) Repair'
			Write-Step '  3) Uninstall'
			Write-Step '  4) Cancel'
			try {
				$choice = Read-Host 'Choose an action [1-4]'
			} catch {
				throw 'Could not read a menu choice. Set KOTELI_ACTION to update, repair, uninstall, or cancel.'
			}
			switch ($choice) {
				{ $_ -in @('1', 'update') } { return 'update' }
				{ $_ -in @('2', 'repair') } { return 'repair' }
				{ $_ -in @('3', 'uninstall') } { return 'uninstall' }
				{ $_ -in @('', '4', 'cancel') } { return 'cancel' }
				default { Write-Warning "Invalid choice: $choice" }
			}
		}
	}

	function Get-KoteliConfigDirectory {
		$base = if ($env:LOCALAPPDATA) {
			$env:LOCALAPPDATA
		} elseif ($env:APPDATA) {
			$env:APPDATA
		} else {
			Join-Path ([IO.Path]::GetTempPath()) 'kxai-tui'
		}
		if ($env:LOCALAPPDATA -or $env:APPDATA) {
			return Join-Path (Join-Path (Join-Path $base 'kxai') 'tui') '.kxai'
		}
		return Join-Path $base '.kxai'
	}

	function Confirm-ConfigRemoval {
		param([Parameter(Mandatory)][string] $ConfigDirectory)

		if ($env:KOTELI_REMOVE_CONFIG) {
			switch ($env:KOTELI_REMOVE_CONFIG.ToLowerInvariant()) {
				{ $_ -in @('1', 'true', 'y', 'yes') } { return $true }
				{ $_ -in @('0', 'false', 'n', 'no') } { return $false }
				default { throw "Invalid KOTELI_REMOVE_CONFIG '$env:KOTELI_REMOVE_CONFIG'. Use yes or no." }
			}
		}

		# An explicitly selected action is commonly used in non-interactive installs.
		if ($env:KOTELI_ACTION) {
			return $false
		}

		try {
			$answer = Read-Host "Also remove Koteli user configuration and state at '$ConfigDirectory'? [y/N]"
		} catch {
			return $false
		}
		return $answer -match '^(y|yes)$'
	}

	function Uninstall-Koteli {
		param(
			[Parameter(Mandatory)][string] $InstallDirectory,
			[Parameter(Mandatory)][string[]] $ManagedNames,
			[Parameter(Mandatory)][string] $ConfigDirectory
		)

		$pathMarker = Join-Path $InstallDirectory '.koteli-path-added'
		foreach ($name in $ManagedNames) {
			$managedPath = Join-Path $InstallDirectory $name
			if (Test-Path -LiteralPath $managedPath) {
				Remove-Item -LiteralPath $managedPath -Force
			}
		}

		if (Test-Path -LiteralPath $pathMarker) {
			$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
			$newUserPath = Remove-PathEntry -PathValue $userPath -Directory $InstallDirectory
			[Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
			$env:Path = Remove-PathEntry -PathValue $env:Path -Directory $InstallDirectory
			Remove-Item -LiteralPath $pathMarker -Force
		}

		if ((Test-Path -LiteralPath $InstallDirectory) -and
			@(Get-ChildItem -LiteralPath $InstallDirectory -Force).Count -eq 0) {
			Remove-Item -LiteralPath $InstallDirectory -Force
		}

		$removeConfig = Confirm-ConfigRemoval -ConfigDirectory $ConfigDirectory
		if ($removeConfig) {
			if (Test-Path -LiteralPath $ConfigDirectory) {
				$resolvedConfig = [IO.Path]::GetFullPath($ConfigDirectory)
				$configLeaf = Split-Path $resolvedConfig -Leaf
				$configParent = Split-Path (Split-Path $resolvedConfig -Parent) -Leaf
				if ($configLeaf -ne '.kxai' -or $configParent -notin @('tui', 'kxai-tui')) {
					throw "Refusing to remove unexpected configuration path: $resolvedConfig"
				}
				Remove-Item -LiteralPath $resolvedConfig -Recurse -Force
				Write-Step "Removed user configuration and state from $resolvedConfig."
			} else {
				Write-Step 'No Koteli user configuration or state was found.'
			}
		} elseif (Test-Path -LiteralPath $ConfigDirectory) {
			Write-Step "Preserved user configuration and state in $ConfigDirectory."
		}
		Write-Step "Koteli was uninstalled from $InstallDirectory."
		Write-Step 'Project-local .kxai and .koteli directories were preserved.'
	}

	$runningOnWindows = $false
	try {
		$runningOnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
			[System.Runtime.InteropServices.OSPlatform]::Windows
		)
	} catch {
		$runningOnWindows = $env:OS -eq 'Windows_NT'
	}
	if (-not $runningOnWindows) {
		throw 'install.ps1 only supports Windows. Use install.sh on Linux or macOS.'
	}

	$installDirectory = if ($env:KOTELI_INSTALL_DIR) {
		$env:KOTELI_INSTALL_DIR
	} elseif ($env:LOCALAPPDATA) {
		Join-Path $env:LOCALAPPDATA 'Programs\Koteli\bin'
	} else {
		Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData\Local\Programs\Koteli\bin'
	}
	$installDirectory = [IO.Path]::GetFullPath($installDirectory)
	$binaries = @('koteli.exe', 'kxaid.exe')
	$managedNames = @($binaries)
	$configDirectory = Get-KoteliConfigDirectory
	$action = Resolve-KoteliAction -InstallDirectory $installDirectory -ManagedNames $managedNames

	switch ($action) {
		'uninstall' {
			Uninstall-Koteli -InstallDirectory $installDirectory -ManagedNames $managedNames `
				-ConfigDirectory $configDirectory
			return
		}
		'cancel' {
			Write-Step 'No changes were made.'
			return
		}
		'repair' { Write-Step "Repairing Koteli in $installDirectory..." }
		'update' { Write-Step "Updating Koteli in $installDirectory..." }
	}

	if ([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12) {
		# TLS 1.2 is already enabled.
	} else {
		[Net.ServicePointManager]::SecurityProtocol =
			[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
	}

	$architecture = Get-KoteliArchitecture
	$repository = if ($env:KOTELI_REPOSITORY) { $env:KOTELI_REPOSITORY.Trim('/') } else { 'ko-k1/koteli' }
	$ref = if ($env:KOTELI_REF) { $env:KOTELI_REF } else { 'main' }
	$downloadBase = if ($env:KOTELI_DOWNLOAD_BASE) {
		$env:KOTELI_DOWNLOAD_BASE.TrimEnd('/')
	} else {
		"https://raw.githubusercontent.com/$repository/$ref"
	}

	$tempDirectory = Join-Path ([IO.Path]::GetTempPath()) ("koteli-install-{0}" -f [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null

	try {
		foreach ($binary in $binaries) {
			$uri = [uri] "$downloadBase/$architecture/win/$binary"
			$temporaryPath = Join-Path $tempDirectory $binary
			try {
				Invoke-KoteliDownload -Uri $uri -Destination $temporaryPath
			} catch {
				throw "Could not download $uri. A Windows/$architecture build may not be published yet. $($_.Exception.Message)"
			}
			Assert-WindowsExecutable -Path $temporaryPath -Name $binary -Architecture $architecture
		}

		New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
		foreach ($binary in $binaries) {
			Copy-Item -LiteralPath (Join-Path $tempDirectory $binary) `
				-Destination (Join-Path $installDirectory $binary) -Force
		}

		$pathMarker = Join-Path $installDirectory '.koteli-path-added'
		if ($env:KOTELI_NO_PATH_UPDATE -ne '1') {
			$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
			if (-not (Test-PathContains -PathValue $userPath -Directory $installDirectory)) {
				$newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
					$installDirectory
				} else {
					"$userPath;$installDirectory"
				}
				[Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
				Set-Content -LiteralPath $pathMarker -Value 'Added by the Koteli installer.' -Encoding Ascii
			}
			if (-not (Test-PathContains -PathValue $env:Path -Directory $installDirectory)) {
				$env:Path = "$installDirectory;$env:Path"
			}
		}

		Write-Step ''
		$result = switch ($action) {
			'install' { 'installed' }
			'repair' { 'repaired' }
			'update' { 'updated' }
		}
		Write-Step "Koteli was $result in $installDirectory."
		Write-Step ''
		Write-Step 'Start the daemon in one terminal:'
		Write-Step '  kxaid'
		Write-Step 'Then start Koteli in another terminal:'
		Write-Step '  koteli'
		Write-Step ''
		if ($env:KOTELI_NO_PATH_UPDATE -eq '1') {
			Write-Step "PATH was not changed. Add $installDirectory to PATH to use these commands."
		} else {
			Write-Step 'If a new terminal cannot find these commands, sign out and back in to refresh PATH.'
		}
	} finally {
		if (Test-Path -LiteralPath $tempDirectory) {
			Remove-Item -LiteralPath $tempDirectory -Recurse -Force
		}
	}
}
