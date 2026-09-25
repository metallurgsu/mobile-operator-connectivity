param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$target=$c.Project.target.ip
try{
  $r=Invoke-RestMethod "https://stat.ripe.net/data/routing-status/data.json?resource=$target" -TimeoutSec 20
  $routes=@($r.data.routes)
  [pscustomobject]@{reachability=($routes.Count -gt 0);route_count=$routes.Count;routes=$routes}
}catch{[pscustomobject]@{reachability=$null;status="ERROR";error=$_.Exception.Message}}