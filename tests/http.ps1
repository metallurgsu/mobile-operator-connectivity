param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$url="http://$($c.Project.target.ip):8080/"
try{
  $r=Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
  [pscustomobject]@{url=$url;status_code=[int]$r.StatusCode;success=($r.StatusCode -eq 200)}
}catch{
  $code=$null
  if($_.Exception.Response){$code=[int]$_.Exception.Response.StatusCode.value__}
  [pscustomobject]@{url=$url;status_code=$code;success=$false;error=$_.Exception.Message}
}