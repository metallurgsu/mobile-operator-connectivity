$ErrorActionPreference="Stop"
. "$PSScriptRoot/common.ps1"
$root=Split-Path $PSScriptRoot -Parent
$ops=(Get-Content "$root/config/operators.json" -Raw|ConvertFrom-Json).operators
foreach($op in $ops){
  if($op.tested_ip){Write-Host "=== $($op.short_name) ===";& "$PSScriptRoot/run-operator.ps1" -Operator $op.short_name}
  else{Write-Host "SKIP $($op.short_name): tested_ip is not configured"}
}