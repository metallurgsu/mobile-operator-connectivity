param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$localIp=""
try{$localIp=(Invoke-RestMethod "https://api.ipify.org?format=json" -TimeoutSec 10).ip}catch{}
$tested=$c.Operator.tested_ip
if($localIp){$tested=$localIp}
$configuredIp=if([string]::IsNullOrWhiteSpace($c.Operator.tested_ip)){$null}else{$c.Operator.tested_ip}
[pscustomobject]@{
  ip=$tested
  configured_ip=$configuredIp
  asn=$c.Operator.asn
  prefix=$c.Operator.prefix
  public_ip_detected=[bool]$localIp
}