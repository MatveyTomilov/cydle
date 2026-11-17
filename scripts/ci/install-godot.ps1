# Installs the Godot editor, its console wrapper and the Windows export templates.
# The console wrapper is required: the plain editor executable uses the GUI subsystem,
# so PowerShell returns immediately without waiting for it or capturing its output.
param(
	[string]$Version = '4.7.2',
	[string]$InstallRoot = (Join-Path $env:USERPROFILE 'godot-ci')
)

$ErrorActionPreference = 'Stop'
$tag = "$Version-stable"
$releaseBase = "https://github.com/godotengine/godot-builds/releases/download/$tag"
$editorDir = Join-Path $InstallRoot 'editor'
$templateDir = Join-Path $InstallRoot 'templates'
$consoleExe = Join-Path $editorDir "Godot_v${tag}_win64_console.exe"
$editorExe = Join-Path $editorDir "Godot_v${tag}_win64.exe"
$releaseTemplate = Join-Path $templateDir 'windows_release_x86_64.exe'
$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }

New-Item -ItemType Directory -Force -Path $editorDir, $templateDir, $tempRoot | Out-Null

function Get-ReleaseFile([string]$Name, [string]$Destination) {
	if (Test-Path $Destination) {
		Write-Host "Using cached download $Destination"
		return
	}
	Write-Host "Downloading $releaseBase/$Name"
	& curl.exe -sS -L --fail --retry 3 --retry-delay 5 -o $Destination "$releaseBase/$Name"
	if ($LASTEXITCODE -ne 0) { throw "Download failed: $Name" }
}

if (-not (Test-Path $consoleExe)) {
	$zip = Join-Path $tempRoot "godot-$tag-editor.zip"
	Get-ReleaseFile "Godot_v${tag}_win64.exe.zip" $zip
	& tar.exe -xf $zip -C $editorDir
	if ($LASTEXITCODE -ne 0) { throw 'Editor archive extraction failed' }
	Remove-Item $zip -Force
}

if (-not (Test-Path $releaseTemplate)) {
	$tpz = Join-Path $tempRoot "godot-$tag-templates.tpz"
	Get-ReleaseFile "Godot_v${tag}_export_templates.tpz" $tpz
	$extractDir = Join-Path $tempRoot "godot-$tag-templates"
	if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
	New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
	& tar.exe -xf $tpz -C $extractDir
	if ($LASTEXITCODE -ne 0) { throw 'Export template archive extraction failed' }
	$windowsTemplates = Get-ChildItem -Path $extractDir -Recurse -Filter 'windows_*_x86_64*.exe'
	if ($windowsTemplates.Count -eq 0) { throw 'No Windows export templates found in the archive' }
	$windowsTemplates | Copy-Item -Destination $templateDir -Force
	$versionFile = Get-ChildItem -Path $extractDir -Recurse -Filter 'version.txt' | Select-Object -First 1
	if ($null -eq $versionFile) { throw 'Export template archive has no version.txt' }
	Copy-Item $versionFile.FullName -Destination $templateDir -Force
	Remove-Item $extractDir -Recurse -Force
	Remove-Item $tpz -Force
}

$installedDir = Join-Path $env:APPDATA "Godot\export_templates\$Version.stable"
New-Item -ItemType Directory -Force -Path $installedDir | Out-Null
Copy-Item (Join-Path $templateDir '*') -Destination $installedDir -Force

$installedVersion = (Get-Content (Join-Path $installedDir 'version.txt') -Raw).Trim()
if ($installedVersion -ne "$Version.stable") {
	throw "Export template version mismatch: expected '$Version.stable', found '$installedVersion'"
}
if (-not (Test-Path (Join-Path $installedDir 'windows_release_x86_64.exe'))) {
	throw 'Windows release export template is not installed'
}
if (-not (Test-Path $consoleExe)) { throw "Godot console wrapper missing: $consoleExe" }
if (-not (Test-Path $editorExe)) { throw "Godot editor missing: $editorExe" }

$reported = & $consoleExe --version
if ($LASTEXITCODE -ne 0) { throw 'Godot console wrapper did not report a version' }
Write-Host "Godot reports: $reported"
if ("$reported" -notmatch [regex]::Escape("$Version.stable")) {
	throw "Godot version mismatch: expected '$Version.stable', reported '$reported'"
}

if ($env:GITHUB_ENV) {
	"GODOT_CONSOLE=$consoleExe" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
	"GODOT_EDITOR=$editorExe" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
}
Write-Host "Godot $Version installed: $consoleExe"
Write-Host "Windows export templates: $installedDir"