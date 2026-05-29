@{
    # PSScriptAnalyzer settings for super-linter (POWERSHELL).
    #
    # These scripts are an interactive command-line tool, so a few default rules
    # do not fit and are intentionally relaxed:
    #
    #   PSAvoidUsingWriteHost        - Write-Host is the intended mechanism for the
    #                                  tool's user-facing console status output.
    #   PSAvoidUsingEmptyCatchBlock  - the empty catch blocks are deliberate
    #                                  connection-probe fallbacks (try the documented
    #                                  health check, silently fall through to a live probe).
    #
    # Restricting Severity to Error/Warning also drops advisory Information-level
    # findings (PSProvideCommentHelp, PSUseOutputTypeCorrectly) that add noise without
    # affecting correctness for top-level scripts.
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingEmptyCatchBlock'
    )
}
