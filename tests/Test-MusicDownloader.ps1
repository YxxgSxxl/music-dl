param([string]$YtDlpPath)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$batch = Join-Path (Split-Path -Parent $PSScriptRoot) 'music_dl.bat'
$lines = [IO.File]::ReadAllLines($batch, [Text.Encoding]::UTF8)
$marker = [Array]::IndexOf($lines, '# MUSIC_DL_POWERSHELL')
. ([ScriptBlock]::Create($lines[($marker + 1)..($lines.Length - 1)] -join [Environment]::NewLine))

if (-not $YtDlpPath) {
    $YtDlpPath = (Get-Command yt-dlp.exe -CommandType Application | Select-Object -First 1).Source
}
$uri = [Uri]'https://example.invalid/track'
$temp = [IO.Path]::GetTempPath().TrimEnd('\')
$root = [IO.Directory]::CreateDirectory((Join-Path $temp ('music-dl-test-' + [Guid]::NewGuid().ToString('N'))))

function Get-SimulatedFilename {
    param([hashtable]$Metadata, [bool]$IsPlaylist, [string]$WorkDirectory)

    $fixture = Join-Path $root.FullName 'track.json'
    $manifest = Join-Path $WorkDirectory 'completed.jsonl'
    [IO.File]::WriteAllText($fixture, ($Metadata | ConvertTo-Json -Compress))
    $arguments = @(Get-MusicDownloadArguments $uri $WorkDirectory $manifest $IsPlaylist)
    # Replace only the final URL with an offline input. Keep the production filename options.
    $arguments = $arguments[0..($arguments.Count - 3)] +
        @('--load-info-json', $fixture, '--simulate', '--print', 'filename')
    $filename = @(Invoke-Downloader $YtDlpPath $arguments)
    if ($LASTEXITCODE -ne 0 -or $filename.Count -ne 1) {
        throw "Expected one simulated path, got $($filename -join ', ')."
    }
    if ([IO.Path]::IsPathRooted($filename[0])) { return $filename[0] }
    Join-Path $WorkDirectory $filename[0]
}

try {
    $version = Get-DownloaderVersion $YtDlpPath
    $title = 'T' + [char]0x00E9 + 'n' + [char]0x00E9 + 'breux'
    $track = @{
        id = 'abc123'
        title = "$title ."
        ext = 'm4a'
        url = 'https://example.invalid/track.m4a'
        playlist = 'Nocturnes .'
        playlist_id = 'playlist-id'
        playlist_index = 7
    }
    $single = Get-SimulatedFilename $track $false $root.FullName
    if ($single -cne (Join-Path $root.FullName "$title\$title.m4a")) {
        throw "Unexpected track name: $single"
    }
    $playlist = Get-SimulatedFilename $track $true $root.FullName
    if ($playlist -cne (Join-Path $root.FullName "Nocturnes\007 - $title.m4a")) {
        throw "Unexpected playlist name: $playlist"
    }

    $track.title = 'NUL.txt'
    $track.playlist = 'AUX'
    $reserved = Get-SimulatedFilename $track $true $root.FullName
    if ($reserved -cne (Join-Path $root.FullName '_AUX\007 - _NUL.txt.m4a')) {
        throw "Expected reserved Windows names to be prefixed: $reserved"
    }

    $longWork = Join-Path $root.FullName ('x' * [Math]::Max(1, 145 - $root.FullName.Length))
    $track.title = 'Long / track: ' + ([char]::ConvertFromUtf32(0x1F3B5) * 100)
    $track.playlist = 'Long playlist ' + ('x' * 300)
    $track.playlist_index = 100
    $path = Get-SimulatedFilename $track $true $longWork
    $leaf = Split-Path -Leaf $path
    if ($path.Length -gt 240 -or $leaf -notlike '100 - Long *' -or $leaf -match '[:/]') {
        throw "Unexpected path for a long Windows destination: $path"
    }
    $tooDeep = Join-Path $root.FullName ('x' * 230)
    try {
        $null = Get-MusicDownloadArguments $uri $tooDeep (Join-Path $tooDeep 'completed.jsonl') $true
        throw 'Expected an error for the very long destination.'
    } catch {
        if ($_.Exception.Message -notlike 'Destination trop longue*') { throw }
    }

    # Simulate a partially completed playlist with one playable file and an unfinished file.
    function Invoke-Downloader {
        param([string]$Executable, [string[]]$Arguments)

        $work = $Arguments[[Array]::IndexOf($Arguments, '-P') + 1]
        $manifest = $Arguments[[Array]::IndexOf($Arguments, '--print-to-file') + 2]
        $folder = [IO.Directory]::CreateDirectory((Join-Path $work 'Nocturnes'))
        $file = Join-Path $folder.FullName '007 - Track.m4a'
        [IO.File]::WriteAllText($file, 'completed')
        [IO.File]::WriteAllText((Join-Path $folder.FullName '008 - Unavailable.jpg'), 'thumbnail')
        [IO.File]::WriteAllText((Join-Path $work 'unfinished.part'), 'partial')
        $record = @{ filepath = $file; webpage_url = $uri.AbsoluteUri } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($manifest, $record)
        $global:LASTEXITCODE = 1
    }
    function Move-DownloadedCover { throw 'Simulated thumbnail failure.' }
    function Notify-MusicFolder {}

    $existing = [IO.Directory]::CreateDirectory((Join-Path $root.FullName 'Nocturnes'))
    $original = Join-Path $existing.FullName '007 - Track.m4a'
    [IO.File]::WriteAllText($original, 'original')
    $result = Save-MusicDownload $uri $root.FullName $true @{ 'yt-dlp' = $YtDlpPath }
    $saved = Join-Path $root.FullName 'Nocturnes (2)'
    if ($result.DownloaderExitCode -ne 1 -or $result.Paths.Count -ne 1 -or $result.Paths[0] -ne $saved) {
        throw 'Expected one saved folder and a partial result.'
    }
    if ([IO.File]::ReadAllText($original) -ne 'original' -or
        [IO.File]::ReadAllText((Join-Path $saved '007 - Track.m4a')) -ne 'completed' -or
        -not [IO.File]::Exists((Join-Path $result.WorkDirectory 'unfinished.part'))) {
        throw 'The completed, existing or recoverable file was lost.'
    }
    $pendingCover = @(Get-ChildItem -LiteralPath $result.WorkDirectory -Filter '008 - Unavailable.jpg' -File -Recurse)
    if ($pendingCover.Count -ne 1 -or [IO.File]::Exists((Join-Path $saved '008 - Unavailable.jpg'))) {
        throw 'The incomplete item did not stay in the working directory.'
    }
    $shortcut = [IO.File]::ReadAllLines((Join-Path $saved '_assets\Nocturnes.url'))
    if ($shortcut.Count -ne 2 -or $shortcut[1] -ne "URL=$($uri.AbsoluteUri)") {
        throw 'The original-page shortcut did not survive the thumbnail failure.'
    }

    Write-Output "Passed with PowerShell $($PSVersionTable.PSVersion) and yt-dlp $version."
} finally {
    if ($root.Parent.FullName -eq $temp -and $root.Name -like 'music-dl-test-*') {
        Remove-Item -LiteralPath $root.FullName -Recurse -Force
    }
}
