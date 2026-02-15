<#
.SYNOPSIS
	Provision an Ubuntu WSL distribution and deploy n8n in Docker.

.DESCRIPTION
	This script runs on Windows and automates the following workflow:
	  1. Creates the working directory C:\wsl\n8n_lab.
	  2. Detects the latest Ubuntu LTS release and downloads the matching WSL rootfs.
	  3. Imports a WSL distribution named Ubuntu-n8n-server.
	  4. Enables systemd for the distribution.
	  5. Installs Docker and starts an n8n container.
	  6. Persists n8n application data to C:\wsl\n8n_lab\n8n_data via a bind mount.

.NOTES
	- Run this script from an elevated PowerShell session (Run as Administrator).
	- A recent WSL build (0.67+) is required for systemd support.
	- The first start of the WSL instance can take several minutes while packages install.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
	param([Parameter(Mandatory)][string]$Message)
	$timestamp = (Get-Date).ToString('HH:mm:ss')
	Write-Host "[$timestamp] $Message" -ForegroundColor Cyan
}

function Test-ElevationRequirement {
	if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
		throw 'This script must be run from an elevated PowerShell session.'
	}
}

function Test-WslAvailability {
	try {
		& wsl.exe --status | Out-Null
	}
	catch {
		throw 'WSL is not installed. Install it with "wsl --install" and rerun this script.'
	}
	if ($LASTEXITCODE -ne 0) {
		throw 'WSL returned a non-zero status. Ensure WSL is installed and accessible before continuing.'
	}
}

function New-DirectoryIfMissing {
	param([Parameter(Mandatory)][string]$Path)
	if (-not (Test-Path -LiteralPath $Path)) {
		Write-Step "Creating directory $Path"
		New-Item -Path $Path -ItemType Directory -Force | Out-Null
	}
}

function Get-LatestUbuntuLtsRelease {
	$orderedCandidates = @(
		[pscustomobject]@{ Version = '24.04'; Codename = 'noble'; ReleaseDate = Get-Date '2024-04-25' },
		[pscustomobject]@{ Version = '22.04'; Codename = 'jammy'; ReleaseDate = Get-Date '2022-04-21' }
	)

	foreach ($candidate in $orderedCandidates) {
		$url = Get-UbuntuRootfsUriFromCodename -Codename $candidate.Codename
		if ([string]::IsNullOrWhiteSpace($url)) {
			Write-Step "Ubuntu candidate $($candidate.Version) does not have a discoverable rootfs URL."
			continue
		}
		if (Test-UriAvailable -Uri $url) {
			Write-Step "Selected Ubuntu LTS candidate $($candidate.Version) ($($candidate.Codename))"
			return [pscustomobject]@{
				Version = $candidate.Version
				Codename = $candidate.Codename
				RootfsUri = $url
				ReleaseDate = $candidate.ReleaseDate
			}
		}
		Write-Step "Ubuntu candidate $($candidate.Version) not reachable at $url"
	}

	throw 'Unable to determine a downloadable Ubuntu LTS rootfs.'
}

function Get-UbuntuRootfsUriFromCodename {
	param([Parameter(Mandatory)][string]$Codename)

	$baseUris = @(
		"https://cdimages.ubuntu.com/ubuntu-wsl/$Codename/current/",
		"https://cdimages.ubuntu.com/ubuntu-wsl/$Codename/daily-live/current/"
	)

	$candidateFileNames = @(
		"ubuntu-$Codename-wsl-amd64-wsl.rootfs.tar.gz",
		"ubuntu-$Codename-wsl-amd64-wsl.rootfs.tar.xz",
		"$Codename-wsl-amd64.wsl",
		"rootfs.tar.gz",
		"rootfs.tar.xz"
	)

	foreach ($baseUri in $baseUris) {
		foreach ($fileName in $candidateFileNames) {
			$uri = "$baseUri$fileName"
			if ([string]::IsNullOrEmpty($uri)) {
				continue
			}
			if (Test-UriAvailable -Uri $uri) {
				return $uri
			}
		}

		$discovered = Find-UbuntuRootfsArtifactInIndex -BaseUri $baseUri
		if ($discovered) {
			return $discovered
		}
	}

	return $null
}

function Find-UbuntuRootfsArtifactInIndex {
	param([Parameter(Mandatory)][string]$BaseUri)

	try {
		$response = Invoke-WebRequest -Uri $BaseUri -UseBasicParsing -ErrorAction Stop
	}
	catch {
		return $null
	}

	$pattern = 'href="([^"]*(?:rootfs|\.wsl)[^"/]*)"'
	$linkMatches = [regex]::Matches($response.Content, $pattern, 'IgnoreCase')
	if ($linkMatches.Count -eq 0) {
		return $null
	}

	$baseUriObject = [System.Uri]$BaseUri
	$candidates = $linkMatches | ForEach-Object {
		$link = $_.Groups[1].Value
		if ($link -like 'http*') {
			$link
		}
		else {
			([System.Uri]::new($baseUriObject, $link)).AbsoluteUri
		}
	} | Sort-Object -Unique

	foreach ($candidate in $candidates) {
		if ([string]::IsNullOrWhiteSpace($candidate)) {
			continue
		}
		if (Test-UriAvailable -Uri $candidate) {
			return $candidate
		}
	}

	return $null
}

function Test-UriAvailable {
	param([Parameter(Mandatory)][string]$Uri)

	try {
		$response = Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing -ErrorAction Stop
		return $response.StatusCode -ge 200 -and $response.StatusCode -lt 400
	}
	catch {
		return $false
	}
}

function Get-FileIfNeeded {
	param(
		[Parameter(Mandatory)][string]$Uri,
		[Parameter(Mandatory)][string]$Destination
	)

	if (Test-Path -LiteralPath $Destination) {
		Write-Step "Using cached file $Destination"
		return
	}

	Write-Step "Downloading $Uri"
	try {
		Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -ErrorAction Stop
	}
	catch {
		$details = "Failed to download {0}: {1}" -f $Uri, $_.Exception.Message
		throw $details
	}
}

function Expand-GzipFile {
	param(
		[Parameter(Mandatory)][string]$SourceGzip,
		[Parameter(Mandatory)][string]$DestinationTar
	)

	if (Test-Path -LiteralPath $DestinationTar) {
		Write-Step "Using existing tar archive $DestinationTar"
		return
	}

	Write-Step "Expanding $(Split-Path -Leaf $SourceGzip)"
	$inputStream = [System.IO.File]::OpenRead($SourceGzip)
	try {
		$gzipStream = New-Object System.IO.Compression.GzipStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
		try {
			$outputStream = [System.IO.File]::Create($DestinationTar)
			try {
				$buffer = New-Object byte[] 81920
				while (($bytesRead = $gzipStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
					$outputStream.Write($buffer, 0, $bytesRead)
				}
			}
			finally {
				$outputStream.Dispose()
			}
		}
		finally {
			$gzipStream.Dispose()
		}
	}
	finally {
		$inputStream.Dispose()
	}
}

function Convert-ToTarArchive {
	param(
		[Parameter(Mandatory)][string]$SourcePath,
		[Parameter(Mandatory)][string]$WorkspaceRoot
	)

	$extension = [System.IO.Path]::GetExtension($SourcePath)
	if (-not $extension) {
		throw "Unable to determine file extension for $SourcePath"
	}

	$lowerExtension = $extension.ToLowerInvariant()
	switch ($lowerExtension) {
		'.gz' {
			$tarPath = [System.IO.Path]::ChangeExtension($SourcePath, '.tar')
			Expand-GzipFile -SourceGzip $SourcePath -DestinationTar $tarPath
			return $tarPath
		}
		'.tar' {
			return $SourcePath
		}
		'.wsl' {
			$tarPath = [System.IO.Path]::ChangeExtension($SourcePath, '.tar')
			Expand-GzipFile -SourceGzip $SourcePath -DestinationTar $tarPath
			return $tarPath
		}
		default {
			throw "Unsupported archive format: $lowerExtension"
		}
	}
}

function Test-WslDistribution {
	param([Parameter(Mandatory)][string]$Name)
	try {
		$raw = (& wsl.exe --list --quiet 2>$null)
	}
	catch {
		throw "Unable to list WSL distributions: $($_.Exception.Message)"
	}

	if (-not $raw) {
		return $false
	}

	$names = $raw -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
	return $names -contains $Name
}

function Import-WslDistribution {
	param(
		[Parameter(Mandatory)][string]$Name,
		[Parameter(Mandatory)][string]$InstallFolder,
		[Parameter(Mandatory)][string]$TarPath
	)

	if (Test-WslDistribution -Name $Name) {
		Write-Step "WSL distribution $Name already exists; skipping import"
		return
	}

	Write-Step "Importing WSL distribution $Name"
	& wsl.exe --import $Name $InstallFolder $TarPath --version 2
	if ($LASTEXITCODE -ne 0) {
		throw "Failed to import WSL distribution $Name (exit code $LASTEXITCODE)"
	}
}

function Invoke-WslCommand {
	param(
		[Parameter(Mandatory)][string]$Distribution,
		[Parameter(Mandatory)][string]$Command,
		[string]$User
	)

	$arguments = @('-d', $Distribution)
	$effectiveUser = if ($User) { $User } else { 'root' }
	$arguments += @('-u', $effectiveUser)
	$arguments += @('--', 'bash', '-lc', $Command)

	& wsl.exe @arguments
	if ($LASTEXITCODE -ne 0) {
		$message = "Command failed in {0} (exit code {1}): {2}" -f $Distribution, $LASTEXITCODE, $Command
		throw $message
	}
}

function Set-WslSystemdConfiguration {
	param(
		[Parameter(Mandatory)][string]$Distribution,
		[Parameter(Mandatory)][string]$Hostname
	)

	$wslConfContent = @"
[boot]
systemd=true

[network]
hostname=$Hostname

[user]
default=root
"@

	$encodedConf = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($wslConfContent))
	$command = "printf '%s' '$encodedConf' | base64 -d | sudo tee /etc/wsl.conf >/dev/null"
	Invoke-WslCommand -Distribution $Distribution -Command $command
}

function Initialize-UbuntuServer {
	param(
		[Parameter(Mandatory)][string]$Distribution,
		[Parameter(Mandatory)][string]$Codename
	)

	Write-Step "Updating packages on $Distribution"
	Invoke-WslCommand -Distribution $Distribution -Command 'sudo rm -f /etc/apt/sources.list.d/docker.list'
	Invoke-WslCommand -Distribution $Distribution -Command 'export DEBIAN_FRONTEND=noninteractive; sudo apt-get update && sudo apt-get upgrade -y'

	Write-Step "Installing Docker prerequisite packages on $Distribution"
	Invoke-WslCommand -Distribution $Distribution -Command 'export DEBIAN_FRONTEND=noninteractive; sudo apt-get install -y ca-certificates curl gnupg lsb-release'

	Invoke-WslCommand -Distribution $Distribution -Command 'sudo install -m 0755 -d /etc/apt/keyrings'
	Invoke-WslCommand -Distribution $Distribution -Command 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg'
	Invoke-WslCommand -Distribution $Distribution -Command 'sudo chmod a+r /etc/apt/keyrings/docker.gpg'

	$repoLine = "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $Codename stable"
	$encodedRepo = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($repoLine))
	$writeRepoCommand = "printf '%s' '$encodedRepo' | base64 -d | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null"
	Invoke-WslCommand -Distribution $Distribution -Command $writeRepoCommand

	Write-Step "Installing Docker Engine on $Distribution"
	Invoke-WslCommand -Distribution $Distribution -Command 'export DEBIAN_FRONTEND=noninteractive; sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
	Invoke-WslCommand -Distribution $Distribution -Command 'sudo usermod -aG docker root'
}

function Start-N8nService {
 	param(
 		[Parameter(Mandatory)][string]$Distribution,
 		[Parameter(Mandatory)][string]$HostDataPath
 	)

	Write-Step "Starting n8n container on $Distribution"
	Invoke-WslCommand -Distribution $Distribution -Command 'sudo systemctl enable --now docker.service'
	Invoke-WslCommand -Distribution $Distribution -Command 'sudo docker network inspect n8n-network >/dev/null 2>&1 || sudo docker network create n8n-network'
	Invoke-WslCommand -Distribution $Distribution -Command "sudo mkdir -p '$HostDataPath' && sudo chown 1000:1000 '$HostDataPath' && sudo chmod 0770 '$HostDataPath'"
	Invoke-WslCommand -Distribution $Distribution -Command 'sudo docker ps -a --format "{{.Names}}" | grep -q "^n8n$" && sudo docker rm -f n8n || true'
	Invoke-WslCommand -Distribution $Distribution -Command "sudo docker run -d --name n8n --restart unless-stopped --network n8n-network -p 5678:5678 -v '$HostDataPath':/home/node/.n8n -e TZ=UTC n8nio/n8n:latest"
}

# Execution starts here
Test-ElevationRequirement
Test-WslAvailability

$workspaceRoot = 'C:\wsl\n8n_lab'
New-DirectoryIfMissing -Path $workspaceRoot

$n8nDataPath = Join-Path $workspaceRoot 'n8n_data'
New-DirectoryIfMissing -Path $n8nDataPath

$ubuntuRelease = Get-LatestUbuntuLtsRelease
$releaseVersion = $ubuntuRelease.Version
$releaseCodename = $ubuntuRelease.Codename
$rootfsUri = $ubuntuRelease.RootfsUri

Write-Step "Selected Ubuntu LTS version $releaseVersion"
$archivePath = Join-Path $workspaceRoot (Split-Path -Leaf $rootfsUri)
Get-FileIfNeeded -Uri $rootfsUri -Destination $archivePath
$tarPath = Convert-ToTarArchive -SourcePath $archivePath -WorkspaceRoot $workspaceRoot

$serverName = 'Ubuntu-n8n-server'
$serverInstallPath = Join-Path $workspaceRoot 'ubuntu-server'

New-DirectoryIfMissing -Path $serverInstallPath

Import-WslDistribution -Name $serverName -InstallFolder $serverInstallPath -TarPath $tarPath

Set-WslSystemdConfiguration -Distribution $serverName -Hostname 'ubuntu-n8n-server'

Write-Step 'Applying systemd configuration by restarting WSL'
& wsl.exe --shutdown
Start-Sleep -Seconds 5

Initialize-UbuntuServer -Distribution $serverName -Codename $releaseCodename
Start-N8nService -Distribution $serverName -HostDataPath '/mnt/c/wsl/n8n_lab/n8n_data'

Write-Step 'All tasks completed. Use "wsl -d Ubuntu-n8n-server" to connect to the new instance.'