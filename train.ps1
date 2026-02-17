param (
    [string]$Files,  # Comma separated list of filenames (e.g. "InventoryManager.luau,ItemTypes.luau")
    [int]$Score      # 1 for Good, -1 for Bad
)

$fileArray = $Files -split ","

$body = @{ 
    fileNames = $fileArray
    score = $Score 
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:3000/feedback" -Method Post -ContentType "application/json" -Body $body
Write-Host "🎓 God Agent updated." -ForegroundColor Green