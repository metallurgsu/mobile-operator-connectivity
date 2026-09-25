param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$target=$c.Project.target.ip
$out=& tracert.exe -d -h 20 -w 1000 $target 2>&1
$hops=@()
foreach($line in $out){
  if($line -match '^\s*(\d+)\s+(.+)$'){
    $hopNumber=[int]$Matches[1]
    $rest=$Matches[2]
    $ips=@([regex]::Matches($rest,'(?:\d{1,3}\.){3}\d{1,3}')|ForEach-Object Value)
    $rtts=@([regex]::Matches($rest,'(?<!\d)(\d+)\s*ms')|ForEach-Object {[int]$_.Groups[1].Value})
    if($ips.Count -gt 0){
      $hops += [pscustomobject]@{hop=$hopNumber;ip=$ips[-1];rtt_ms=$rtts;status="REPLIED"}
    }else{
      $hops += [pscustomobject]@{hop=$hopNumber;ip=$null;rtt_ms=$rtts;status="TIMEOUT"}
    }
  }
}
[pscustomobject]@{target=$target;hops=$hops;status=if($hops.Count){"CONFIRMED"}else{"ERROR"}}