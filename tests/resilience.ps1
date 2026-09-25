param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"

function Get-AsnNumber {
  param($Asn)
  if($null -eq $Asn -or [string]::IsNullOrWhiteSpace([string]$Asn)){return $null}
  [int]([string]$Asn -replace '^AS','')
}

$c=Get-Config $Operator
$sourceAsn=$c.Operator.asn
$targetAsn=$c.Project.target.asn

if([string]::IsNullOrWhiteSpace($sourceAsn) -or [string]::IsNullOrWhiteSpace($targetAsn)){
  [pscustomobject]@{
    hypothesis=$null
    multihomed_evidence=@()
    direct_adjacency_exists=$null
    current_path_uses_transit=$null
    status="NOT_TESTED"
    note="Source or target ASN is not configured."
  }
  return
}

# Re-run the dependent tests. Each is independent/side-effect free by design
# (same pattern as bgp-tools.ps1 -> identity.ps1, ix.ps1 -> traceroute.ps1).
$bgp=& "$PSScriptRoot/bgp.ps1" -Operator $Operator
$ripe=& "$PSScriptRoot/ripestat.ps1" -Operator $Operator
$ix=& "$PSScriptRoot/ix.ps1" -Operator $Operator

$targetAsnNum=Get-AsnNumber $targetAsn

# A more/less-specific announcement of the target prefix from an origin ASN
# other than the target's own ASN is evidence of multihoming: the prefix (or
# a covering/covered one) is reachable via more than one origin, which is a
# structural precondition for surviving the loss of any single upstream.
# NOTE: this does NOT by itself prove the *source* operator can reach that
# alternate origin without transit -- it only proves an alternate origin exists.
$specifics=@($bgp.less_specifics)+@($bgp.more_specifics)
$altOriginSpecifics=@($specifics | Where-Object {
  $null -ne $_.origin -and (Get-AsnNumber $_.origin) -ne $targetAsnNum
})
$multihomed=($bgp.origin_count -gt 1) -or ($altOriginSpecifics.Count -gt 0)

$directAdjacencyExists=($ripe.direct_as_adjacency -eq $true) -or
  ($ix.specific_ix_path_proven -eq $true) -or
  ($ix.direct_peer_proven -eq $true)

$currentPathUsesTransit=($ix.internet_transit -eq $true)

$anyEvidenceGathered=($bgp.status -eq "ok") -or ($ripe.status -ne "ERROR") -or ($ix.status -ne "NOT_TESTED")

$hypothesis=
  if(-not $anyEvidenceGathered){"NOT_PROVEN"}
  elseif($directAdjacencyExists -and -not $currentPathUsesTransit){"DIRECT_PATH_OBSERVED"}
  elseif($directAdjacencyExists -and $currentPathUsesTransit){"DIRECT_ADJACENCY_EXISTS_BUT_UNUSED"}
  elseif((-not $directAdjacencyExists) -and $multihomed){"TRANSIT_DEPENDENT_BUT_MULTIHOMED"}
  elseif($currentPathUsesTransit -and -not $directAdjacencyExists){"TRANSIT_DEPENDENT"}
  else{"NOT_PROVEN"}

[pscustomobject]@{
  hypothesis=$hypothesis
  direct_adjacency_exists=$directAdjacencyExists
  current_path_uses_transit=$currentPathUsesTransit
  multihomed_evidence=$altOriginSpecifics
  origin_count=$bgp.origin_count
  ris_direct_path_count=$ripe.ris_peerings.direct_path_count
  ris_route_count=$ripe.ris_peerings.route_count
  matched_ix=$ix.matched_ix
  status=if($hypothesis -eq "NOT_PROVEN"){"NOT_PROVEN"}else{"HYPOTHESIS"}
  note="This is a PASSIVE-MEASUREMENT HYPOTHESIS about failover behaviour, not a verified failover test. 'DIRECT_ADJACENCY_EXISTS_BUT_UNUSED' means a direct BGP session or common IX was observed (RIS/PeeringDB), but the CURRENTLY measured data-plane path still crosses a third-party ASN -- routing policy (local-pref/MED) may simply prefer transit today, or the direct session may be an IX route-server rather than a real bilateral peer. Confirming that the messenger would survive loss of external transit requires an ACTIVE test: e.g. during a maintenance window, deprioritize or withdraw the transit-learned route (via local BGP policy, a blackhole community, or physically isolating the transit uplink) on the source and/or target side, then verify the messenger still exchanges messages. No passive measurement from a single vantage point can substitute for that."
}
