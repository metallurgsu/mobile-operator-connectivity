param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"

function Get-PeeringDb {
  param([Parameter(Mandatory)][string]$Path)
  try {
    $url="https://www.peeringdb.com/api/$Path"
    return Invoke-RestMethod $url -Headers @{"Accept"="application/json";"User-Agent"="mobile-operator-connectivity/1.0"} -TimeoutSec 20
  } catch {
    return [pscustomobject]@{error=$_.Exception.Message;data=@()}
  }
}

function Get-FirstData {
  param($Response)
  if($null -eq $Response){return $null}
  $items=@($Response.data)
  if($items.Count -gt 0){return $items[0]}
  return $null
}

$c=Get-Config $Operator
$sourceAsn=[int]($c.Operator.asn -replace '^AS','')
$targetAsn=[int]($c.Project.target.asn -replace '^AS','')

$sourceNet=Get-FirstData (Get-PeeringDb "net?asn=$sourceAsn")
$targetNet=Get-FirstData (Get-PeeringDb "net?asn=$targetAsn")

if($sourceNet -and $targetNet){
  $sourceNetix=@((Get-PeeringDb "netixlan?net_id=$($sourceNet.id)&depth=0").data)
  $targetNetix=@((Get-PeeringDb "netixlan?net_id=$($targetNet.id)&depth=0").data)
  $sourceNetfac=@((Get-PeeringDb "netfac?net_id=$($sourceNet.id)&depth=0").data)
  $targetNetfac=@((Get-PeeringDb "netfac?net_id=$($targetNet.id)&depth=0").data)

  $commonIx=@(
    foreach($a in $sourceNetix){
      foreach($b in $targetNetix){
        if([string]$a.ix_id -eq [string]$b.ix_id){
          [pscustomobject]@{
            ix_id=$a.ix_id
            name=if($a.name){$a.name}else{$b.name}
            source_ipaddr4=$a.ipaddr4
            target_ipaddr4=$b.ipaddr4
            source_speed=$a.speed
            target_speed=$b.speed
          }
        }
      }
    }
  )

  $commonFacilities=@(
    foreach($a in $sourceNetfac){
      foreach($b in $targetNetfac){
        if([string]$a.fac_id -eq [string]$b.fac_id){
          [pscustomobject]@{
            fac_id=$a.fac_id
            name=if($a.name){$a.name}else{$b.name}
            source_local_asn=$a.local_asn
            target_local_asn=$b.local_asn
          }
        }
      }
    }
  )

  [pscustomobject]@{
    source="PeeringDB"
    source_asn="AS$sourceAsn"
    target_asn="AS$targetAsn"
    source_network=[pscustomobject]@{id=$sourceNet.id;name=$sourceNet.name;asn=$sourceNet.asn}
    target_network=[pscustomobject]@{id=$targetNet.id;name=$targetNet.name;asn=$targetNet.asn}
    source_ix_count=$sourceNetix.Count
    target_ix_count=$targetNetix.Count
    source_facility_count=$sourceNetfac.Count
    target_facility_count=$targetNetfac.Count
    common_ix=$commonIx
    common_facilities=$commonFacilities
    direct_peering_possible=if($commonIx.Count -gt 0){$true}elseif($commonFacilities.Count -gt 0){$true}else{$false}
    status="FOUND"
    note="PeeringDB records interconnection presence and possible common infrastructure; it does not prove that the measured flow used a particular IX or facility."
  }
}else{
  [pscustomobject]@{
    source="PeeringDB"
    source_asn="AS$sourceAsn"
    target_asn="AS$targetAsn"
    source_network=$sourceNet
    target_network=$targetNet
    common_ix=@()
    common_facilities=@()
    direct_peering_possible=$null
    status="NOT_FOUND"
    note="One or both ASN records were not found in PeeringDB."
  }
}