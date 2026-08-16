$ImagesSourceBase = "C:\Users\ADmin\Documents\중반아저씨_공구"
$SiteRoot = "C:\Users\ADmin\Desktop\gonggu-site"
$SiteImages = Join-Path $SiteRoot "images"
$PricesDir = Join-Path $SiteRoot "prices"
$PriceTableDir = Join-Path $SiteRoot "가격표"
$ManifestPath = Join-Path $SiteRoot "manifest.json"
$OcrScript = Join-Path $SiteRoot "scripts\ocr-prices.ps1"

foreach ($d in @($SiteImages, $PricesDir, $PriceTableDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# 1) 위챗에서 정리된 날짜별 이미지를 사이트로 복사
$dateFolders = Get-ChildItem -Path $ImagesSourceBase -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' }

foreach ($folder in $dateFolders) {
    $dest = Join-Path $SiteImages $folder.Name
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    Copy-Item -Path (Join-Path $folder.FullName '*') -Destination $dest -Force -ErrorAction SilentlyContinue
}

# 2) 환율 조회 (CNY -> KRW), 200원 미만이면 200원 적용
$cnyToKrw = 200
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rateResp = Invoke-RestMethod -Uri "https://api.frankfurter.app/latest?from=CNY&to=KRW" -TimeoutSec 15
    if ($rateResp.rates.KRW) { $cnyToKrw = [double]$rateResp.rates.KRW }
} catch {
    Write-Output "환율 조회 실패, 기본값(200) 사용"
}
$appliedRate = [Math]::Max(200, $cnyToKrw)

# 3) 가격 인식 안 된 날짜에 대해 OCR 실행
$imageExt = @(".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp")
$siteDateFolders = Get-ChildItem -Path $SiteImages -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } |
    Sort-Object Name -Descending

foreach ($folder in $siteDateFolders) {
    $priceFile = Join-Path $PricesDir "$($folder.Name).json"
    if (-not (Test-Path $priceFile)) {
        & $OcrScript -Date $folder.Name
    }
}

# 4) manifest.json 생성 (가격 포함) + 날짜별 가격표(csv) 생성
$manifest = @()

foreach ($folder in $siteDateFolders) {
    $imgs = Get-ChildItem -Path $folder.FullName -File -ErrorAction SilentlyContinue |
        Where-Object { $imageExt -contains $_.Extension.ToLower() } |
        Sort-Object Name

    if ($imgs.Count -eq 0) { continue }

    $priceFile = Join-Path $PricesDir "$($folder.Name).json"
    $priceMap = @{}
    if (Test-Path $priceFile) {
        $priceData = Get-Content $priceFile -Raw | ConvertFrom-Json
        foreach ($p in $priceData) { $priceMap[$p.file] = $p.cny }
    }

    $imageEntries = @()
    $csvRows = @()

    foreach ($img in $imgs) {
        $cny = $priceMap[$img.Name]
        $costKrw = $null
        $saleKrw = $null
        if ($null -ne $cny) {
            $costKrw = [Math]::Round(([double]$cny * $appliedRate) / 100) * 100
            $saleKrw = [Math]::Round(($costKrw * 1.5) / 100) * 100
        }
        $imageEntries += [PSCustomObject]@{ file = $img.Name; cny = $cny; krw = $saleKrw }
        $csvRows += [PSCustomObject]@{
            파일명 = $img.Name
            위안화가격 = $cny
            적용환율 = $appliedRate
            원가원화 = $costKrw
            판매가_50프로마진 = $saleKrw
        }
    }

    $manifest += [PSCustomObject]@{
        date = $folder.Name
        rate = $appliedRate
        images = @($imageEntries)
    }

    $csvPath = Join-Path $PriceTableDir "$($folder.Name).csv"
    $csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
}

if ($manifest.Count -eq 0) {
    "[]" | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
} else {
    ConvertTo-Json -InputObject @($manifest) -Depth 6 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
}

# 5) git 커밋 및 푸시 (원격이 연결되어 있을 때만)
Push-Location $SiteRoot
$hasRemote = git remote 2>$null
if ($hasRemote) {
    git add -A
    $status = git status --porcelain
    if ($status) {
        git commit -m "자동 업데이트 $(Get-Date -Format 'yyyy-MM-dd')" | Out-Null
        git push
    }
}
Pop-Location
