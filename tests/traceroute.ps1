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
  } catch { return "INVALID" }
}

function New-NetworkInfo {
  param(
    [string]$Scope,
    [string]$Asn,
    [array]$Asns,
    [string]$Prefix,
    [string]$Status,
    [string]$Source,
    [string]$Error
  )
  [pscustomobject]@{
    scope=$Scope
    asn=$Asn
    origin_asn=$Asn
    asns=$Asns
    prefix=$Prefix
    network_status=$Status
    network_source=$Source
    error=$Error
  }
}

function Get-NetworkInfo {
  param([string]$Ip)

  $scope=Get-IPv4Scope $Ip
  if($scope -ne "PUBLIC"){
    return New-NetworkInfo $scope $null @() $null "NOT_PUBLIC" "local-address-classification" $null
  }

  # First try network-info: it is fast and often returns the announcing ASN/prefix.
  try {
    $url="https://stat.ripe.net/data/network-info/data.json?resource=$Ip&sourceapp=mobile-operator-connectivity"
    $r=Invoke-RestMethod $url -TimeoutSec 20
    $asns=@($r.data.asns | ForEach-Object { "AS$($_)" })
    $prefix=[string]$r.data.prefix
    if($prefix -or $asns.Count -gt 0){
      $origin=if($asns.Count -gt 0){$asns[0]}else{$null}
      return New-NetworkInfo "PUBLIC" $origin $asns $prefix "FOUND" "RIPEstat network-info" $null
    }
  } catch {
    $firstError=$_.Exception.Message
  }

  # Fallback: prefix-overview. This can resolve addresses for which network-info
  # does not return a result.
  try {
    $url="https://stat.ripe.net/data/prefix-overview/data.json?resource=$Ip&sourceapp=mobile-operator-connectivity"
    $r=Invoke-RestMethod $url -TimeoutSec 20
    $prefix=[string]$r.data.prefix
    $asns=@($r.data.asns | ForEach-Object { "AS$($_)" })
    $origin=$null
    if($r.data.origin_asns){
      $origin=@($r.data.origin_asns | ForEach-Object { "AS$($_)" })
      $asns=@($asns + $origin | Select-Object -Unique)
    }
    if($origin.Count -eq 0 -and $asns.Count -gt 0){$origin=@($asns[0])}
    $originAsn=if($origin.Count -gt 0){$origin[0]}else{$null}
    if($prefix -or $asns.Count -gt 0){
      return New-NetworkInfo "PUBLIC" $originAsn $asns $prefix "FOUND" "RIPEstat prefix-overview" $null
    }
    return New-NetworkInfo "PUBLIC" $null @() $prefix "NOT_FOUND" "RIPEstat prefix-overview" $firstError
  } catch {
    return New-NetworkInfo "PUBLIC" $null @() $null "ERROR" "RIPEstat prefix-overview" $_.Exception.Message
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
      if(-not $networkCache.ContainsKey($ip)){ $networkCache[$ip]=Get-NetworkInfo $ip }
      $net=$networkCache[$ip]
      $hops += [pscustomobject]@{
        hop=$hopNumber; ip=$ip; rtt_ms=$rtts; status="REPLIED"
        scope=$net.scope; asn=$net.asn; origin_asn=$net.origin_asn
        asns=$net.asns; prefix=$net.prefix
        network_status=$net.network_status; network_source=$net.network_source
        network_error=$net.error
      }
    } else {
      $hops += [pscustomobject]@{
        hop=$hopNumber; ip=$null; rtt_ms=$rtts; status="TIMEOUT"
        scope=$null; asn=$null; origin_asn=$null; asns=@(); prefix=$null
        network_status="NOT_OBSERVED"; network_source=$null; network_error=$null
      }
    }
  }
}

[pscustomobject]@{
  target=$target
  hops=$hops
  status=if($hops.Count){"CONFIRMED"}else{"ERROR"}
}