& {
	[CmdletBinding()]
	param()

	Set-StrictMode -Version Latest
	$ErrorActionPreference = 'Stop'
	$ProgressPreference = 'SilentlyContinue'

	$script:KoteliRich = $false
	$script:KoteliUnicode = $false
	$script:KoteliActiveStage = ''
	$script:KoteliActiveDetail = ''
	$script:KoteliReset = ''
	$script:KoteliBold = ''
	$script:KoteliCyan = ''
	$script:KoteliPurple = ''
	$script:KoteliGreen = ''
	$script:KoteliAmber = ''
	$script:KoteliRed = ''
	$script:KoteliMuted = ''
	$script:KoteliErase = ''
	$script:KoteliBrandMark = '*'
	$script:KoteliActiveMark = '>'
	$script:KoteliOkMark = '+'
	$script:KoteliSeparator = '-'
	$script:KoteliArrow = '->'

	function Initialize-KoteliUi {
		$allowRich = $false
		try {
			$allowRich =
				-not [Console]::IsOutputRedirected -and
				-not [Console]::IsErrorRedirected -and
				[string]::IsNullOrEmpty($env:CI) -and
				$env:TERM -ne 'dumb' -and
				-not (Test-Path Env:NO_COLOR)

			if ($allowRich) {
				# Accessing the console handle is an intentional capability check.
				$null = [Console]::WindowWidth
			}
		} catch {
			$allowRich = $false
		}

		if (-not $allowRich) {
			return
		}

		$script:KoteliRich = $true
		$escapeCharacter = [string][char]27
		$script:KoteliReset = "$escapeCharacter[0m"
		$script:KoteliBold = "$escapeCharacter[1m"
		$script:KoteliCyan = "$escapeCharacter[36m"
		$script:KoteliPurple = "$escapeCharacter[35m"
		$script:KoteliGreen = "$escapeCharacter[32m"
		$script:KoteliAmber = "$escapeCharacter[33m"
		$script:KoteliRed = "$escapeCharacter[31m"
		$script:KoteliMuted = "$escapeCharacter[90m"
		$script:KoteliErase = "$escapeCharacter[2K"

		try {
			$script:KoteliUnicode = [Console]::OutputEncoding.CodePage -eq 65001
		} catch {
			$script:KoteliUnicode = $false
		}
		if ($script:KoteliUnicode) {
			$script:KoteliBrandMark = [string][char]0x25C6
			$script:KoteliActiveMark = [string][char]0x25C7
			$script:KoteliOkMark = [string][char]0x2713
			$script:KoteliSeparator = [string][char]0x00B7
			$script:KoteliArrow = [string][char]0x2192
		}
	}

	function Write-KoteliHeader {
		if ($script:KoteliRich) {
			[Console]::Out.WriteLine(
				"$($script:KoteliCyan)$($script:KoteliBrandMark)$($script:KoteliReset) " +
				"$($script:KoteliBold)$($script:KoteliPurple)Koteli$($script:KoteliReset)"
			)
		} else {
			[Console]::Out.WriteLine('== Koteli ==')
		}
	}

	function Write-KoteliDetail {
		param(
			[Parameter(Mandatory)][string] $Label,
			[Parameter(Mandatory)][AllowEmptyString()][string] $Value
		)
		if ($script:KoteliRich) {
			[Console]::Out.WriteLine(
				"$($script:KoteliMuted)$Label`:$($script:KoteliReset) $Value"
			)
		} else {
			[Console]::Out.WriteLine("[info] $Label`: $Value")
		}
	}

	function Start-KoteliStage {
		param(
			[Parameter(Mandatory)][string] $Stage,
			[Parameter(Mandatory)][string] $Detail
		)
		$script:KoteliActiveStage = $Stage
		$script:KoteliActiveDetail = $Detail
		if ($script:KoteliRich) {
			[Console]::Out.Write(
				"$($script:KoteliCyan)$($script:KoteliActiveMark)$($script:KoteliReset) " +
				"$Stage $($script:KoteliSeparator) $Detail"
			)
			[Console]::Out.Flush()
		} else {
			[Console]::Out.WriteLine("[start] $Stage - $Detail")
		}
	}

	function Complete-KoteliStage {
		param([Parameter(Mandatory)][string] $Detail)
		if ($script:KoteliRich) {
			[Console]::Out.WriteLine(
				"`r$($script:KoteliErase)$($script:KoteliGreen)$($script:KoteliOkMark)" +
				"$($script:KoteliReset) $($script:KoteliActiveStage) " +
				"$($script:KoteliSeparator) $Detail"
			)
		} else {
			[Console]::Out.WriteLine("[ok] $($script:KoteliActiveStage) - $Detail")
		}
		$script:KoteliActiveStage = ''
		$script:KoteliActiveDetail = ''
	}

	function Fail-KoteliStage {
		param([Parameter(Mandatory)][string] $Message)
		if ($script:KoteliRich) {
			[Console]::Error.WriteLine(
				"`r$($script:KoteliErase)$($script:KoteliRed)x$($script:KoteliReset) " +
				"$($script:KoteliActiveStage) $($script:KoteliSeparator) $Message"
			)
		} else {
			[Console]::Error.WriteLine("[error] $($script:KoteliActiveStage) - $Message")
		}
		$script:KoteliActiveStage = ''
		$script:KoteliActiveDetail = ''
	}

	function Write-KoteliStatus {
		param(
			[Parameter(Mandatory)][ValidateSet('ok', 'warn', 'error', 'info')][string] $Kind,
			[Parameter(Mandatory)][string] $Label,
			[Parameter(Mandatory)][string] $Detail
		)
		if ($script:KoteliRich) {
			switch ($Kind) {
				'ok' {
					$color = $script:KoteliGreen
					$mark = $script:KoteliOkMark
				}
				'warn' {
					$color = $script:KoteliAmber
					$mark = '!'
				}
				'error' {
					$color = $script:KoteliRed
					$mark = 'x'
				}
				default {
					$color = $script:KoteliMuted
					$mark = '-'
				}
			}
			[Console]::Out.WriteLine(
				"$color$mark$($script:KoteliReset) $Label " +
				"$($script:KoteliSeparator) $Detail"
			)
		} else {
			[Console]::Out.WriteLine("[$Kind] $Label - $Detail")
		}
	}

	function Write-KoteliError {
		param([Parameter(Mandatory)][string] $Message)
		if ($script:KoteliRich) {
			[Console]::Error.WriteLine(
				"$($script:KoteliRed)x$($script:KoteliReset) $Message"
			)
		} else {
			[Console]::Error.WriteLine("[error] $Message")
		}
	}

	function Write-KoteliReceipt {
		param(
			[Parameter(Mandatory)][string] $Label,
			[Parameter(Mandatory)][AllowEmptyString()][string] $Value
		)
		if ($script:KoteliRich) {
			[Console]::Out.WriteLine(
				"$($script:KoteliGreen)$($script:KoteliOkMark)$($script:KoteliReset) " +
				"$Label`: $Value"
			)
		} else {
			[Console]::Out.WriteLine("[result] $Label`: $Value")
		}
	}

	function Write-KoteliNext {
		param(
			[Parameter(Mandatory)][string] $Label,
			[Parameter(Mandatory)][string] $Value
		)
		if ($script:KoteliRich) {
			[Console]::Out.WriteLine(
				"$($script:KoteliCyan)>$($script:KoteliReset) $Label`: $Value"
			)
		} else {
			[Console]::Out.WriteLine("[next] $Label`: $Value")
		}
	}

	function Get-KoteliArchitecture {
		$detectedArchitecture = $null
		try {
			$detectedArchitecture =
				[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
		} catch {
			$detectedArchitecture = if ($env:PROCESSOR_ARCHITEW6432) {
				$env:PROCESSOR_ARCHITEW6432
			} else {
				$env:PROCESSOR_ARCHITECTURE
			}
		}

		switch ($detectedArchitecture.ToUpperInvariant()) {
			{ $_ -in @('X64', 'AMD64') } { return 'amd64' }
			{ $_ -in @('ARM64', 'AARCH64') } { return 'aarch64' }
			default { throw "Unsupported CPU architecture: $detectedArchitecture" }
		}
	}

	function Test-KoteliManagedPath {
		param([Parameter(Mandatory)][string] $Path)
		try {
			$item = Get-Item -LiteralPath $Path -Force
			return -not $item.PSIsContainer
		} catch {
			return $false
		}
	}

	function Get-KoteliConfigDirectory {
		$baseDirectory = if ($env:LOCALAPPDATA) {
			$env:LOCALAPPDATA
		} elseif ($env:APPDATA) {
			$env:APPDATA
		} else {
			Join-Path ([IO.Path]::GetTempPath()) 'kxai-tui'
		}
		if ($env:LOCALAPPDATA -or $env:APPDATA) {
			return Join-Path (Join-Path (Join-Path $baseDirectory 'kxai') 'tui') '.kxai'
		}
		return Join-Path $baseDirectory '.kxai'
	}

	function Test-PathContains {
		param(
			[AllowNull()][string] $PathValue,
			[Parameter(Mandatory)][string] $Directory
		)

		if ([string]::IsNullOrWhiteSpace($PathValue)) {
			return $false
		}

		$expectedDirectory = $Directory.Trim().Trim('"').TrimEnd('\')
		foreach ($entry in @($PathValue -split ';')) {
			$expandedEntry =
				[Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"')).TrimEnd('\')
			if ([string]::Equals(
				$expandedEntry,
				$expectedDirectory,
				[StringComparison]::OrdinalIgnoreCase
			)) {
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

		$expectedDirectory = $Directory.Trim().Trim('"').TrimEnd('\')
		$keptEntries = New-Object 'System.Collections.Generic.List[string]'
		foreach ($entry in @($PathValue -split ';')) {
			if ([string]::IsNullOrWhiteSpace($entry)) {
				continue
			}
			$expandedEntry =
				[Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"')).TrimEnd('\')
			if (-not [string]::Equals(
				$expandedEntry,
				$expectedDirectory,
				[StringComparison]::OrdinalIgnoreCase
			)) {
				$keptEntries.Add($entry)
			}
		}
		return $keptEntries -join ';'
	}

	function Get-KoteliUserPath {
		if ([AppDomain]::CurrentDomain.GetData(
			'KoteliInstaller.UseInMemoryUserPath'
		)) {
			return [AppDomain]::CurrentDomain.GetData(
				'KoteliInstaller.InMemoryUserPath'
			)
		}
		return [Environment]::GetEnvironmentVariable('Path', 'User')
	}

	function Set-KoteliUserPath {
		param([AllowNull()][string] $Value)
		if ([AppDomain]::CurrentDomain.GetData(
			'KoteliInstaller.UseInMemoryUserPath'
		)) {
			[AppDomain]::CurrentDomain.SetData(
				'KoteliInstaller.InMemoryUserPath',
				$Value
			)
			return
		}
		[Environment]::SetEnvironmentVariable('Path', $Value, 'User')
	}

	function Invoke-KoteliDownload {
		param(
			[Parameter(Mandatory)][uri] $Uri,
			[Parameter(Mandatory)][string] $Destination
		)

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
			$firstByte = $stream.ReadByte()
			$secondByte = $stream.ReadByte()
		} finally {
			$stream.Dispose()
		}

		if ($firstByte -ne 0x4d -or $secondByte -ne 0x5a) {
			throw "$Name is not a valid Windows executable. The download may be unavailable or corrupt."
		}
	}

	function Get-KoteliActionName {
		param([Parameter(Mandatory)][string] $Action)
		switch ($Action) {
			'update' { return 'Update' }
			'repair' { return 'Repair' }
			'uninstall' { return 'Uninstall' }
			default { return 'Cancel' }
		}
	}

	function Get-KoteliMenuLine {
		param(
			[Parameter(Mandatory)][ValidateRange(0, 3)][int] $Index,
			[Parameter(Mandatory)][ValidateRange(0, 3)][int] $Selected
		)
		$title = @('Update', 'Repair', 'Uninstall', 'Cancel')[$Index]
		$description = @(
			'refresh both binaries',
			'reinstall both binaries',
			'remove binaries; state separate',
			'make no changes'
		)[$Index]
		if ($Index -eq $Selected) {
			return (
				"$($script:KoteliBold)$($script:KoteliCyan)> [ {0,-9} ]" +
				"$($script:KoteliReset) {1}" -f $title, $description
			)
		}
		return ('  [ {0,-9} ] {1}' -f $title, $description)
	}

	function Write-KoteliButtonRows {
		param(
			[Parameter(Mandatory)][ValidateRange(0, 3)][int] $Selected,
			[Parameter(Mandatory)][bool] $Redraw,
			[int] $MenuTop = 0
		)
		if ($Redraw) {
			[Console]::SetCursorPosition(0, $MenuTop)
		}
		for ($row = 0; $row -lt 4; $row++) {
			$line = Get-KoteliMenuLine -Index $row -Selected $Selected
			if ($Redraw) {
				[Console]::Out.Write($script:KoteliErase)
			}
			[Console]::Out.WriteLine($line)
		}
	}

	function Read-KoteliNumberedAction {
		while ($true) {
			[Console]::Out.WriteLine('  1) Update    - refresh both binaries')
			[Console]::Out.WriteLine('  2) Repair    - reinstall both binaries')
			[Console]::Out.WriteLine(
				'  3) Uninstall - remove binaries; configuration is handled separately'
			)
			[Console]::Out.WriteLine('  4) Cancel    - make no changes')
			try {
				$choice = Read-Host 'Choose an action [1-4] (default 4)'
			} catch {
				throw (
					'Could not read a menu choice. Set KOTELI_ACTION to update, repair, ' +
					'uninstall, or cancel.'
				)
			}
			if ($null -eq $choice) {
				$choice = ''
			}
			switch ($choice.ToLowerInvariant()) {
				'1' {
					$selectedAction = 'update'
				}
				'update' {
					$selectedAction = 'update'
				}
				'2' {
					$selectedAction = 'repair'
				}
				'repair' {
					$selectedAction = 'repair'
				}
				'3' {
					$selectedAction = 'uninstall'
				}
				'uninstall' {
					$selectedAction = 'uninstall'
				}
				'' {
					$selectedAction = 'cancel'
				}
				'4' {
					$selectedAction = 'cancel'
				}
				'cancel' {
					$selectedAction = 'cancel'
				}
				default {
					Write-KoteliStatus -Kind warn -Label 'Menu' -Detail "invalid choice: $choice"
					continue
				}
			}
			break
		}
		[Console]::Out.WriteLine("Selected: $(Get-KoteliActionName -Action $selectedAction)")
		return $selectedAction
	}

	function Read-KoteliButtonAction {
		param([Parameter(Mandatory)][ValidateRange(0, 3)][int] $DefaultSelection)

		try {
			if ([Console]::IsInputRedirected -or [Console]::WindowWidth -lt 48) {
				return Read-KoteliNumberedAction
			}

			$null = [Console]::CursorTop
			[Console]::Out.WriteLine(
				"$($script:KoteliMuted)Use Up/Down, Enter, Esc, or 1-4." +
				$script:KoteliReset
			)
			Write-KoteliButtonRows -Selected $DefaultSelection -Redraw $false
			$menuEnd = [Console]::CursorTop
			$menuTop = $menuEnd - 4
			if ($menuTop -lt 0) {
				throw 'Could not determine the menu cursor position.'
			}

			$selected = $DefaultSelection
			$confirmed = $false
			while (-not $confirmed) {
				$key = [Console]::ReadKey($true)
				$directSelection = switch ([string] $key.KeyChar) {
					'1' { 0 }
					'2' { 1 }
					'3' { 2 }
					'4' { 3 }
					default { -1 }
				}
				if ($directSelection -ge 0) {
					$selected = $directSelection
					Write-KoteliButtonRows -Selected $selected -Redraw $true `
						-MenuTop $menuTop
					$confirmed = $true
					continue
				}
				switch ($key.Key) {
					'UpArrow' {
						$selected = ($selected + 3) % 4
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
					}
					'DownArrow' {
						$selected = ($selected + 1) % 4
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
					}
					'Enter' {
						$confirmed = $true
					}
					'Escape' {
						$selected = 3
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
						$confirmed = $true
					}
					'D1' {
						$selected = 0
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
						$confirmed = $true
					}
					'NumPad1' {
						$selected = 0
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
						$confirmed = $true
					}
					'D2' {
						$selected = 1
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
						$confirmed = $true
					}
					'NumPad2' {
						$selected = 1
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
						$confirmed = $true
					}
					'D3' {
						$selected = 2
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
						$confirmed = $true
					}
					'NumPad3' {
						$selected = 2
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
						$confirmed = $true
					}
					'D4' {
						$selected = 3
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
						$confirmed = $true
					}
					'NumPad4' {
						$selected = 3
						Write-KoteliButtonRows -Selected $selected -Redraw $true -MenuTop $menuTop
						$confirmed = $true
					}
				}
			}

			$selectedAction = @('update', 'repair', 'uninstall', 'cancel')[$selected]
			[Console]::Out.WriteLine(
				"Selected: $(Get-KoteliActionName -Action $selectedAction)"
			)
			return $selectedAction
		} catch {
			# Keep the existing four rows and put the usable fallback beneath them.
			[Console]::Out.WriteLine()
			return Read-KoteliNumberedAction
		}
	}

	function Resolve-KoteliAction {
		param([Parameter(Mandatory)][ValidateRange(1, 2)][int] $InstalledCount)

		if ($env:KOTELI_ACTION) {
			switch ($env:KOTELI_ACTION.ToLowerInvariant()) {
				'update' { return 'update' }
				'repair' { return 'repair' }
				'install' { return 'repair' }
				'uninstall' { return 'uninstall' }
				'cancel' { return 'cancel' }
				default {
					throw (
						"Invalid KOTELI_ACTION '$env:KOTELI_ACTION'. Use update, repair, " +
						'uninstall, or cancel.'
					)
				}
			}
		}

		if ($script:KoteliRich) {
			$defaultSelection = if ($InstalledCount -eq 2) { 0 } else { 1 }
			return Read-KoteliButtonAction -DefaultSelection $defaultSelection
		}
		return Read-KoteliNumberedAction
	}

	function Confirm-KoteliConfigRemoval {
		param([Parameter(Mandatory)][string] $ConfigDirectory)

		if ($env:KOTELI_REMOVE_CONFIG) {
			switch ($env:KOTELI_REMOVE_CONFIG.ToLowerInvariant()) {
				{ $_ -in @('1', 'true', 'y', 'yes') } { return $true }
				{ $_ -in @('0', 'false', 'n', 'no') } { return $false }
				default {
					throw (
						"Invalid KOTELI_REMOVE_CONFIG '$env:KOTELI_REMOVE_CONFIG'. " +
						'Use yes or no.'
					)
				}
			}
		}

		if ($env:KOTELI_ACTION) {
			return $false
		}

		Write-KoteliStatus -Kind warn -Label 'Koteli state' -Detail (
			"$ConfigDirectory (legacy kxai compatibility path)"
		)
		Write-KoteliDetail -Label 'Local projects' -Value (
			'.kxai and .koteli remain untouched'
		)
		try {
			$answer = Read-Host 'Remove Koteli user configuration and state? [y/N]'
		} catch {
			return $false
		}
		if ($null -eq $answer) {
			return $false
		}
		return $answer -match '^(y|yes)$'
	}

	function Assert-SafeKoteliConfigPath {
		param([Parameter(Mandatory)][string] $ConfigDirectory)
		$fullConfigPath = [IO.Path]::GetFullPath($ConfigDirectory)
		$configLeaf = Split-Path $fullConfigPath -Leaf
		$configParent = Split-Path (Split-Path $fullConfigPath -Parent) -Leaf
		if ($configLeaf -ne '.kxai' -or $configParent -notin @('tui', 'kxai-tui')) {
			throw "Refusing to remove unexpected configuration path: $fullConfigPath"
		}
		return $fullConfigPath
	}

	function Remove-KoteliConfigPath {
		param([Parameter(Mandatory)][string] $ConfigDirectory)
		$configItem = Get-Item -LiteralPath $ConfigDirectory -Force
		if (($configItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
			Remove-Item -LiteralPath $ConfigDirectory -Force
		} else {
			Remove-Item -LiteralPath $ConfigDirectory -Recurse -Force
		}
	}

	function Invoke-KoteliUninstall {
		param(
			[Parameter(Mandatory)][string] $InstallDirectory,
			[Parameter(Mandatory)][string[]] $Binaries,
			[Parameter(Mandatory)][string] $ConfigDirectory
		)

		# Validate the automation value and the deletion boundary before removing anything.
		$removeConfig = Confirm-KoteliConfigRemoval -ConfigDirectory $ConfigDirectory
		$configExists = $false
		try {
			$null = Get-Item -LiteralPath $ConfigDirectory -Force
			$configExists = $true
		} catch {
			$configExists = $false
		}
		if ($removeConfig -and $configExists) {
			$null = Assert-SafeKoteliConfigPath -ConfigDirectory $ConfigDirectory
		}

		Write-KoteliStatus -Kind ok -Label 'Fetch' -Detail 'not required for uninstall'
		Write-KoteliStatus -Kind ok -Label 'Validate format' -Detail (
			'not required for uninstall'
		)

		$binaryResults = @{}
		Start-KoteliStage -Stage 'Install/Remove' -Detail (
			'remove binaries and state'
		)
		foreach ($binary in $Binaries) {
			$managedPath = Join-Path $InstallDirectory $binary
			if (Test-KoteliManagedPath -Path $managedPath) {
				Remove-Item -LiteralPath $managedPath -Force
				$binaryResults[$binary] = 'removed'
			} else {
				$binaryResults[$binary] = 'not found'
			}
		}

		if ($removeConfig) {
			if ($configExists) {
				Remove-KoteliConfigPath -ConfigDirectory $ConfigDirectory
				$configResult = 'removed'
			} else {
				$configResult = 'not found'
			}
		} elseif ($configExists) {
			$configResult = 'preserved'
		} else {
			$configResult = 'not found'
		}
		Complete-KoteliStage -Detail 'managed files handled'

		$pathMarker = Join-Path $InstallDirectory '.koteli-path-added'
		Start-KoteliStage -Stage 'PATH' -Detail 'remove installer-managed entry'
		if (Test-Path -LiteralPath $pathMarker) {
			$userPath = Get-KoteliUserPath
			$newUserPath = Remove-PathEntry -PathValue $userPath -Directory $InstallDirectory
			Set-KoteliUserPath -Value $newUserPath
			$env:Path = Remove-PathEntry -PathValue $env:Path -Directory $InstallDirectory
			Remove-Item -LiteralPath $pathMarker -Force
			$pathResult = 'removed'
		} else {
			$pathResult = 'unchanged'
		}
		Complete-KoteliStage -Detail $pathResult

		if ((Test-Path -LiteralPath $InstallDirectory) -and
			@(Get-ChildItem -LiteralPath $InstallDirectory -Force).Count -eq 0) {
			Remove-Item -LiteralPath $InstallDirectory -Force
		}

		[Console]::Out.WriteLine()
		Write-KoteliReceipt -Label 'Action' -Value 'uninstalled'
		Write-KoteliReceipt -Label 'koteli.exe' -Value $binaryResults['koteli.exe']
		Write-KoteliReceipt -Label 'kxaid.exe' -Value $binaryResults['kxaid.exe']
		Write-KoteliReceipt -Label 'Destination' -Value $InstallDirectory
		Write-KoteliReceipt -Label 'PATH' -Value $pathResult
		Write-KoteliReceipt -Label 'Koteli state' -Value "$configResult ($ConfigDirectory)"
		Write-KoteliReceipt -Label 'Local projects' -Value '.kxai and .koteli preserved'
	}

	function Invoke-KoteliInstaller {
		Write-KoteliHeader
		Start-KoteliStage -Stage 'Detect' -Detail (
			'platform, target, and binaries'
		)

		$runningOnWindows = $false
		try {
			$runningOnWindows =
				[System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
					[System.Runtime.InteropServices.OSPlatform]::Windows
				)
		} catch {
			$runningOnWindows = $env:OS -eq 'Windows_NT'
		}
		if (-not $runningOnWindows) {
			throw 'install.ps1 only supports Windows. Use install.sh on Linux or macOS.'
		}

		$architecture = Get-KoteliArchitecture
		$installDirectory = if ($env:KOTELI_INSTALL_DIR) {
			$env:KOTELI_INSTALL_DIR
		} elseif ($env:LOCALAPPDATA) {
			Join-Path $env:LOCALAPPDATA 'Programs\Koteli\bin'
		} else {
			Join-Path (
				[Environment]::GetFolderPath('UserProfile')
			) 'AppData\Local\Programs\Koteli\bin'
		}
		$installDirectory = [IO.Path]::GetFullPath($installDirectory)
		$configDirectory = Get-KoteliConfigDirectory
		$binaries = @('koteli.exe', 'kxaid.exe')

		$repository = if ($env:KOTELI_REPOSITORY) {
			$env:KOTELI_REPOSITORY.Trim('/')
		} else {
			'ko-k1/koteli'
		}
		$ref = if ($env:KOTELI_REF) { $env:KOTELI_REF } else { 'main' }
		$downloadBase = if ($env:KOTELI_DOWNLOAD_BASE) {
			$env:KOTELI_DOWNLOAD_BASE.TrimEnd('/')
		} else {
			"https://raw.githubusercontent.com/$repository/$ref"
		}

		if ([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12) {
			# TLS 1.2 is already enabled.
		} else {
			[Net.ServicePointManager]::SecurityProtocol =
				[Net.ServicePointManager]::SecurityProtocol -bor
				[Net.SecurityProtocolType]::Tls12
		}

		$installedCount = @(
			$binaries | Where-Object {
				Test-KoteliManagedPath -Path (Join-Path $installDirectory $_)
			}
		).Count
		Complete-KoteliStage -Detail (
			"windows/$architecture; presence $installedCount/2"
		)

		if ($installedCount -eq 0) {
			$action = 'install'
		} else {
			if ($script:KoteliUnicode) {
				[Console]::Out.WriteLine(
					"$($script:KoteliMuted)manage $($script:KoteliSeparator) " +
					"windows/$architecture $($script:KoteliArrow) $installDirectory" +
					$script:KoteliReset
				)
			} else {
				[Console]::Out.WriteLine(
					"manage - windows/$architecture -> $installDirectory"
				)
			}
			Write-KoteliDetail -Label 'Binaries' -Value "$installedCount/2 present"
			$action = Resolve-KoteliAction -InstalledCount $installedCount
		}

		switch ($action) {
			'uninstall' {
				Invoke-KoteliUninstall -InstallDirectory $installDirectory `
					-Binaries $binaries -ConfigDirectory $configDirectory
				return
			}
			'cancel' {
				[Console]::Out.WriteLine()
				Write-KoteliReceipt -Label 'Action' -Value 'cancelled'
				Write-KoteliReceipt -Label 'Changes' -Value 'none'
				return
			}
		}

		$tempDirectory = Join-Path (
			[IO.Path]::GetTempPath()
		) ("koteli-install-{0}" -f [guid]::NewGuid().ToString('N'))
		try {
			New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null
			foreach ($binary in $binaries) {
				$uri = [uri] "$downloadBase/$architecture/win/$binary"
				$temporaryPath = Join-Path $tempDirectory $binary
				Start-KoteliStage -Stage 'Fetch' -Detail "$binary for windows/$architecture"
				try {
					Invoke-KoteliDownload -Uri $uri -Destination $temporaryPath
				} catch {
					throw (
						"$binary could not be downloaded from $uri. " +
						"A Windows/$architecture build may not be published yet. " +
						$_.Exception.Message
					)
				}
				Complete-KoteliStage -Detail $binary

				Start-KoteliStage -Stage 'Validate format' -Detail $binary
				Assert-WindowsExecutable -Path $temporaryPath -Name $binary `
					-Architecture $architecture
				Complete-KoteliStage -Detail "$binary is a Windows executable"
			}

			Start-KoteliStage -Stage 'Install/Remove' -Detail (
				"$action both binaries"
			)
			New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
			foreach ($binary in $binaries) {
				Copy-Item -LiteralPath (Join-Path $tempDirectory $binary) `
					-Destination (Join-Path $installDirectory $binary) -Force
			}
			Complete-KoteliStage -Detail 'koteli.exe and kxaid.exe installed'

			$pathMarker = Join-Path $installDirectory '.koteli-path-added'
			Start-KoteliStage -Stage 'PATH' -Detail 'inspect and update user PATH'
			if ($env:KOTELI_NO_PATH_UPDATE -eq '1') {
				$pathResult = 'unchanged (KOTELI_NO_PATH_UPDATE=1)'
			} else {
				$userPath = Get-KoteliUserPath
				if (-not (Test-PathContains -PathValue $userPath -Directory $installDirectory)) {
					$newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
						$installDirectory
					} else {
						"$userPath;$installDirectory"
					}
					Set-KoteliUserPath -Value $newUserPath
					Set-Content -LiteralPath $pathMarker `
						-Value 'Added by the Koteli installer.' -Encoding Ascii
					$pathResult = 'added to user PATH'
				} else {
					$pathResult = 'already present'
				}
				if (-not (Test-PathContains -PathValue $env:Path -Directory $installDirectory)) {
					$env:Path = "$installDirectory;$env:Path"
				}
			}
			Complete-KoteliStage -Detail $pathResult

			$result = switch ($action) {
				'install' { 'installed' }
				'repair' { 'repaired' }
				'update' { 'updated' }
			}
			[Console]::Out.WriteLine()
			Write-KoteliReceipt -Label 'Action' -Value $result
			Write-KoteliReceipt -Label 'Binaries' -Value 'koteli.exe, kxaid.exe'
			Write-KoteliReceipt -Label 'Destination' -Value $installDirectory
			Write-KoteliReceipt -Label 'PATH' -Value $pathResult
			Write-KoteliReceipt -Label 'Koteli state' -Value (
				"preserved ($configDirectory)"
			)
			Write-KoteliNext -Label 'Terminal 1' -Value 'kxaid - start the daemon'
			Write-KoteliNext -Label 'Terminal 2' -Value 'koteli - open Koteli'
		} finally {
			if (Test-Path -LiteralPath $tempDirectory) {
				Remove-Item -LiteralPath $tempDirectory -Recurse -Force
			}
		}
	}

	Initialize-KoteliUi
	try {
		Invoke-KoteliInstaller
	} catch {
		$errorMessage = $_.Exception.Message
		if ($script:KoteliActiveStage) {
			Fail-KoteliStage -Message $errorMessage
		} else {
			Write-KoteliError -Message $errorMessage
		}
		if (-not $script:KoteliRich) {
			$styleVariable = Get-Variable -Name PSStyle -ErrorAction SilentlyContinue
			if ($null -ne $styleVariable) {
				$styleVariable.Value.OutputRendering = 'PlainText'
			}
		}
		throw $errorMessage
	}
}
