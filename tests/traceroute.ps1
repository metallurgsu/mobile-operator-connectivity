param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"

function Get-IPv4Scope {
  param([string]$Ip)
  try {
    $bytes=[System.Net.IPAddress]::Parse($Ip).GetAddressBytes()
    if($bytes.Count -ne 4){return "OTHER"}
    if($bytes[0] -eq 10){return "RFC1918"}
    if($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31){return "RFC1918"}
    if($bytes[0] -eq 192 -and $bytes[1] -eq 168){return "RFC1918"}
    if($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127){return "CGNAT"}
    if($bytes[0] -eq 169 -and $bytes[1] -eq 254){return "LINK_LOCAL"}
    if($bytes[0] -eq 127){return "LOOPBACK"}
    if($bytes[0] -eq 198 -and $bytes[1] -ge 18 -and $bytes[1] -le 19){return "BENCHMARK"}
    return "PUBLIC"
  } catch {
    return "INVALID"
  }
}

function Get-NetworkInfo {
  param([string]$Ip)
  $scope=Get-IPv4Scope $Ip
  if($scope -ne "PUBLIC"){
    return [pscustomobject]@{
      scope=$scope
      asn=$null
      asns=@()
      prefix=$null
      status="NOT_PUBLIC"
      source="local-address-classification"
    }
  }

  try {
    $url="https://stat.ripe.net/data/network-info/data.json?resource=$Ip&sourceapp=mobile-operator-connectivity"
    $r=Invoke-RestMethod $url -TimeoutSec 20
    $asns=@($r.data.asns | ForEach-Object { "AS$($_)" })
    $prefix=$r.data.prefix
    [pscustomobject]@{
      scope="PUBLIC"
      asn=if($asns.Count -gt 0){$asns[0]}else{$null}
      asns=$asns
      prefix=$prefix
      status=if($prefix -or $asns.Count -gt 0){"FOUND"}else{"NOT_FOUND"}
      source="RIPEstat network-info"
    }
  } catch {
    [pscustomobject]@{
      scope="PUBLIC"
      asn=$null
      asns=@()
      prefix=$null
      status="ERROR"
      source="RIPEstat network-info"
      error=$_.Exception.Message
    }
  }
}

$c=Get-Config $Operator
$target=$c.Project.target.ip
$out=& tracert.exe -d -h 20 -w 1000 $target 2>&1
$hops=@()
$networkCache=@{}

foreach($line in $out){
  if($line -match '^\s*(\d+)\s+(.+)$'){
    $hopNumber=[int]$Matches[1]
    $rest=$Matches[2]
    $ips=@([regex]::Matches($rest,'(?:\d{1,3}\.){3}\d{1,3}')|ForEach-Object Value)
    $rtts=@([regex]::Matches($rest,'(?<!\d)(\d+)\s*ms')|ForEach-Object {[int]$_.Groups[1].Value})

    if($ips.Count -gt 0){
      $ip=$ips[-1]
      if(-not $networkCache.ContainsKey($ip)){
        $networkCache[$ip]=Get-NetworkInfo $ip
      }
      $net=$networkCache[$ip]
      $hops += [pscustomobject]@{
        hop=$hopNumber
        ip=$ip
        rtt_ms=$rtts
        status="REPLIED"
        scope=$net.scope
        asn=$net.asn
        asns=$net.asns
        prefix=$net.prefix
        network_status=$net.status
        network_source=$net.source
      }
    }else{
      $hops += [pscustomobject]@{
        hop=$hopNumber
        ip=$null
        rtt_ms=$rtts
        status="TIMEOUT"
        scope=$null
        asn=$null
        asns=@()
        prefix=$null
        network_status="NOT_OBSERVED"
        network_source=$null
      }
    }
  }
}

[pscustomobject]@{
  target=$target
  hops=$hops
  status=if($hops.Count){"CONFIRMED"}else{"ERROR"}
}