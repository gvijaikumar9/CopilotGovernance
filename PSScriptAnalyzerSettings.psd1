@{
    # Write-Host is intentional in this module: the cmdlets print colored, interactive
    # status lines and value-moment prompts (star/feedback) to the console. All
    # pipeline DATA is returned through the output stream (return / the objects),
    # never via Write-Host, so piping, Export-Csv, and ConvertTo-Json stay clean.
    ExcludeRules = @('PSAvoidUsingWriteHost')
}
