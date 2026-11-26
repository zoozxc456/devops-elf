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
iap up <name>...                  在背景開 tunnel（斷線自動重連），console 可以繼續用
iap ps / logs <name> [-f]         列出背景 tunnel／看 gcloud 輸出
iap down <name>... / down --all   關閉背景 tunnel
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
# ---------- background tunnels：每條一個 <name>.pid（pid lport rport instance）與 <name>.log ----------
$stateDir = if ($env:XDG_STATE_HOME) { Join-Path $env:XDG_STATE_HOME 'iap' }
            elseif ($IsWindows) { Join-Path $env:LOCALAPPDATA 'iap' }
            else { Join-Path $HOME '.local/state/iap' }
function Test-IapStateName([string]$Name) { $Name -cmatch '^[A-Za-z0-9_][A-Za-z0-9._-]*$' }
function Read-IapLog([string]$Path) {
    # 背景行程還開著檔案寫入，要用 ReadWrite 共用模式才讀得到
    $stream = [IO.FileStream]::new($Path, 'Open', 'Read', 'ReadWrite, Delete')
    try { [IO.StreamReader]::new($stream).ReadToEnd() } finally { $stream.Dispose() }
}
# 回傳仍在執行的背景 tunnel；pid 檔殘留（行程不在或 pid 被重用）就刪掉
function Get-IapTunnelProcess([string]$Name) {
    if (-not (Test-IapStateName $Name)) { return $null }
    $file = Join-Path $stateDir "$Name.pid"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
    $fields = @(([IO.File]::ReadAllText($file)).Trim() -split '\s+')
    $process = $null
    if ($fields.Count -ge 4 -and $fields[0] -match '^\d+$') {
        $process = Get-Process -Id ([int]$fields[0]) -ErrorAction SilentlyContinue
    }
    if ($process -and $process.ProcessName -like 'pwsh*') {
        return [pscustomobject]@{ Name = $Name; Process = $process; LocalPort = $fields[1]; RemotePort = $fields[2]; Instance = $fields[3] }
    }
    Remove-Item -LiteralPath $file -Force
    return $null
}
function Get-IapTunnelNames {
    if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) { return @() }
    @(Get-ChildItem -LiteralPath $stateDir -Filter '*.pid' -File | ForEach-Object BaseName)
}
if ($command -eq 'ps') {
    $rows = @(foreach ($name in Get-IapTunnelNames) {
        $tunnel = Get-IapTunnelProcess $name
        if ($tunnel) {
            [pscustomobject]@{
                Name = $name; PID = $tunnel.Process.Id
                Local = "localhost:$($tunnel.LocalPort)"; Remote = "$($tunnel.Instance):$($tunnel.RemotePort)"
                Uptime = ((Get-Date) - $tunnel.Process.StartTime).ToString('hh\:mm\:ss')
            }
        }
    })
    if ($rows.Count) { $rows | Format-Table -AutoSize } else { '沒有背景 tunnel' }
    return
}
if ($command -eq 'down') {
    $names = @($arguments | Select-Object -Skip 1)
    $all = $names.Count -eq 1 -and $names[0] -in @('--all','-All')
    if ($all) { $names = @(Get-IapTunnelNames) }
    elseif (-not $names.Count) { throw '用法：iap down <name>... 或 iap down --all' }
    $failed = @()
    foreach ($name in $names) {
        $tunnel = Get-IapTunnelProcess ([string]$name)
        if (-not $tunnel) { if (-not $all) { $failed += $name }; continue }
        try { $tunnel.Process.Kill($true) } catch { }
        [void]$tunnel.Process.WaitForExit(5000)
        Remove-Item -LiteralPath (Join-Path $stateDir "$name.pid") -Force -ErrorAction SilentlyContinue
        Write-Host "✔ [$name] 已關閉"
    }
    if (-not $names.Count) { '沒有背景 tunnel' }
    if ($failed.Count) { throw "沒有在背景執行：$($failed -join ' ')" }
    return
}
if ($command -eq 'logs') {
    $name = if ($arguments.Count -ge 2) { [string]$arguments[1] } else { '' }
    $log = Join-Path $stateDir "$name.log"
    if (-not (Test-IapStateName $name) -or -not (Test-Path -LiteralPath $log -PathType Leaf)) {
        throw "沒有 $name 的背景 tunnel 紀錄（iap ps 看清單）"
    }
    $follow = @($arguments | Select-Object -Skip 2) | Where-Object { $_ -in @('-f','-Wait','--follow') }
    if ($follow) { Get-Content -LiteralPath $log -Tail 50 -Wait } else { Get-Content -LiteralPath $log -Tail 50 }
    return
}
function Show-Endpoints($Entry) {
    foreach ($endpoint in $Entry.Endpoints) {
        Write-Host ('  ' + ([string]$endpoint).Replace('{port}', [string]$Entry.LocalPort).Replace('{rport}', [string]$Entry.RemotePort))
    }
}
function Get-IapFlags($Entry) {
    $flags = @()
    if ($Entry.Project -and $Entry.Project -ne '-') { $flags += @('--project', [string]$Entry.Project) }
    if ($Entry.Zone -and $Entry.Zone -ne '-') { $flags += @('--zone', [string]$Entry.Zone) }
    $flags
}
function Assert-IapTunnelPorts($Entry) {
    foreach ($port in @($Entry.RemotePort, $Entry.LocalPort)) {
        if ([string]$port -notmatch '^[1-9][0-9]{0,4}$' -or [int]$port -gt 65535) { throw 'Tunnel port 必須為 1–65535。' }
    }
}
function Test-IapPortBusy([int]$Port) {
    $client = [Net.Sockets.TcpClient]::new()
    try { return $client.ConnectAsync('127.0.0.1', $Port).Wait(500) } catch { return $false } finally { $client.Dispose() }
}
function Start-IapTunnel($Entry) {
    $name = [string]$Entry.Name
    if ($Entry.Type -cne 'tunnel') { Write-Host "iap: $name 是 $($Entry.Type)，背景模式只支援 tunnel（ssh 請用 iap $name）"; return $false }
    if (-not (Test-IapStateName $name)) { Write-Host "iap: 背景模式的名稱只能用英數字與 . _ -：$name"; return $false }
    Assert-IapTunnelPorts $Entry
    $existing = Get-IapTunnelProcess $name
    if ($existing) { Write-Host "• [$name] 已在背景執行（PID $($existing.Process.Id)）  localhost:$($Entry.LocalPort)"; return $true }
    if (Test-IapPortBusy ([int]$Entry.LocalPort)) { Write-Host "iap: [$name] localhost:$($Entry.LocalPort) 已被佔用"; return $false }
    [void][IO.Directory]::CreateDirectory($stateDir)
    $log = Join-Path $stateDir "$name.log"
    $pidFile = Join-Path $stateDir "$name.pid"
    Write-IapPrivateFile $log ''
    $gcloudArgs = @('compute', 'start-iap-tunnel', [string]$Entry.Instance, [string]$Entry.RemotePort,
                    "--local-host-port=localhost:$($Entry.LocalPort)") + @(Get-IapFlags $Entry)
    # 參數用 JSON 帶進 -EncodedCommand，不經過命令列拼接；斷線 3 秒後自動重連
    $payload = (@{ Log = $log; Args = $gcloudArgs } | ConvertTo-Json -Compress).Replace("'", "''")
    $loop = @"
`$p = '$payload' | ConvertFrom-Json
while (`$true) {
    & gcloud @(`$p.Args) *>> `$p.Log
    "[iap] tunnel 結束（exit `$LASTEXITCODE），3 秒後重連…" | Out-File -Append -LiteralPath `$p.Log
    Start-Sleep -Seconds 3
}
"@
    $pwshArgs = @('-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand',
                  [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($loop)))
    $pwsh = (Get-Process -Id $PID).Path
    $process = if ($IsWindows) {
        Start-Process -FilePath $pwsh -ArgumentList $pwshArgs -WindowStyle Hidden -PassThru
    } else {
        # nohup：關掉終端機也不會跟著結束
        Start-Process -FilePath 'nohup' -ArgumentList (@($pwsh) + $pwshArgs) -RedirectStandardOutput '/dev/null' -PassThru
    }
    Write-IapPrivateFile $pidFile "$($process.Id) $($Entry.LocalPort) $($Entry.RemotePort) $($Entry.Instance)"
    Write-Host "→ [$name] localhost:$($Entry.LocalPort) ⇢ $($Entry.Instance):$($Entry.RemotePort)  背景連線中…"
    $timeout = if ($env:IAP_UP_TIMEOUT) { [int]$env:IAP_UP_TIMEOUT } else { 30 }
    $deadline = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $deadline) {
        $text = Read-IapLog $log
        if ($text -like '*Listening on port*') {
            Write-Host "✔ [$name] 已連線（背景 PID $($process.Id)）  localhost:$($Entry.LocalPort) ⇢ $($Entry.Instance):$($Entry.RemotePort)"
            Show-Endpoints $Entry
            return $true
        }
        if ($text -match '(?m)^\[iap\] tunnel 結束' -or $process.HasExited) { break }
        Start-Sleep -Milliseconds 200
    }
    try { $process.Kill($true) } catch { }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Write-Host "iap: [$name] tunnel 沒有建立，gcloud 輸出："
    (Read-IapLog $log) -split '\r?\n' | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
    return $false
}
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
if ($command -eq 'up') {
    $names = @($arguments | Select-Object -Skip 1)
    if (-not $names.Count) { throw '用法：iap up <name>...' }
    $ok = $true
    foreach ($name in $names) {
        $found = @($entries | Where-Object { $_.Name -ceq [string]$name })
        if ($found.Count -ne 1) { Write-Host "iap: 找不到唯一連線：$name（iap ls 看清單）"; $ok = $false; continue }
        if (-not (Start-IapTunnel $found[0])) { $ok = $false }
    }
    if (-not $ok) { exit 1 }
    return
}
if ($command -in @('ls','list')) {
    $entries | Format-Table Name,Type,Project,Zone,Instance,RemotePort,LocalPort -AutoSize
    return
}
if ($command -eq '') {
    if (-not $entries.Count) { throw '設定檔是空的，請執行 iap setup。' }
    for ($index = 0; $index -lt $entries.Count; $index++) { Write-Host "$($index + 1). $($entries[$index].Name) [$($entries[$index].Type)]" }
    do {
        $choice = Read-Host '選哪台？（多選用逗號分隔，會在背景開 tunnel）'
        $numbers = @(([string]$choice).Trim() -split '[,\s]+' | ForEach-Object { $number = 0; if ([int]::TryParse($_, [ref]$number)) { $number } else { -1 } })
    } until ($numbers.Count -and -not ($numbers | Where-Object { $_ -lt 1 -or $_ -gt $entries.Count }))
    if ($numbers.Count -gt 1) {
        $ok = $true
        foreach ($number in $numbers) { if (-not (Start-IapTunnel $entries[$number - 1])) { $ok = $false } }
        if (-not $ok) { exit 1 }
        return
    }
    $selected = $entries[$numbers[0] - 1]
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
if ($command -eq 'show') { Show-Endpoints $selected; return }
$flags = @(Get-IapFlags $selected)
switch -CaseSensitive ($selected.Type) {
    'ssh' {
        Write-Host "→ [$($selected.Name)] ssh $($selected.Instance) via IAP"
        Show-Endpoints $selected
        & gcloud compute ssh $selected.Instance @flags --tunnel-through-iap @extra
    }
    'tunnel' {
        Assert-IapTunnelPorts $selected
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
