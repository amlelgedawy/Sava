# SAVA — Re-extract (fixed joint mapping) + Retrain
# Run from project root: .\reextract_and_retrain.ps1

$ErrorActionPreference = "Stop"
$kp = "D:\Year 4 UNI\Sava\perception\activity_recognition\data\keypoints_v2"
$root = "D:\Year 4 UNI\Sava"

Write-Host "`n=== Step 1: Deleting stale MediaPipe-extracted files ===" -ForegroundColor Cyan
Remove-Item "$kp\WALK\ntu_*"    -Force -ErrorAction SilentlyContinue
Remove-Item "$kp\EAT\ntu_*"     -Force -ErrorAction SilentlyContinue
Remove-Item "$kp\EAT\adl_*"     -Force -ErrorAction SilentlyContinue
Remove-Item "$kp\DRINK\ntu_*"   -Force -ErrorAction SilentlyContinue
Remove-Item "$kp\DRINK\adl_*"   -Force -ErrorAction SilentlyContinue
Remove-Item "$kp\SLEEP\adl_*"   -Force -ErrorAction SilentlyContinue
Remove-Item "$kp\FALL\ntu_*"    -Force -ErrorAction SilentlyContinue
Remove-Item "$kp\FALL\upfall_*" -Force -ErrorAction SilentlyContinue

Write-Host "Files remaining per class (ETRI only should remain):"
Write-Host "  WALK:  $((Get-ChildItem "$kp\WALK").Count)"
Write-Host "  EAT:   $((Get-ChildItem "$kp\EAT").Count)"
Write-Host "  DRINK: $((Get-ChildItem "$kp\DRINK").Count)"
Write-Host "  SLEEP: $((Get-ChildItem "$kp\SLEEP").Count)"
Write-Host "  FALL:  $((Get-ChildItem "$kp\FALL").Count)"

Set-Location $root

Write-Host "`n=== Step 2: Extracting NTU keypoints ===" -ForegroundColor Cyan
python perception/activity_recognition/extract_keypoints_ntu.py

Write-Host "`n=== Step 3: Extracting ADL keypoints ===" -ForegroundColor Cyan
python perception/activity_recognition/extract_keypoints_adl.py

Write-Host "`n=== Step 4: Extracting UP-Fall keypoints ===" -ForegroundColor Cyan
python perception/activity_recognition/extract_keypoints_upfall.py

Write-Host "`n=== Step 5: Final class counts ===" -ForegroundColor Cyan
Write-Host "  WALK:  $((Get-ChildItem "$kp\WALK").Count)"
Write-Host "  EAT:   $((Get-ChildItem "$kp\EAT").Count)"
Write-Host "  DRINK: $((Get-ChildItem "$kp\DRINK").Count)"
Write-Host "  SLEEP: $((Get-ChildItem "$kp\SLEEP").Count)"
Write-Host "  FALL:  $((Get-ChildItem "$kp\FALL").Count)"

Write-Host "`n=== Step 6: Retraining SkateFormer ===" -ForegroundColor Cyan
python perception/activity_recognition/train_finetune_v2.py

Write-Host "`nAll done!" -ForegroundColor Green
