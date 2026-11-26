#Requires -Version 7.2
Register-ArgumentCompleter -Native -CommandName iap,iap.ps1 -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $elements = $commandAst.CommandElements
    $candidates = @()
    if ($elements.Count -le 2) {
        $candidates += @('help','export','ls','show','edit','setup','new','remove','reset','uninstall','names','version','update','up','ps','down','logs')
        $candidates += @(& iap names 2>$null)
    } elseif ($elements[1].Extent.Text -in @('show','edit','remove','up')) { $candidates += @(& iap names 2>$null) }
    elseif ($elements[1].Extent.Text -in @('down','logs')) {
        $candidates += @('--all') + @(& iap ps 2>$null | Out-String -Stream | Select-Object -Skip 3 | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ })
    }
    foreach ($candidate in $candidates) {
        if ($candidate -like "$wordToComplete*") {
            [Management.Automation.CompletionResult]::new($candidate, $candidate, 'ParameterValue', $candidate)
        }
    }
}
