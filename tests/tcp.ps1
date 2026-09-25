param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$target=$c.Project.target.ip
$result=[ordered]@{}
foreach($port in 22,8080){
  $r=Test-NetConnection -ComputerName $target -Port $port -WarningAction SilentlyContinue
  $result["$port"]=[pscustomobject]@{success=[bool]$r.TcpTestSucceeded}
}
[pscustomobject]$result