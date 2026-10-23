#Requires -Version 7.2
<#
.SYNOPSIS
Lookout 互動式設定精靈；只產生設定，不執行部署。
.EXAMPLE
pwsh -File ./scripts/setup.ps1 -Mode ansible
.EXAMPLE
pwsh -File ./scripts/setup.ps1 -Mode agent -OutputDir ./prepared
#>
[CmdletBinding()]
param(
    [ValidateSet('ansible', 'server', 'agent')][string]$Mode,
    [string]$OutputDir = (Split-Path $PSScriptRoot -Parent),
    [switch]$Help
)
Set-PSDebug -Off
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SourceRoot = Split-Path $PSScriptRoot -Parent
$Utf8 = [System.Text.UTF8Encoding]::new($false)
$Work = $null

function Ask([string]$Label, [string]$Default, [scriptblock]$Validate) {
    while ($true) {
        $prompt = if ($Default.Length) { "$Label [$Default]" } else { $Label }
        $value = Read-Host $prompt
        if ([string]::IsNullOrEmpty($value)) { $value = $Default }
        if (& $Validate $value) { return $value }
        Write-Host '格式不符，請重新輸入。'
    }
}
function Confirm([string]$Label, [bool]$Default = $false) {
    while ($true) {
        $hint = if ($Default) { 'Y/n' } else { 'y/N' }
        $value = Read-Host "$Label [$hint]"
        if ([string]::IsNullOrEmpty($value)) { return $Default }
        if ($value -match '^(y|yes)$') { return $true }
        if ($value -match '^(n|no)$') { return $false }
        Write-Host '請輸入 y 或 n。'
    }
}
function Test-Plain([string]$Value) {
    return $Value -notmatch "['\p{Cc}]" -and -not $Value.Contains('{{') -and -not $Value.Contains('{%')
}
$Identifier = { param($v) $v -cmatch '^[A-Za-z][A-Za-z0-9_-]*$' }
$SshHost = { param($v) $v -cmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' }
$Network = { param($v) $v -cmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$' }
$Plain = { param($v) Test-Plain $v }
$Nonempty = { param($v) $v.Length -gt 0 -and (Test-Plain $v) }
$LinuxPath = { param($v) $v -cmatch '^/[A-Za-z0-9_./-]+$' -and $v -ne '/' -and $v -notmatch '/\.\.(/|$)' }
$Positive = { param($v) $v -match '^[1-9][0-9]{0,5}$' }
function Test-IPv4([string]$Value) {
    if ($Value -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $false }
    foreach ($octet in $Value.Split('.')) {
        if (($octet.Length -gt 1 -and $octet.StartsWith('0')) -or [int]$octet -gt 255) { return $false }
    }
    return $true
}
$IPv4 = { param($v) Test-IPv4 $v }
$ServerIp = { param($v) (Test-IPv4 $v) -and $v -notmatch '^127\.' -and $v -notin @('0.0.0.0', '192.0.2.10') }
function Get-Plugins {
    if (Confirm '啟用 Odoo 插件？') { 'odoo' }
    if (Confirm '啟用 Nginx 插件？') { 'nginx' }
}
function Get-Password {
    while ($true) {
        $first = $null; $second = $null
        try {
            $first = Read-Host 'Grafana 管理員密碼（不顯示，不能含單引號或換行）' -AsSecureString
            $second = Read-Host '再次輸入密碼' -AsSecureString
            $a = [Net.NetworkCredential]::new('', $first).Password
            $b = [Net.NetworkCredential]::new('', $second).Password
            if ($a.Length -gt 0 -and $a -cne 'CHANGE_ME' -and $a -ceq $b -and (Test-Plain $a)) { return $a }
            Write-Host '密碼不符、為空或含不支援的字元，請重新輸入。'
        } finally {
            if ($null -ne $first) { $first.Dispose() }
            if ($null -ne $second) { $second.Dispose() }
            $a = $null; $b = $null
        }
    }
}
function Set-PrivatePath([string]$Path, [bool]$Directory = $false) {
    if ($IsWindows) {
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = if ($Directory) { [Security.AccessControl.DirectorySecurity]::new() } else { [Security.AccessControl.FileSecurity]::new() }
        $acl.SetOwner($user)
        $acl.SetAccessRuleProtection($true, $false)
        if ($Directory) {
            $rule = [Security.AccessControl.FileSystemAccessRule]::new($user, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        } else {
            $rule = [Security.AccessControl.FileSystemAccessRule]::new($user, 'FullControl', 'Allow')
        }
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $Path -AclObject $acl
    } else {
        $permissions = if ($Directory) { 'UserRead,UserWrite,UserExecute' } else { 'UserRead,UserWrite' }
        [IO.File]::SetUnixFileMode($Path, [IO.UnixFileMode]$permissions)
    }
}
function Write-PrivateText([string]$Path, [string]$Content) {
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    [IO.File]::WriteAllText($Path, '', $Utf8)
    Set-PrivatePath $Path
    [IO.File]::WriteAllText($Path, $Content, $Utf8)
}
function Check-Replacement([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "拒絕覆寫目錄或連結：$Path" }
        return (Confirm "已有 $Path，將重建並備份原檔，是否繼續？")
    }
    return $true
}
function Publish-Text([string]$Path, [string]$Content) {
    if (Test-Path -LiteralPath $Path) {
        $backup = "$Path.backup-$([guid]::NewGuid().ToString('N'))"
        Write-PrivateText $backup ([IO.File]::ReadAllText($Path))
        Write-Host "原檔備份：$backup"
    }
    $staged = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        Write-PrivateText $staged $Content
        [IO.File]::Move($staged, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Force }
    }
    Write-Host "已寫入：$Path"
}
function Get-ServerSettings {
    $settings = [ordered]@{
        lookout_server_ip = Ask '監控主機內網／VPN IPv4（不能填 localhost）' '10.0.0.10' $ServerIp
        grafana_bind_addr = Ask 'Grafana 綁定 IPv4' '127.0.0.1' $IPv4
        grafana_root_url = Ask 'Grafana 瀏覽器網址' 'http://localhost:3000' { param($v) $v -match '^https?://\S+$' -and (Test-Plain $v) }
        grafana_timezone = Ask 'Grafana 時區' 'browser' { param($v) $v -in @('browser','UTC') -or $v -cmatch '^[A-Za-z_+-]+(/[A-Za-z0-9_+-]+)+$' }
        grafana_admin_user = Ask 'Grafana 管理員帳號' 'admin' $Identifier
        prometheus_retention = (Ask 'Prometheus 保留天數' '30' $Positive) + 'd'
    }
    $hours = Ask 'Loki prod log 保留小時（至少 24）' '720' { param($v) $v -match '^[1-9][0-9]{0,5}$' -and [int]$v -ge 24 }
    $nonprod = Ask 'Loki 非 prod log 保留小時（至少 24，且不超過 prod）' ([Math]::Min(168, [int]$hours).ToString()) { param($v) $v -match '^[1-9][0-9]{0,5}$' -and [int]$v -ge 24 -and [int]$v -le [int]$hours }
    $settings.loki_retention = $hours + 'h'
    $settings.loki_retention_nonprod = $nonprod + 'h'
    return $settings
}
function Get-Python {
    foreach ($name in @('python3', 'python', 'py')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $command -or $command.Source -match 'WindowsApps') { continue }
        $prefix = @()
        if ($name -eq 'py') { $prefix = @('-3') }
        $check = @($prefix) + @('-c', 'import sys; sys.exit(0 if sys.version_info.major == 3 else 1)')
        & $command.Source @check *> $null
        if ($LASTEXITCODE -eq 0) { return @{ Exe = $command.Source; Prefix = $prefix } }
    }
    throw '請先安裝 Python 3，並將 python / python3 / py 加入 PATH。'
}
function Convert-WslPath([string]$Path) {
    $result = & wsl.exe --exec wslpath -a -u $Path
    if ($LASTEXITCODE -ne 0) { throw 'WSL 路徑轉換失敗，請確認預設 WSL 發行版已安裝。' }
    return ($result -join '').Trim()
}
function Encrypt-Vault([string]$PlainPath, [string]$EncryptedPath) {
    if ($IsWindows) {
        $linuxPlain = Convert-WslPath $PlainPath
        $linuxEncrypted = Convert-WslPath $EncryptedPath
        & wsl.exe --exec ansible-vault encrypt --output $linuxEncrypted $linuxPlain | Out-Host
    } else {
        & ansible-vault encrypt --output $EncryptedPath $PlainPath | Out-Host
    }
    if ($LASTEXITCODE -ne 0) { throw 'Vault 加密失敗，未發布設定。' }
    $cipher = [IO.File]::ReadAllText($EncryptedPath)
    if (-not $cipher.StartsWith('$ANSIBLE_VAULT;')) { throw 'Vault 產物不是加密內容，未發布設定。' }
    return $cipher
}
function Show-Help {
    Write-Host @'
用法：pwsh -File ./scripts/setup.ps1 [-Mode ansible|server|agent] [-OutputDir PATH]
不帶模式會顯示選單。需要 PowerShell 7.2+。
Ansible：產生 inventory.local.yml 與加密 Vault。Windows 需 WSL 內的 ansible-vault。
Server / Agent：原生產生 .env 與插件產物，需要本機 Python 3。
只建立設定，不會 SSH、安裝套件或啟動服務。OutputDir 不包含程式碼。
'@
}

try {
    if ($Help) { Show-Help; return }
    if (-not $Mode) {
        Write-Host "Lookout 設定精靈`n1. Ansible 部署設定`n2. Server .env`n3. Agent .env"
        $choice = Ask '選擇模式' '1' { param($v) $v -in @('1','2','3') }
        $Mode = @{'1'='ansible'; '2'='server'; '3'='agent'}[$choice]
    }
    $Mode = $Mode.ToLowerInvariant()
    $OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
    if ($Mode -eq 'ansible') {
        if ($IsWindows) {
            if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'Ansible 模式需要 WSL，請先在 WSL 安裝 Python 3 與 ansible-core。' }
            & wsl.exe --exec sh -c 'command -v ansible-vault >/dev/null'
            if ($LASTEXITCODE -ne 0) { throw '請先在預設 WSL 發行版安裝 ansible-core，確認 ansible-vault 在 WSL 的 PATH。' }
            Write-Host 'Windows 使用 WSL 的 ansible-vault 加密；部署指令也必須在 Linux／WSL 中執行。'
        } elseif (-not (Get-Command ansible-vault -ErrorAction SilentlyContinue)) {
            throw '請先安裝 ansible-core，確認 ansible-vault 在 PATH。'
        }
        $target = Join-Path $OutputDir 'deploy/inventory.local.yml'
    } else {
        $python = Get-Python
        $target = Join-Path $OutputDir "$Mode/.env"
    }
    if (-not (Check-Replacement $target)) { Write-Host '已取消，原檔未變更。'; return }
    $Work = Join-Path ([IO.Path]::GetTempPath()) ('lookout-setup-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($Work)
    Set-PrivatePath $Work $true

    if ($Mode -eq 'ansible') {
        $vault = Join-Path $OutputDir 'deploy/group_vars/all/vault.yml'
        $newVault = -not (Test-Path -LiteralPath $vault)
        if (-not $newVault) {
            $item = Get-Item -LiteralPath $vault -Force
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not ([IO.File]::ReadAllText($vault).StartsWith('$ANSIBLE_VAULT;'))) { throw '既有 Vault 不是加密的一般檔案，請先整理或加密。' }
            Write-Host '保留既有加密 Vault（Grafana 密碼與 DB／通知 secrets）。'
        }
        $sshUser = Ask 'SSH 使用者' 'deploy' $Identifier
        $serverName = Ask '監控主機 inventory 名稱' 'monitoring' $Identifier
        $sshAddress = Ask '監控主機 SSH 位址（IP 或 DNS）' '10.0.0.10' $SshHost
        $remoteRoot = Ask '遠端 Linux 部署目錄' '/opt/lookout' $LinuxPath
        $settings = Get-ServerSettings
        $dataDir = Ask '遠端監控資料目錄（磁碟須已掛好）' "$remoteRoot/server/data" $LinuxPath
        $plugins = @(Get-Plugins)
        $serverAgent = Confirm '監控主機也部署 Agent，監控自身資源？' $true
        if ($serverAgent) { $serverNetwork = Ask '監控主機 Agent Docker 網路（須已存在）' 'app' $Network }
        $agentCount = [int](Ask '另外加入幾台應用 Agent 主機（0–50）' '1' { param($v) $v -match '^([0-9]|[1-4][0-9]|50)$' })
        function New-HostVars([string]$Address) {
            return [ordered]@{ ansible_host=$Address; ansible_user=$sshUser; lookout_root=$remoteRoot; lookout_server_ip=$settings.lookout_server_ip; lookout_plugins=@($plugins) }
        }
        $hosts = [ordered]@{}
        $agents = [ordered]@{}
        $serverVars = New-HostVars $sshAddress
        foreach ($key in $settings.Keys) { $serverVars[$key] = $settings[$key] }
        $serverVars.lookout_data_dir = $dataDir
        if ($serverAgent) { $agents[$serverName]=@{}; $serverVars.app_network=$serverNetwork; $serverVars.host_role='prod' }
        $hosts[$serverName]=$serverVars
        for ($i=1; $i -le $agentCount; $i++) {
            Write-Host "`n應用 Agent $i/$agentCount"
            do {
                $name = Ask 'inventory 名稱（須唯一）' "app-$i" $Identifier
                if ($hosts.Contains($name)) { Write-Host '名稱已存在，請換一個。' }
            } while ($hosts.Contains($name))
            $address = Ask 'SSH 位址（IP 或 DNS）' "10.0.0.$(20+$i)" $SshHost
            $role = Ask '主機環境／角色' 'prod' $Identifier
            $appNetwork = Ask '應用 Docker 網路（須已存在）' 'app' $Network
            $envs = Ask '允許收集的環境 regex' $role $Nonempty
            $vars = New-HostVars $address
            $vars.host_role=$role; $vars.app_network=$appNetwork; $vars.lookout_envs=$envs
            $hosts[$name]=$vars; $agents[$name]=@{}
        }
        $serverHosts=[ordered]@{}; $serverHosts[$serverName]=@{}
        $inventory=[ordered]@{ all=[ordered]@{ children=[ordered]@{ lookout_server=@{hosts=$serverHosts}; lookout_agent=@{hosts=$agents} }; hosts=$hosts } }
        # JSON is valid YAML and requires no extra serializer or module.
        $inventoryText=($inventory | ConvertTo-Json -Depth 20) + "`n"
        Write-Host "監控主機：$serverName（$($settings.lookout_server_ip)），額外 Agent：$agentCount 台"
        if ($newVault) {
            $password = Get-Password
            $plainPath = Join-Path $Work 'vault.plain.yml'
            try {
                Write-PrivateText $plainPath ("vault_grafana_admin_password: !unsafe '" + $password.Replace("'", "''") + "'`nvault_alertmanager_secrets: {}`nvault_lookout_agent_env: {}`n")
                $password=$null
                Write-Host '接著設定 Vault 加密密碼，部署時使用這組密碼。'
                $cipher = Encrypt-Vault $plainPath (Join-Path $Work 'vault.yml')
                Publish-Text $vault $cipher
            } finally {
                $password=$null
                if (Test-Path -LiteralPath $plainPath) { Remove-Item -LiteralPath $plainPath -Force }
            }
        }
        Publish-Text $target $inventoryText
        Write-Host "`n在 Linux 控制端的 deploy/ 執行以下指令（Windows 使用 WSL）："
        Write-Host 'ansible-galaxy collection install -r requirements.yml -p .collections'
        Write-Host 'ansible all -i inventory.local.yml -m ping --ask-vault-pass'
        Write-Host 'ansible-playbook -i inventory.local.yml site.yml --syntax-check --ask-vault-pass'
        Write-Host 'ansible-playbook -i inventory.local.yml site.yml --ask-vault-pass'
        Write-Host 'sudo 需要密碼時加 --ask-become-pass；SSH key 使用控制端的 ssh-agent 或 --private-key。'
    } else {
        $values = [ordered]@{}
        if ($Mode -eq 'server') {
            $settings = Get-ServerSettings
            $dataDir = Ask '目標 Linux 主機上的監控資料目錄（非 Windows 路徑）' '/opt/lookout/server/data' $LinuxPath
            $plugins = @(Get-Plugins)
            $password=Get-Password
            $values.BIND_ADDR=$settings.lookout_server_ip
            $values.GRAFANA_BIND_ADDR=$settings.grafana_bind_addr
            $values.GRAFANA_ADMIN_USER=$settings.grafana_admin_user
            $values.GRAFANA_ADMIN_PASSWORD=$password
            $values.GRAFANA_ROOT_URL=$settings.grafana_root_url
            $values.GRAFANA_TIMEZONE=$settings.grafana_timezone
            $values.PROMETHEUS_RETENTION=$settings.prometheus_retention
            $values.LOKI_RETENTION=$settings.loki_retention
            $values.LOKI_RETENTION_NONPROD=$settings.loki_retention_nonprod
            $values.LOOKOUT_DATA_DIR=$dataDir
            $password=$null
        } else {
            $values.HOST_NAME=Ask '這台 Agent 的唯一名稱' 'app-01' $Identifier
            $values.HOST_ROLE=Ask '主機環境／角色' 'prod' $Identifier
            $values.APP_NETWORK=Ask '應用 Docker 網路（須已存在）' 'app' $Network
            $values.LOOKOUT_ENVS=Ask '允許收集的環境 regex' $values.HOST_ROLE $Nonempty
            $values.LOOKOUT_CONTAINERS=Ask '依名稱收 log 的容器 regex（可留空）' '' $Plain
            $address=Ask '監控主機內網／VPN IPv4' '10.0.0.10' $ServerIp
            $values.LOKI_PUSH_URL="http://${address}:3100/loki/api/v1/push"
            $values.PROMETHEUS_REMOTE_WRITE_URL="http://${address}:9090/api/v1/write"
            $plugins=@(Get-Plugins)
        }
        $pluginArgs=@($python.Prefix) + @((Join-Path $SourceRoot 'scripts/plugins.py'), 'apply', '--output', $OutputDir) + @($plugins)
        & $python.Exe @pluginArgs | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '插件組合失敗，未發布 .env。' }
        $lines = foreach ($key in $values.Keys) { "${key}='$($values[$key])'" }
        Publish-Text $target (($lines -join "`n") + "`n")
        $values.Clear()
        Write-Host "`n設定完成。將設定與 generated/ 放進目標 Linux 主機的完整 Lookout 目錄。"
        Write-Host "在目標 Linux 的 lookout/ 設定權限：chmod 600 $Mode/.env"
        if ($Mode -eq 'server') { Write-Host "先在 Linux 的 lookout/ 執行：sudo scripts/prepare-data.sh $dataDir" }
        Write-Host "在目標主機的 $Mode/ 執行：docker compose config --quiet，確認後再 docker compose up -d。"
        Write-Host '應用 label／log 格式仍須自行設定；變更插件後須重建對應容器。'
    }
} catch {
    # Do not print invocation context or variable values: they could contain secrets.
    Write-Host ('設定失敗：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($null -ne $Work -and (Test-Path -LiteralPath $Work)) { Remove-Item -LiteralPath $Work -Recurse -Force }
}
