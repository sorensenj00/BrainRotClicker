param (
    [string]$Query
)

if ([string]::IsNullOrWhiteSpace($Query)) {
    Write-Host "Usage: ./ask 'Your question here'" -ForegroundColor Red
    exit
}

$body = @{ question = $Query } | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "http://localhost:3000/ask" -Method Post -ContentType "application/json" -Body $body
    Write-Host "✅ God Agent has updated the context file." -ForegroundColor Green
    
    # Optional: Print the files it found directly to terminal
    foreach ($item in $response.findings) {
        Write-Host "Found: $($item.file) (Score: $($item.score))" -ForegroundColor Gray
    }
} catch {
    Write-Host "❌ Error: Is the God Agent running?" -ForegroundColor Red
    Write-Host $_.Exception.Message
}