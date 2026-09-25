param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$localIp=""
try{$localIp=(Invoke-RestMethod "https://api.ipify.org?format=json" -TimeoutSec 10).ip}catch{}
$tested=$c.Operator.tested_ip
if($localIp){$tested=$localIp}
[pscustomobject]@{ip=$tested;configured_ip=$c.Operator.tested_ip;asn=$c.Operator.asn;prefix=$c.Operator.prefix;public_ip_detected=[bool]$localIp}