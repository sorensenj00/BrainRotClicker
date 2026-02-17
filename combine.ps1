# combine.ps1
# Combines all source code files into a single "combined code.txt" file

$OutputFile = "combined code.txt"
$SourceDir = "src"
$IncludeExtensions = @("*.luau", "*.lua", "*.json")

# Start with a fresh file
"" | Out-File -FilePath $OutputFile -Encoding utf8

Write-Host "Combining code from $SourceDir..." -ForegroundColor Cyan

# Get all files matching extensions, excluding any hidden or system files
$Files = Get-ChildItem -Path $SourceDir -Include $IncludeExtensions -Recurse -File

# Also include the project file if it exists
if (Test-Path "default.project.json") {
    $Files += Get-Item "default.project.json"
}

foreach ($File in $Files) {
    $RelativePath = $File.FullName.Replace((Get-Location).Path + "\", "")
    Write-Host "Adding: $RelativePath"
    
    Add-Content -Path $OutputFile -Value ("=" * 80) -Encoding utf8
    Add-Content -Path $OutputFile -Value "FILE: $RelativePath" -Encoding utf8
    Add-Content -Path $OutputFile -Value ("=" * 80) -Encoding utf8
    Add-Content -Path $OutputFile -Value "" -Encoding utf8
    
    Get-Content -Path $File.FullName | Add-Content -Path $OutputFile -Encoding utf8
    
    Add-Content -Path $OutputFile -Value "" -Encoding utf8
    Add-Content -Path $OutputFile -Value "" -Encoding utf8
}

Write-Host "`nSuccessfully combined $($Files.Count) files into '$OutputFile'" -ForegroundColor Green
