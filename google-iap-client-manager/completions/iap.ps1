#Requires -Version 7.2
Register-ArgumentCompleter -Native -CommandName iap,iap.ps1 -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $elements = $commandAst.CommandElements
    $candidates = @()
    if ($elements.Count -le 2) {
        $candidates += @('help','export','ls','show','edit','setup','new','remove','reset','uninstall','names','version','update')
        $candidates += @(& iap names 2>$null)
    } elseif ($elements[1].Extent.Text -in @('show','edit','remove')) { $candidates += @(& iap names 2>$null) }
    foreach ($candidate in $candidates) {
        if ($candidate -like "$wordToComplete*") {
            [Management.Automation.CompletionResult]::new($candidate, $candidate, 'ParameterValue', $candidate)
        }
    }
}
