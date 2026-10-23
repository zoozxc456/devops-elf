#Requires -Version 7.2
# Native PowerShell client; arguments are passed to gcloud as literal values.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0
$runtimeRoot = if (Test-Path -LiteralPath "$PSScriptRoot/.iap/scripts/common.ps1") { "$PSScriptRoot/.iap" } else { $PSScriptRoot }
. "$runtimeRoot/scripts/common.ps1"
$arguments = @($args)
$command = if ($arguments.Count) { [string]$arguments[0] } else { '' }
if ($command -eq 'export') {
    $output = $null
    for ($i = 1; $i -lt $arguments.Count; $i++) {
        $argument = [string]$arguments[$i]
        if ($argument -in @('-Help','--help','-h')) {
            '用法：iap export [FILE] 或 iap export -Output FILE；保留原始格式，不轉換格式。'
            return
        }
        if ($argument -in @('-Output','--output','-o')) {
            $i++
            if ($i -ge $arguments.Count -or -not $arguments[$i] -or $null -ne $output) { throw '請指定一個輸出檔案。' }
            $output = [string]$arguments[$i]
        } else {
            if ($argument.StartsWith('-') -or $null -ne $output) { throw '用法：iap export [FILE] 或 iap export -Output FILE' }
            $output = $argument
        }
    }
    $config = Get-IapConfigPath
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw "找不到設定檔：$config" }
    if ($null -eq $output) { Write-Output -NoEnumerate ([IO.File]::ReadAllText($config)); return }
    $output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($output)
    Assert-IapRegularTarget $output
    $sourcePath = (Get-Item -LiteralPath $config).FullName
    $comparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
    if ($comparer.Equals($sourcePath, $output)) { throw '輸出不可為目前設定檔本身。' }
    $original = $null
    if (Test-Path -LiteralPath $output) {
        $original = [IO.File]::ReadAllBytes($output)
        $answer = Read-Host "已有 ${output}，覆寫前將備份，是否繼續？ [y/N]"
        if ($null -eq $answer -or $answer -notmatch '^(y|yes)$') { return }
    }
    [void][IO.Directory]::CreateDirectory((Split-Path $output -Parent))
    $staged = "$output.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        Write-IapPrivateFile $staged ''
        [IO.File]::WriteAllBytes($staged, [IO.File]::ReadAllBytes($config))
        Assert-IapRegularTarget $output
        if ($null -ne $original) {
            if (-not (Test-Path -LiteralPath $output) -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($output)) -cne [Convert]::ToBase64String($original)) {
                throw '輸出檔在操作期間已變更，未覆寫。'
            }
            $backup = "$output.backup-$([guid]::NewGuid().ToString('N'))"
            Write-IapPrivateFile $backup ''
            [IO.File]::WriteAllBytes($backup, $original)
            Write-Host "原檔備份：$backup"
        } elseif (Test-Path -LiteralPath $output) { throw '輸出檔在操作期間已建立，未覆寫。' }
        [IO.File]::Move($staged, $output, $true)
    } finally {
        if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Force }
    }
    Write-Host "已匯出：$output"
    return
}
if ($command -in @('remove','reset','uninstall') -or ($command -eq 'edit' -and $arguments.Count -gt 1)) {
    $options = @{ Action = $command; Config = (Get-IapConfigPath); BinDir = $PSScriptRoot }
    if ($arguments.Count -gt 2) { throw "用法：iap $command [name]" }
    if ($arguments.Count -eq 2) { $options.Name = [string]$arguments[1] }
    & "$runtimeRoot/scripts/manage.ps1" @options
    return
}
if ($command -in @('setup','new')) {
    $setupOptions = @{}
    if ($command -eq 'new') { $setupOptions.New = $true }
    for ($i = 1; $i -lt $arguments.Count; $i++) {
        switch ([string]$arguments[$i]) {
            { $_ -in @('-Config','--config') } {
                $i++
                if ($i -ge $arguments.Count -or -not $arguments[$i]) { throw '缺少 -Config PATH' }
                $setupOptions.Config = [string]$arguments[$i]
            }
            { $_ -in @('-Help','--help','-h') } { $setupOptions.Help = $true }
            default { throw "未知 setup 參數：$_" }
        }
    }
    & "$runtimeRoot/scripts/setup.ps1" @setupOptions
    return
}
if ($command -in @('version','-v','--version')) { 'iap 0.4.1 (PowerShell)'; return }
if ($command -in @('-h','--help','help')) {
    @'
iap [name [gcloud/ssh arguments]]  互動選單或直接連線
iap help / --help / -h            顯示使用說明
iap export [FILE]                 匯出目前設定（保留原始格式）
iap setup [-Config PATH]          互動設定
iap new [-Config PATH]            新增一組連線，保留既有設定
iap edit <name> / remove <name>    修改／移除指定連線
iap reset / uninstall             清空連線／解除安裝（先確認）
iap ls / names / show <name>      列表／名稱／入口
iap edit / version / update       編輯／版本／更新
PowerShell 7.2+；原生支援純文字、JSON、JSON 語法的 YAML。
一般 YAML 另需 mikefarah yq。import / to-yaml 請使用 Bash 版。
'@
    return
}
if ($command -in @('update','self-update')) {
    $beforeVersion = & "$PSScriptRoot/iap.ps1" version
    if ($runtimeRoot -ne $PSScriptRoot) {
        $record = Join-Path $runtimeRoot 'powershell-source'
        if (-not (Test-Path -LiteralPath $record -PathType Leaf)) { throw '找不到安裝來源紀錄，請從原始碼執行一次 install.ps1 以升級安裝資訊。' }
        $source = [IO.File]::ReadAllText($record).TrimEnd("`r", "`n")
        if (-not $source -or $source -eq $PSScriptRoot -or
            -not (Test-Path -LiteralPath "$source/iap.ps1" -PathType Leaf) -or
            -not (Test-Path -LiteralPath "$source/install.ps1" -PathType Leaf)) {
            throw '安裝來源已移動或刪除，請從新的原始碼目錄重新安裝，以更新來源紀錄；現有連線仍可使用。'
        }
        $hasGit = $null -ne (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)
        $gitSource = $false
        if ($hasGit) {
            & git -C $source rev-parse --show-toplevel 2>$null | Out-Null
            $gitSource = $LASTEXITCODE -eq 0
        }
        if ($gitSource) {
            & "$source/iap.ps1" update
            if ($LASTEXITCODE -ne 0) { throw '更新來源失敗，未更新安裝副本。' }
        } else {
            Write-Host "來源不是 Git checkout，從本機目錄同步：$source"
        }
        & "$source/install.ps1" -BinDir $PSScriptRoot -NoPath
        $afterVersion = & "$PSScriptRoot/iap.ps1" version
        Write-Host "✔ 更新完成：$beforeVersion → $afterVersion"
        $global:LASTEXITCODE = 0
        return
    }
    $repo = & git -C $PSScriptRoot rev-parse --show-toplevel
    if ($LASTEXITCODE -ne 0) { throw '這份 iap 不在 git repo 裡。' }
    $dirty = & git -C $repo status --porcelain
    if ($LASTEXITCODE -ne 0 -or $dirty) { throw '請先處理 repo 裡尚未 commit 的修改。' }
    & git -C $repo pull --ff-only --tags
    if ($LASTEXITCODE -ne 0) { throw 'git pull 失敗。' }
    $afterVersion = & "$PSScriptRoot/iap.ps1" version
    Write-Host "✔ 更新完成：$beforeVersion → $afterVersion"
    return
}
if ($command -in @('import','to-yaml')) { throw '此指令請使用 Bash 版 iap。' }
$config = Get-IapConfigPath
if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw "找不到設定檔：${config}，請先執行 iap setup。" }
if ($command -eq 'edit') {
    $editor = if ($env:EDITOR) { $env:EDITOR } elseif ($IsWindows) { 'notepad.exe' } else { 'vi' }
    & $editor $config
    return
}
$text = [IO.File]::ReadAllText($config)
$entries = [Collections.Generic.List[object]]::new()
if ([IO.Path]::GetExtension($config) -in @('.json','.yaml','.yml')) {
    $data = Read-IapStructuredConfig $config
    $defaults = if ($data['defaults']) { $data['defaults'] } else { @{} }
    foreach ($name in $data['hosts'].Keys) {
        $hostConfig = $data['hosts'][$name]
        if ($null -eq $hostConfig) { $hostConfig = @{} }
        $endpoints = @()
        if ($hostConfig['endpoints'] -is [Collections.IDictionary]) {
            $endpoints = @($hostConfig['endpoints'].GetEnumerator() | ForEach-Object { "$($_.Key)  $($_.Value)" })
        } elseif ($hostConfig['endpoints']) { $endpoints = @($hostConfig['endpoints']) }
        $entries.Add([pscustomobject]@{
            Name = $name; Type = ($hostConfig['type'] ?? 'ssh')
            Project = ($hostConfig['project'] ?? $defaults['project'] ?? '-')
            Zone = ($hostConfig['zone'] ?? $defaults['zone'] ?? '-')
            Instance = ($hostConfig['instance'] ?? $name)
            RemotePort = $hostConfig['remote_port']
            LocalPort = ($hostConfig['local_port'] ?? $hostConfig['remote_port'])
            Endpoints = $endpoints
        })
    }
} else {
    $current = $null
    foreach ($line in ($text -split '\r?\n')) {
        if ($line -match '^\s*(#|$)') { continue }
        if ($line -match '^\s*>\s*(.*)$') {
            if ($null -ne $current) { $current.Endpoints += $Matches[1] }
            continue
        }
        $fields = @($line.Trim() -split '\s+')
        if ($fields.Count -lt 5 -or $fields.Count -gt 7) { throw "無效設定行：$line" }
        $remote = if ($fields.Count -ge 6) { $fields[5] } else { $null }
        $local = if ($fields.Count -ge 7) { $fields[6] } else { $remote }
        $current = [pscustomobject]@{
            Name = $fields[0]; Type = $fields[1]; Project = $fields[2]
            Zone = $fields[3]; Instance = $fields[4]; RemotePort = $remote
            LocalPort = $local; Endpoints = @()
        }
        $entries.Add($current)
    }
}
if ($command -eq 'names') { $entries | ForEach-Object Name; return }
if ($command -in @('ls','list')) {
    $entries | Format-Table Name,Type,Project,Zone,Instance,RemotePort,LocalPort -AutoSize
    return
}
if ($command -eq '') {
    if (-not $entries.Count) { throw '設定檔是空的，請執行 iap setup。' }
    for ($index = 0; $index -lt $entries.Count; $index++) { Write-Host "$($index + 1). $($entries[$index].Name) [$($entries[$index].Type)]" }
    do { $choice = Read-Host '選哪台？'; $number = 0 }
    until ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $entries.Count)
    $selected = $entries[$number - 1]
    $extra = @()
} else {
    $name = if ($command -eq 'show') {
        if ($arguments.Count -lt 2) { throw '用法：iap show <name>' }
        [string]$arguments[1]
    } else { $command }
    $found = @($entries | Where-Object { $_.Name -ceq $name })
    if ($found.Count -ne 1) { throw "找不到唯一連線：$name（iap ls 看清單）" }
    $selected = $found[0]
    $extra = @($arguments | Select-Object -Skip 1)
}
function Show-Endpoints($Entry) {
    foreach ($endpoint in $Entry.Endpoints) {
        Write-Host ('  ' + ([string]$endpoint).Replace('{port}', [string]$Entry.LocalPort).Replace('{rport}', [string]$Entry.RemotePort))
    }
}
if ($command -eq 'show') { Show-Endpoints $selected; return }
$flags = @()
if ($selected.Project -and $selected.Project -ne '-') { $flags += @('--project', [string]$selected.Project) }
if ($selected.Zone -and $selected.Zone -ne '-') { $flags += @('--zone', [string]$selected.Zone) }
switch -CaseSensitive ($selected.Type) {
    'ssh' {
        Write-Host "→ [$($selected.Name)] ssh $($selected.Instance) via IAP"
        Show-Endpoints $selected
        & gcloud compute ssh $selected.Instance @flags --tunnel-through-iap @extra
    }
    'tunnel' {
        foreach ($port in @($selected.RemotePort, $selected.LocalPort)) {
            if ([string]$port -notmatch '^[1-9][0-9]{0,4}$' -or [int]$port -gt 65535) { throw 'Tunnel port 必須為 1–65535。' }
        }
        Write-Host "→ [$($selected.Name)] localhost:$($selected.LocalPort) ⇢ $($selected.Instance):$($selected.RemotePort)"
        if ($selected.Endpoints.Count) {
            Write-Host '  連線入口（tunnel 建立後可用）：'
            Show-Endpoints $selected
        }
        & gcloud compute start-iap-tunnel $selected.Instance $selected.RemotePort "--local-host-port=localhost:$($selected.LocalPort)" @flags 2>&1 |
            ForEach-Object {
                if ([string]$_ -like '*Listening on port*') {
                    Write-Host "✔ [$($selected.Name)] 已連線（Ctrl-C 結束）"
                } else { Write-Host $_ }
            }
    }
    default { throw "不支援的連線類型：$($selected.Type)" }
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
