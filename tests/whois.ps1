param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$ip=$c.Operator.tested_ip
if(-not $ip){return [pscustomobject]@{available=$false;status="NOT_TESTED"}}
try{
  $r=Invoke-RestMethod "https://rdap.db.ripe.net/ip/$ip" -TimeoutSec 20
  [pscustomobject]@{available=$true;handle=$r.handle;name=$r.name;country=$r.country;status="CONFIRMED"}
}catch{[pscustomobject]@{available=$false;status="ERROR";error=$_.Exception.Message}}