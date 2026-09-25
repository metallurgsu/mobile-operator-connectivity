param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"

function Invoke-RipeStat {
  param([Parameter(Mandatory)][string]$Endpoint,[Parameter(Mandatory)][string]$Resource,[hashtable]$ExtraQuery=@{})
  $encoded=[uri]::EscapeDataString($Resource)
  $uri="https://stat.ripe.net/data/$Endpoint/data.json?resource=$encoded"
  foreach($key in $ExtraQuery.Keys){
    $uri+="&$key=$([uri]::EscapeDataString([string]$ExtraQuery[$key]))"
  }
  try {
    [pscustomobject]@{success=$true;uri=$uri;data=(Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 30)}
  } catch {
    [pscustomobject]@{success=$false;uri=$uri;data=$null;error=$_.Exception.Message}
  }
}

function Get-ObjectValues {
  param($Value)
  if($null -eq $Value){return @()}
  if($Value -is [System.Collections.IDictionary]){return @($Value.Values)}
  if(($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])){return @($Value)}
  return @($Value)
}

function Convert-AsPath {
  param($Path)
  if($null -eq $Path){return @()}
  if($Path -is [string]){return @($Path -split 's+' | Where-Object {$_})}
  return @($Path | ForEach-Object {[string]$_})
}

function Test-DirectAdjacency {
  param([string[]]$Path,[string]$SourceAsn,[string]$TargetAsn)
  $s=$SourceAsn -replace '^AS',''
  $t=$TargetAsn -replace '^AS',''
  for($i=0;$i -lt $Path.Count-1;$i++){
    $a=$Path[$i] -replace '[{}()]',''
    $b=$Path[$i+1] -replace '[{}()]',''
    if(($a -eq $s -and $b -eq $t) -or ($a -eq $t -and $b -eq $s)){return $true}
  }
  return $false
}

function Get-NeighbourMatch {
  param($Neighbours,[string]$WantedAsn)
  $wanted=[int]($WantedAsn -replace '^AS','')
  foreach($n in Get-ObjectValues $Neighbours){
    if([int]$n.asn -eq $wanted){
      return [pscustomobject]@{found=$true;asn=$n.asn;type=$n.type;power=$n.power}
    }
  }
  return [pscustomobject]@{found=$false;asn=$wanted;type=$null;power=$null}
}

function Get-LookingGlassPaths {
  param($Data,[string]$SourceAsn,[string]$TargetAsn)
  $out=@()
  # Current RIPEstat format: data.rrcs is an object keyed by RRC;
  # each RRC contains an "entries" list. Older formats may expose peers.
  if($Data.rrcs -is [System.Collections.IDictionary]){
    foreach($entry in $Data.rrcs.GetEnumerator()){
      $rrcId=[string]$entry.Key
      $rrc=$entry.Value
      $peers=if($rrc.entries){Get-ObjectValues $rrc.entries}elseif($rrc.peers){Get-ObjectValues $rrc.peers}else{@()}
      foreach($peer in $peers){
        $path=Convert-AsPath $peer.as_path
        if($path.Count -gt 0){
          $out += [pscustomobject]@{
            rrc=$rrcId
            peer=$peer.peer
            prefix=$peer.prefix
            next_hop=$peer.next_hop
            as_path=$path
            direct_adjacency=(Test-DirectAdjacency $path $SourceAsn $TargetAsn)
          }
        }
      }
    }
  } else {
    foreach($rrc in Get-ObjectValues $Data.rrcs){
      $rrcId=if($rrc.rrc){$rrc.rrc}elseif($rrc.id){$rrc.id}else{$null}
      $peers=if($rrc.entries){Get-ObjectValues $rrc.entries}elseif($rrc.peers){Get-ObjectValues $rrc.peers}else{@()}
      foreach($peer in $peers){
        $path=Convert-AsPath $peer.as_path
        if($path.Count -gt 0){
          $out += [pscustomobject]@{
            rrc=$rrcId
            peer=$peer.peer
            prefix=$peer.prefix
            next_hop=$peer.next_hop
            as_path=$path
            direct_adjacency=(Test-DirectAdjacency $path $SourceAsn $TargetAsn)
          }
        }
      }
    }
  }
  return @($out)
}

$c=Get-Config $Operator
$sourceAsn=$c.Operator.asn
$targetAsn=$c.Project.target.asn
$targetPrefix=$c.Project.target.prefix
$targetIp=$c.Project.target.ip

$lg=Invoke-RipeStat "looking-glass" $targetPrefix
$state=Invoke-RipeStat "bgp-state" $targetPrefix
$sourceNeighbours=Invoke-RipeStat "asn-neighbours" $sourceAsn @{lod=1}
$targetNeighbours=Invoke-RipeStat "asn-neighbours" $targetAsn @{lod=1}

$lgPaths=if($lg.success){Get-LookingGlassPaths $lg.data $sourceAsn $targetAsn}else{@()}

$statePaths=@()
if($state.success){
  foreach($route in Get-ObjectValues $state.data.bgp_state){
    $path=Convert-AsPath $route.path
    if($path.Count -gt 0){
      $statePaths += [pscustomobject]@{
        target_prefix=$route.target_prefix
        source_id=$route.source_id
        path=$path
        direct_adjacency=(Test-DirectAdjacency $path $sourceAsn $targetAsn)
      }
    }
  }
}

$sourceMatch=if($sourceNeighbours.success){Get-NeighbourMatch $sourceNeighbours.data.neighbours $targetAsn}else{$null}
$targetMatch=if($targetNeighbours.success){Get-NeighbourMatch $targetNeighbours.data.neighbours $sourceAsn}else{$null}
$pathDirect=(@($lgPaths | Where-Object {$_.direct_adjacency})).Count -gt 0 -or (@($statePaths | Where-Object {$_.direct_adjacency})).Count -gt 0
$neighbourDirect=($sourceMatch -and $sourceMatch.found) -or ($targetMatch -and $targetMatch.found)
$anySuccess=$lg.success -or $state.success -or $sourceNeighbours.success -or $targetNeighbours.success

[pscustomobject]@{
  source="RIPEstat"
  source_asn=$sourceAsn
  target_asn=$targetAsn
  target_ip=$targetIp
  target_prefix=$targetPrefix
  looking_glass=[pscustomobject]@{
    success=$lg.success
    uri=$lg.uri
    route_count=$lgPaths.Count
    paths=$lgPaths
    error=$lg.error
  }
  bgp_state=[pscustomobject]@{
    success=$state.success
    uri=$state.uri
    route_count=$statePaths.Count
    paths=$statePaths
    query_time=$state.data.query_time
    error=$state.error
  }
  source_neighbours=[pscustomobject]@{
    success=$sourceNeighbours.success
    uri=$sourceNeighbours.uri
    target=$sourceMatch
    error=$sourceNeighbours.error
  }
  target_neighbours=[pscustomobject]@{
    success=$targetNeighbours.success
    uri=$targetNeighbours.uri
    source=$targetMatch
    error=$targetNeighbours.error
  }
  direct_as_adjacency=if($pathDirect -or $neighbourDirect){$true}elseif($anySuccess){$false}else{$null}
  path_observation_count=($lgPaths.Count + $statePaths.Count)
  direct_path_observation_count=(@($lgPaths | Where-Object {$_.direct_adjacency}).Count + @($statePaths | Where-Object {$_.direct_adjacency}).Count)
  status=if($lg.success -and $state.success -and $sourceNeighbours.success -and $targetNeighbours.success){"LOOKUP_OK"}elseif($anySuccess){"PARTIAL"}else{"ERROR"}
  note="RIPEstat RIS control-plane observations. Looking Glass uses RRC entries/peers; BGP State exposes AS paths. AS adjacency does not prove that the measured data-plane flow used that path or a specific IX."
}