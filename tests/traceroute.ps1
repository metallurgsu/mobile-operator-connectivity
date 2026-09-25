param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$target=$c.Project.target.ip
$out=& tracert.exe -d -h 20 -w 1000 $target 2>&1
$hops=@()
foreach($line in $out){
  if($line -match '^\s*\d+\s+(.+)$'){
    $ips=[regex]::Matches($Matches[1],'(?:\d{1,3}\.){3}\d{1,3}')|ForEach-Object Value
    if($ips){$hops+=$ips[-1]}else{$hops+="*"}
  }
}
[pscustomobject]@{target=$target;hops=$hops;status=if($hops.Count){"CONFIRMED"}else{"ERROR"}}