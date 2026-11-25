@echo off
rem SPDX-License-Identifier: MIT
rem Author: YxxgSxxl
setlocal DisableDelayedExpansion
set "ERRORLEVEL="
set "MUSIC_DL_BATCH=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -Command "$ErrorActionPreference = 'Stop'; $lines = [IO.File]::ReadAllLines($env:MUSIC_DL_BATCH, [Text.Encoding]::UTF8); $start = [Array]::IndexOf($lines, '# MUSIC_DL_POWERSHELL'); if ($start -lt 0 -or $start -ge ($lines.Length - 1)) { exit 1 }; . ([ScriptBlock]::Create(($lines[($start + 1)..($lines.Length - 1)] -join [Environment]::NewLine))); exit (Start-MusicDownloader)"
exit /b %ERRORLEVEL%

# MUSIC_DL_POWERSHELL
$ErrorActionPreference = 'Stop'
$stableDownloaderVersionPattern = '^\d{4}\.\d{2}\.\d{2}(?:\.\d+)?$'

function Read-MusicInput {
    param([string]$Prompt)

    Write-Host $Prompt -ForegroundColor Cyan -NoNewline
    [Console]::ReadLine()
}

function Initialize-MusicConsole {
    param([string]$Title)

    $utf8 = [Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
    if ([Console]::IsOutputRedirected) { return }

    try {
        $console = $Host.UI.RawUI
        $console.WindowTitle = $Title
        $console.BackgroundColor = 'Black'
        $console.ForegroundColor = 'Gray'

        if ($env:TERM_PROGRAM -eq 'vscode' -or $env:WT_SESSION) { return }

        # The 76-column window and centering only apply to the classic console.
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class MusicDownloaderWindow {
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect {
        public int Left, Top, Right, Bottom;
    }

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr window, int x, int y, int width, int height, bool repaint);
}
'@
        $window = [MusicDownloaderWindow]::GetConsoleWindow()
        if ($window -eq [IntPtr]::Zero -or -not [MusicDownloaderWindow]::IsWindowVisible($window)) { return }

        & "$env:SystemRoot\System32\mode.com" con 'cols=76' 'lines=30' 2>$null | Out-Null
        $rect = New-Object MusicDownloaderWindow+Rect
        if (-not [MusicDownloaderWindow]::GetWindowRect($window, [ref]$rect)) { return }

        Add-Type -AssemblyName System.Windows.Forms
        $area = [Windows.Forms.Screen]::FromHandle($window).WorkingArea
        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        $left = $area.Left + [Math]::Max(0, [int](($area.Width - $width) / 2))
        $top = $area.Top + [Math]::Max(0, [int](($area.Height - $height) / 2))
        [void][MusicDownloaderWindow]::MoveWindow($window, $left, $top, $width, $height, $true)
    } catch {
        # Appearance is optional if the console host rejects a window operation.
    }
}

function Write-MusicStatus {
    param([string]$Label, [string]$Text, [ConsoleColor]$Color = 'Cyan')

    Write-Host "  [$Label] " -ForegroundColor $Color -NoNewline
    Write-Host $Text
}

function Show-MusicHeader {
    param([string]$Heading, [string]$Subtitle, [switch]$KeepContent)

    if (-not $KeepContent -and -not [Console]::IsOutputRedirected) { Clear-Host }
    $width = 66
    $border = '  +' + ('=' * $width) + '+'
    Write-Host ''
    Write-Host $border -ForegroundColor DarkCyan
    foreach ($line in $Heading, $Subtitle) {
        if (-not $line) { continue }
        $left = [int][Math]::Floor(($width - $line.Length) / 2)
        $centered = ((' ' * $left) + $line).PadRight($width)
        Write-Host '  |' -ForegroundColor DarkCyan -NoNewline
        Write-Host $centered -ForegroundColor Cyan -NoNewline
        Write-Host '|' -ForegroundColor DarkCyan
    }
    Write-Host $border -ForegroundColor DarkCyan
    Write-Host ''
}

function Read-MusicLink {
    Write-Host ''
    Write-Host "  Colle le lien d’un titre ou d’une playlist."
    Write-Host '  Le type de contenu est détecté automatiquement.' -ForegroundColor DarkGray
    Write-Host ''
    Write-MusicStatus 'Q' 'Quitter'
    Write-Host ''
    while ($true) {
        $text = Read-MusicInput '  Lien > '
        if ($null -eq $text -or $text.Trim() -eq 'q') { return }
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $uri = ConvertTo-MusicUri $text.Trim()
        if ($uri) { return $uri }
        Write-MusicStatus '!' 'Colle un lien HTTP ou HTTPS valide.' -Color Yellow
    }
}

function Read-MusicRetry {
    if (-not [Console]::IsInputRedirected) {
        Write-Host '  Choix > ' -ForegroundColor Cyan -NoNewline
        do {
            $key = [Console]::ReadKey($true).Key
        } until ($key -in 'R', 'Q')
        Write-Host $key
        return ($key -eq 'R')
    }

    while ($true) {
        $choice = Read-MusicInput '  Choix > '
        if ($null -eq $choice -or $choice.Trim() -eq 'q') { return $false }
        if ($choice.Trim() -eq 'r') { return $true }
    }
}

function Find-DownloadTools {
    $tools = @{}
    $missing = @()
    foreach ($name in 'yt-dlp', 'ffmpeg', 'ffprobe') {
        $command = Get-Command "$name.exe" -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) {
            $tools[$name] = $command.Source
        } else {
            $missing += $name
        }
    }
    if ($missing.Count -gt 0) {
        throw "Outils introuvables dans le PATH : $($missing -join ', '). Installe-les selon le README, puis ouvre un nouveau terminal."
    }
    $tools
}

function ConvertTo-MusicUri {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text) -or $Text -match '[\s"<>\x00-\x1F\x7F]') {
        return
    }
    $uri = $null
    if ([Uri]::TryCreate($Text, [UriKind]::Absolute, [ref]$uri) -and
        $uri.IsWellFormedOriginalString() -and $uri.Scheme -in 'http', 'https' -and $uri.Host) {
        return $uri
    }
}

function Invoke-Downloader {
    param([string]$Executable, [string[]]$Arguments)

    # Windows PowerShell can surface native stderr as PowerShell error records.
    $ErrorActionPreference = 'Continue'
    & $Executable --ignore-config --encoding utf-8 --socket-timeout 30 @Arguments
}

function Get-DownloaderVersion {
    param([string]$Executable)

    $version = @(Invoke-Downloader $Executable @('--version'))
    if ($LASTEXITCODE -ne 0 -or $version.Count -eq 0 -or [string]::IsNullOrWhiteSpace($version[-1])) {
        throw 'yt-dlp ne démarre pas. Répare son installation, puis relance Music Downloader.'
    }
    $version[-1].Trim()
}

function Get-StableDownloaderRelease {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest' -UseBasicParsing -TimeoutSec 5
    if ($release.tag_name -notmatch $stableDownloaderVersionPattern) {
        throw 'Version stable inattendue.'
    }
    $release.tag_name
}

function Invoke-DownloaderUpdate {
    param([string]$Executable, [string]$Version)

    $file = Get-Item -LiteralPath $Executable
    $installedPath = $file.FullName
    if ($file.LinkType -eq 'SymbolicLink' -and $file.Target) {
        $installedPath = @($file.Target)[0]
    }

    if ($installedPath -match '\\WinGet\\Packages\\yt-dlp\.yt-dlp_') {
        $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $winget) {
            throw 'WinGet est introuvable pour cette installation de yt-dlp.'
        }
        & $winget.Source upgrade --id yt-dlp.yt-dlp --exact --source winget --version $Version --skip-dependencies --disable-interactivity | Out-Host
    } else {
        Invoke-Downloader $Executable @('--update-to', "stable@$Version") | Out-Host
    }
    if ($LASTEXITCODE -ne 0) {
        throw "L’outil de mise à jour a renvoyé le code $LASTEXITCODE."
    }
}

function Offer-DownloaderUpdate {
    param([string]$Executable)

    $installed = Get-DownloaderVersion $Executable
    if ($installed -notmatch $stableDownloaderVersionPattern) {
        Write-MusicStatus 'INFO' "yt-dlp $installed. Le contrôle concerne les versions stables."
        return
    }

    try {
        $latest = Get-StableDownloaderRelease
    } catch {
        Write-MusicStatus '!' "Vérification indisponible. yt-dlp $installed reste utilisable." -Color Yellow
        return
    }
    if ([version]$latest -le [version]$installed) {
        Write-MusicStatus 'OK' "yt-dlp $installed est à jour (canal stable)." -Color Green
        return
    }

    Write-MusicStatus 'MAJ' "yt-dlp $latest est disponible. Version installée : $installed." -Color Yellow
    $answer = Read-MusicInput '  Installer cette version stable ? [o/N] '
    if ($null -eq $answer -or $answer.Trim() -ne 'o') {
        Write-MusicStatus 'INFO' "yt-dlp $installed est conservé pour cette session."
        return
    }

    try {
        Invoke-DownloaderUpdate $Executable $latest
    } catch {
        Write-MusicStatus '!' "Mise à jour impossible. $($_.Exception.Message)" -Color Yellow
    }

    $usable = Get-DownloaderVersion $Executable
    if ($usable -match $stableDownloaderVersionPattern -and [version]$usable -ge [version]$latest) {
        Write-MusicStatus 'OK' "yt-dlp $usable est prêt." -Color Green
    } else {
        Write-MusicStatus '!' "La version $usable est toujours utilisée." -Color Yellow
    }
}

function Get-SourceInfo {
    param([string]$Downloader, [Uri]$Uri)

    $json = @(Invoke-Downloader $Downloader @('--flat-playlist', '--dump-single-json', '--', $Uri.AbsoluteUri))
    if ($LASTEXITCODE -ne 0 -or $json.Count -eq 0) {
        throw "yt-dlp n’a pas pu analyser le lien."
    }
    try {
        $metadata = ConvertFrom-Json -InputObject ($json -join [Environment]::NewLine)
    } catch {
        throw 'La réponse de yt-dlp est illisible.'
    }
    if (-not $metadata -or (-not $metadata.id -and -not $metadata._type)) {
        throw "yt-dlp n’a renvoyé aucune information sur ce lien."
    }

    $platform = $metadata.extractor_key
    if (-not $platform) { $platform = $metadata.extractor }
    if (-not $platform) { $platform = 'Generic' }
    [pscustomobject]@{
        IsPlaylist = ($metadata._type -in 'playlist', 'multi_video' -or $null -ne $metadata.entries)
        Platform = $platform
    }
}

function Select-DownloadDestination {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = 'Choisis le dossier de destination'
        if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
    } finally {
        $dialog.Dispose()
    }
}

function Get-CompletedDownloadFolders {
    param([string]$WorkDirectory, [string]$Manifest)

    if (-not [IO.File]::Exists($Manifest)) {
        throw 'Aucun fichier audio finalisé par yt-dlp.'
    }
    $folders = [ordered]@{}
    foreach ($line in [IO.File]::ReadLines($Manifest, [Text.Encoding]::UTF8)) {
        $record = ConvertFrom-Json -InputObject $line
        if (-not $record.filepath -or -not [IO.Path]::IsPathRooted($record.filepath)) {
            throw 'yt-dlp a renvoyé un chemin de sortie inattendu.'
        }
        $file = Get-Item -LiteralPath $record.filepath -ErrorAction Stop
        if ($file -isnot [IO.FileInfo] -or $file.Directory.Parent.FullName -ne $WorkDirectory) {
            throw 'Un fichier finalisé ne se trouve pas dans un dossier de téléchargement attendu.'
        }
        if (-not $folders.Contains($file.Directory.FullName)) {
            $folders[$file.Directory.FullName] = [pscustomobject]@{
                Folder = $file.Directory
                FirstUrl = ConvertTo-MusicUri $record.webpage_url
                Tracks = [Collections.Generic.List[IO.FileInfo]]::new()
            }
        }
        $folders[$file.Directory.FullName].Tracks.Add($file)
    }
    if ($folders.Count -eq 0) {
        throw 'Aucun fichier audio finalisé par yt-dlp.'
    }
    $folders.Values
}

function Move-DownloadedCover {
    param($Entry, [string]$Assets)

    $images = @(Get-ChildItem -LiteralPath $Entry.Folder.FullName -File | Where-Object {
        $_.Extension -in '.jpg', '.jpeg', '.png', '.webp', '.avif', '.gif', '.bmp'
    })
    $thumbnails = @(foreach ($track in $Entry.Tracks) {
        $images | Where-Object { $_.BaseName -eq $track.BaseName }
    })
    if ($thumbnails.Count -eq 0) { return }

    $coverPath = Join-Path $Assets ('cover' + $thumbnails[0].Extension)
    if ([IO.File]::Exists($coverPath)) { return (Get-Item -LiteralPath $coverPath) }
    [IO.File]::Move($thumbnails[0].FullName, $coverPath)
    # Extra track thumbnails belong to this staged download.
    foreach ($file in $thumbnails) {
        if ($file.FullName -ne $thumbnails[0].FullName) { [IO.File]::Delete($file.FullName) }
    }
    Get-Item -LiteralPath $coverPath
}

function Notify-MusicFolder {
    param([string]$Path)

    try {
        if (-not ('MusicDownloaderExplorer' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MusicDownloaderExplorer {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern void SHChangeNotify(uint eventId, uint flags, string path, IntPtr unused);
}
'@
        }
        # SHCNE_UPDATEITEM with a Unicode filesystem path.
        [MusicDownloaderExplorer]::SHChangeNotify(0x2000, 0x0005, $Path, [IntPtr]::Zero)
    } catch {
        # Explorer can pick up desktop.ini independently of this notification.
    }
}

function Add-DownloadAssets {
    param($Entry, [Uri]$Uri, [bool]$IsPlaylist, [hashtable]$Tools)

    $folder = $Entry.Folder
    $assets = Join-Path $folder.FullName '_assets'
    [void][IO.Directory]::CreateDirectory($assets)

    Write-MusicStatus '4/6' 'Récupération de la pochette...'
    $cover = $null
    try {
        $cover = Move-DownloadedCover $Entry $assets
        if (-not $cover) {
            $coverArguments = @('--skip-download', '--write-thumbnail', '-P', $assets, '-o', 'cover.%(ext)s')
            if ($Entry.FirstUrl) {
                $coverArguments += @('--no-playlist', '--', $Entry.FirstUrl.AbsoluteUri)
            } elseif ($IsPlaylist) {
                $coverArguments += @('--yes-playlist', '--playlist-items', '1', '--', $Uri.AbsoluteUri)
            } else {
                $coverArguments += @('--no-playlist', '--', $Uri.AbsoluteUri)
            }
            Invoke-Downloader $Tools['yt-dlp'] $coverArguments | Out-Host
            $cover = Get-ChildItem -LiteralPath $assets -File | Where-Object {
                $_.BaseName -eq 'cover' -and $_.Extension -in '.jpg', '.jpeg', '.png', '.webp', '.avif', '.gif', '.bmp'
            } | Select-Object -First 1
        }
        if (-not $cover) { Write-Warning "Pochette indisponible pour $($folder.Name)." }
    } catch {
        Write-Warning "Pochette indisponible pour $($folder.Name). $($_.Exception.Message)"
    }

    Write-MusicStatus '5/6' 'Création du raccourci...'
    try {
        $shortcut = @('[InternetShortcut]', "URL=$($Uri.AbsoluteUri)")
        $shortcutPath = Join-Path $assets ($folder.Name + '.url')
        [IO.File]::WriteAllLines($shortcutPath, $shortcut, [Text.Encoding]::Unicode)
    } catch {
        Write-Warning "Raccourci indisponible pour $($folder.Name). $($_.Exception.Message)"
    }

    if ($cover) {
        try {
            $null = Set-MusicFolderIcon $folder $cover $Tools['ffmpeg']
        } catch {
            Write-Warning "Icône indisponible pour $($folder.Name). $($_.Exception.Message)"
        }
    }
}

function Set-MusicFolderIcon {
    param([IO.DirectoryInfo]$Folder, [IO.FileInfo]$Cover, [string]$Ffmpeg)

    Write-MusicStatus '6/6' 'Application de la pochette au dossier...'
    $icon = Join-Path $Folder.FullName 'folder.ico'
    & $Ffmpeg -nostdin -loglevel error -i $Cover.FullName -vf 'scale=256:256:force_original_aspect_ratio=increase,crop=256:256' -frames:v 1 $icon | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($icon)) {
        Write-Warning "Impossible de créer l’icône de $($folder.Name)."
        return $false
    }

    $desktopIni = Join-Path $folder.FullName 'desktop.ini'
    [IO.File]::WriteAllLines($desktopIni, @('[.ShellClassInfo]', 'IconResource=folder.ico,0'), [Text.Encoding]::Unicode)
    $attributes = [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
    [IO.File]::SetAttributes($icon, $attributes)
    [IO.File]::SetAttributes($desktopIni, $attributes)
    $folder.Attributes = $folder.Attributes -bor [IO.FileAttributes]::ReadOnly
    Write-MusicStatus 'OK' 'Icône du dossier appliquée.' -Color Green
    return $true
}

function Move-CompletedDownloadFolder {
    param([IO.DirectoryInfo]$Folder, [string]$Destination)

    # Directory.Move is a rename on the same volume and refuses to overwrite.
    for ($number = 1; $number -le 1000; $number++) {
        $name = $Folder.Name
        if ($number -gt 1) { $name = "$name ($number)" }
        $target = Join-Path $Destination $name
        if (Test-Path -LiteralPath $target) { continue }
        try {
            [IO.Directory]::Move($Folder.FullName, $target)
            return $target
        } catch [IO.IOException] {
            if (-not (Test-Path -LiteralPath $target) -or
                -not [IO.Directory]::Exists($Folder.FullName)) { throw }
        }
    }
    throw "Aucun nom libre pour $($Folder.Name). Choisis un autre dossier de destination."
}

function Move-IncompleteDownloadFiles {
    param($Entry, [string]$RecoveryRoot)

    $keep = @('folder.ico', 'desktop.ini') + @($Entry.Tracks | ForEach-Object Name)
    $remaining = @(Get-ChildItem -LiteralPath $Entry.Folder.FullName -File -Force |
        Where-Object { $_.Name -notin $keep })
    if ($remaining.Count -eq 0) { return }

    $recovery = [IO.Directory]::CreateDirectory((Join-Path $RecoveryRoot $Entry.Folder.Name))
    foreach ($file in $remaining) {
        [IO.File]::Move($file.FullName, (Join-Path $recovery.FullName $file.Name))
    }
}

function Get-MusicDownloadArguments {
    param([Uri]$Uri, [string]$WorkDirectory, [string]$Manifest, [bool]$IsPlaylist)

    # Leave room under the legacy Windows path limit for both names and FFmpeg's temporary suffixes.
    $nameBytes = [Math]::Min(80, [int][Math]::Floor((240 - $WorkDirectory.Length - 32) / 2))
    if ($nameBytes -lt 20) {
        throw 'Destination trop longue. Choisis un dossier plus proche de la racine, par exemple D:\Musique.'
    }

    $title = "%(filename_title,id).${nameBytes}B"
    $arguments = @(
        '--windows-filenames', '--no-simulate', '--parse-metadata', '%(title|)s:(?s)(?P<filename_title>.+)',
        '-f', 'bestaudio/best', '-x', '--audio-format', 'best', '--write-thumbnail', '--no-write-playlist-metafiles',
        '--use-postprocessor', 'FFmpegMetadata:when=after_move',
        '--use-postprocessor', 'EmbedThumbnail:when=after_move;already_have_thumbnail=True',
        '-P', $WorkDirectory,
        '--print-to-file', 'after_move:%(.{filepath,webpage_url})j', $Manifest
    )

    if ($IsPlaylist) {
        $arguments += @('--yes-playlist', '--parse-metadata', 'pre_process:%(playlist|)s:(?s)(?P<filename_playlist>.+)')
        $fields = 'filename_title,filename_playlist'
        $template = "%(filename_playlist,playlist_id).${nameBytes}B\%(playlist_index)03d - $title.%(ext)s"
    } else {
        $arguments += '--no-playlist'
        $fields = 'filename_title'
        $template = "$title\$title.%(ext)s"
    }

    # Windows PowerShell drops empty native arguments unless explicitly quoted.
    $emptyReplacement = ''
    if ($PSVersionTable.PSVersion.Major -lt 7) { $emptyReplacement = '""' }
    $reservedName = '(?i)^(?:CON|PRN|AUX|NUL|(?:COM|LPT)[1-9\u00B9\u00B2\u00B3]|CONIN\$|CONOUT\$)(?=\s*(?:\.|$))'
    $arguments += @(
        '--replace-in-metadata', $fields, '[\s.]+$', $emptyReplacement,
        '--replace-in-metadata', $fields, $reservedName, '_\g<0>',
        '-o', $template, '--', $Uri.AbsoluteUri
    )
    $arguments
}

function Save-MusicDownload {
    param([Uri]$Uri, [string]$Destination, [bool]$IsPlaylist, [hashtable]$Tools)

    $directory = Get-Item -LiteralPath $Destination
    if ($directory -isnot [IO.DirectoryInfo]) {
        throw 'La destination doit être un dossier.'
    }
    $work = Join-Path $directory.FullName ('.music-dl-' + [Guid]::NewGuid().ToString('N').Substring(0, 16))
    $manifest = Join-Path $work 'completed.jsonl'
    $arguments = @(Get-MusicDownloadArguments $Uri $work $manifest $IsPlaylist)
    try {
        $work = [IO.Directory]::CreateDirectory($work).FullName
    } catch {
        throw "Impossible de créer le dossier temporaire dans $($directory.FullName). $($_.Exception.Message)"
    }
    $finished = @()
    try {
        if ($IsPlaylist) {
            Write-MusicStatus '3/6' 'Téléchargement de la playlist...'
        } else {
            Write-MusicStatus '3/6' 'Téléchargement du titre...'
        }
        Invoke-Downloader $Tools['yt-dlp'] $arguments | Out-Host
        $downloadExit = $LASTEXITCODE
        if ($downloadExit -ne 0 -and -not [IO.File]::Exists($manifest)) {
            throw "Le téléchargement a échoué (yt-dlp, code $downloadExit)."
        }

        $folders = @(Get-CompletedDownloadFolders $work $manifest)
        $recoveryRoot = Join-Path $work ('.partial-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        foreach ($entry in $folders) {
            try {
                Add-DownloadAssets $entry $Uri $IsPlaylist $Tools
            } catch {
                Write-Warning "Accessoires indisponibles pour $($entry.Folder.Name). $($_.Exception.Message)"
            }
            if ($downloadExit -ne 0) {
                try {
                    Move-IncompleteDownloadFiles $entry $recoveryRoot
                } catch {
                    Write-Warning "Certains fichiers de travail sont restés dans $($entry.Folder.Name). $($_.Exception.Message)"
                }
            }
            $path = Move-CompletedDownloadFolder $entry.Folder $directory.FullName
            $finished += $path
            Notify-MusicFolder $path
        }

        # Only remove the manifest and an empty directory that we created.
        [IO.File]::Delete($manifest)
        $remainingWork = $null
        if ([IO.Directory]::GetFileSystemEntries($work).Length -eq 0) {
            [IO.Directory]::Delete($work)
        } else {
            $remainingWork = $work
        }
        [pscustomobject]@{
            Paths = $finished
            WorkDirectory = $remainingWork
            DownloaderExitCode = $downloadExit
        }
    } catch {
        foreach ($path in $finished) {
            Write-Host "Déjà enregistré : $path"
        }
        Write-Warning "Dossier de travail conservé : $work"
        throw
    }
}

function Start-MusicDownloader {
    $mainHeading = 'YxxgSxxl Music Downloader'
    $mainSubtitle = 'Audio et playlists | v1.0.1'
    Initialize-MusicConsole $mainHeading
    Show-MusicHeader $mainHeading $mainSubtitle

    try {
        $tools = Find-DownloadTools
        Offer-DownloaderUpdate $tools['yt-dlp']
    } catch {
        Write-Host "  [ERREUR] $($_.Exception.Message)" -ForegroundColor Red
        if (-not [Console]::IsInputRedirected) {
            $null = Read-MusicInput '  Appuie sur Entrée pour quitter. '
        }
        return 1
    }

    while ($true) {
        $uri = Read-MusicLink
        if (-not $uri) { return 0 }

        $status = 0
        try {
            Show-MusicHeader 'ANALYSE DU LIEN'
            Write-MusicStatus '1/6' 'Détection de la plateforme et du contenu...'
            Write-Host ''
            $source = Get-SourceInfo $tools['yt-dlp'] $uri
            $kind = 'Son unique'
            if ($source.IsPlaylist) { $kind = 'Projet / Playlist' }
            Write-MusicStatus 'OK' "Plateforme : $($source.Platform)" -Color Green
            Write-Host "       Type : $kind" -ForegroundColor DarkGray
            Write-Host ''
            Write-MusicStatus '2/6' 'Choix du dossier de destination...'
            $destination = Select-DownloadDestination
            if (-not $destination) {
                Show-MusicHeader $mainHeading $mainSubtitle
                Write-Host '  Sélection du dossier annulée.'
                Write-Host ''
                continue
            }

            Write-Host ''
            Write-MusicStatus 'OK' 'Destination sélectionnée' -Color Green
            Write-Host "       $destination"
            Write-Host ''
            $download = Save-MusicDownload $uri $destination $source.IsPlaylist $tools
            if ($download.DownloaderExitCode -ne 0) {
                $status = 1
                Show-MusicHeader 'TÉLÉCHARGEMENT PARTIEL' -KeepContent
                Write-MusicStatus '!' "yt-dlp a signalé une erreur (code $($download.DownloaderExitCode))." -Color Yellow
            } else {
                Start-Sleep -Seconds 1
                Show-MusicHeader 'TÉLÉCHARGEMENT TERMINÉ'
            }
            Write-Host "  Plateforme  : $($source.Platform)"
            Write-Host ''
            Write-Host '  Destination :'
            foreach ($path in $download.Paths) {
                Write-Host "  $path"
            }
            if ($download.WorkDirectory) {
                Write-Host ''
                Write-MusicStatus '!' "Fichiers de travail conservés : $($download.WorkDirectory)" -Color Yellow
            }
        } catch {
            $status = 1
            Show-MusicHeader 'ERREUR' -KeepContent
            Write-Host "  [ERREUR] $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host ''
        if ($status -eq 0) {
            Write-MusicStatus 'R' 'Nouveau téléchargement'
        } else {
            Write-MusicStatus 'R' 'Réessayer'
        }
        Write-MusicStatus 'Q' 'Quitter'
        Write-Host ''
        if (-not (Read-MusicRetry)) { return $status }
        Show-MusicHeader $mainHeading $mainSubtitle
    }
}
