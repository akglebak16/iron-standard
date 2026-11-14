param([Parameter(Mandatory=$true)][string]$EnginePath)

$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tests = Get-ChildItem -LiteralPath $project -Recurse -Filter 'test_*.gd' | Sort-Object FullName
if ($tests.Count -eq 0) { throw 'No Godot tests found' }
foreach ($test in $tests) {
    $relative = $test.FullName.Substring($project.Length + 1).Replace('\', '/')
    $output = & $EnginePath --headless --path $project --script "res://$relative" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $output -match 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Assertion failed') {
        Write-Output $output
        throw "Godot test failed: $relative"
    }
    Write-Output "$relative OK"
}
