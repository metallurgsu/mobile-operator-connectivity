param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"

function Invoke-RipeStat {
  param([Parameter(Mandatory)][string]$Endpoint,[Parameter(Mandatory)][string]$Resource,[int]$Lod=0)
  $encoded=[uri]::EscapeDataString($Resource)
  $uri="https://stat.ripe.net/data/$Endpoint/data.json?resource=$encoded&lod=$Lod"
  try {
    [pscustomobject]@{success=$true;uri=$uri;data=(Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 30)}
  } catch {
    [pscustomobject]@{success=$false;uri=$uri;data=$null;error=$_.Exception.Message}
  }
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
    if((($Path[$i] -replace '[{}()]','') -eq $s -and ($Path[$i+1] -replace '[{}()]','') -eq $t) -or
       (($Path[$i] -replace '[{}()]','') -eq $t -and ($Path[$i+1] -replace '[{}()]','') -eq $s)){
      return $true
    }
  }
  return $false
}

function Get-NeighbourMatch {
  param($Neighbours,[string]$WantedAsn)
  $wanted=[int]($WantedAsn -replace '^AS','')
  foreach($n in @($Neighbours)){
    if([int]$n.asn -eq $wanted){
      return [pscustomobject]@{found=$true;asn=$n.asn;type=$n.type;power=$n.power}
    }
  }
  return [pscustomobject]@{found=$false;asn=$wanted;type=$null;power=$null}
}

$c=Get-Config $Operator
$sourceAsn=$c.Operator.asn
$targetAsn=$c.Project.target.asn
$targetPrefix=$c.Project.target.prefix
$targetIp=$c.Project.target.ip

$lg=Invoke-RipeStat "looking-glass" $targetPrefix 1
$sourceNeighbours=Invoke-RipeStat "asn-neighbours" $sourceAsn 1
$targetNeighbours=Invoke-RipeStat "asn-neighbours" $targetAsn 1

$paths=@()
if($lg.success){
  foreach($rrc in @($lg.data.rrcs)){
    foreach($peer in @($rrc.peers)){
      $path=Convert-AsPath $peer.as_path
      if($path.Count -gt 0){
        $paths += [pscustomobject]@{
          rrc=$rrc.id
          peer=$peer.peer
          prefix=$peer.prefix
          next_hop=$peer.next_hop
          as_path=$path
          direct_adjacency=(Test-DirectAdjacency $path $sourceAsn $targetAsn)
        }
      }
    }
  }
}

$sourceMatch=if($sourceNeighbours.success){Get-NeighbourMatch $sourceNeighbours.data.neighbours $targetAsn}else{$null}
$targetMatch=if($targetNeighbours.success){Get-NeighbourMatch $targetNeighbours.data.neighbours $sourceAsn}else{$null}
$pathDirect=(@($paths | Where-Object {$_.direct_adjacency})).Count -gt 0
$neighbourDirect=($sourceMatch -and $sourceMatch.found) -or ($targetMatch -and $targetMatch.found)

[pscustomobject]@{
  source="RIPEstat"
  source_asn=$sourceAsn
  target_asn=$targetAsn
  target_ip=$targetIp
  target_prefix=$targetPrefix
  looking_glass=[pscustomobject]@{
    success=$lg.success
    uri=$lg.uri
    route_count=$paths.Count
    paths=$paths
    error=$lg.error
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
  direct_as_adjacency=if($pathDirect -or $neighbourDirect){$true}elseif($lg.success -or $sourceNeighbours.success -or $targetNeighbours.success){$false}else{$null}
  path_observation_count=$paths.Count
  direct_path_observation_count=@($paths | Where-Object {$_.direct_adjacency}).Count
  status=if($lg.success -and $sourceNeighbours.success -and $targetNeighbours.success){"LOOKUP_OK"}elseif($lg.success -or $sourceNeighbours.success -or $targetNeighbours.success){"PARTIAL"}else{"ERROR"}
  note="RIPEstat provides BGP control-plane observations from RIPE RIS. AS adjacency does not prove that the measured data-plane flow used that path or a specific IX."
}
