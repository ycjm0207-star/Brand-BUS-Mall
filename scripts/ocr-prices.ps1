param(
    [Parameter(Mandatory = $true)]
    [string]$Date
)

$Tesseract = "C:\Program Files\Tesseract-OCR\tesseract.exe"
$SiteRoot = "C:\Users\ADmin\Desktop\gonggu-site"
$ImgDir = Join-Path $SiteRoot "images\$Date"
$PricesDir = Join-Path $SiteRoot "prices"
$PriceFile = Join-Path $PricesDir "$Date.json"

if (-not (Test-Path $ImgDir)) { return }
if (-not (Test-Path $PricesDir)) { New-Item -ItemType Directory -Path $PricesDir -Force | Out-Null }

$imageExt = @(".jpg", ".jpeg", ".png", ".bmp", ".webp")
$results = @()

Get-ChildItem -Path $ImgDir -File -ErrorAction SilentlyContinue |
    Where-Object { $imageExt -contains $_.Extension.ToLower() } |
    ForEach-Object {
        $img = $_.FullName
        $tmpBase = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())

        & $Tesseract $img $tmpBase --psm 11 -c tessedit_char_whitelist="0123456789.¥元RMB" 2>$null | Out-Null
        $text = ""
        if (Test-Path "$tmpBase.txt") {
            $text = Get-Content "$tmpBase.txt" -Raw -ErrorAction SilentlyContinue
            Remove-Item "$tmpBase.txt" -ErrorAction SilentlyContinue
        }

        $cny = $null
        if ($text) {
            $nums = [regex]::Matches($text, '\d{1,4}(\.\d{1,2})?') |
                ForEach-Object { [double]$_.Value } |
                Where-Object { $_ -ge 5 -and $_ -le 9999 }
            if ($nums) { $cny = ($nums | Select-Object -First 1) }
        }

        $results += [PSCustomObject]@{ file = $_.Name; cny = $cny }
    }

ConvertTo-Json -InputObject @($results) -Depth 4 | Set-Content -LiteralPath $PriceFile -Encoding UTF8
