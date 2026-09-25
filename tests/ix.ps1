param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"

function Get-AsnNumber {
  param([string]$Asn)
  if([string]::IsNullOrWhiteSpace($Asn)){return $null}
  [int]($Asn -replace '^AS','')
}

$c=Get-Config $Operator
$sourceAsn=$c.Operator.asn
$targetAsn=$c.Project.target.asn

if([string]::IsNullOrWhiteSpace($sourceAsn) -or [string]::IsNullOrWhiteSpace($targetAsn)){
  [pscustomobject]@{
    direct_peer_proven=$null
    specific_ix_path_proven=$null
    internet_transit=$null
    matched_ix=@()
    third_party_asns=@()
    status="NOT_TESTED"
    note="Source or target ASN is not configured; cannot cross-reference traceroute with PeeringDB."
  }
  return
}

# Re-run the underlying measurements. Each test script is independent and
# side-effect free, matching the pattern already used by bgp-tools.ps1
# (which re-runs identity.ps1). This keeps every script runnable standalone
# at the cost of one extra HTTP round-trip per dependency.
$trace=& "$PSScriptRoot/traceroute.ps1" -Operator $Operator
$peeringDb=& "$PSScriptRoot/peeringdb.ps1" -Operator $Operator

$sourceAsnNum=Get-AsnNumber $sourceAsn
$targetAsnNum=Get-AsnNumber $targetAsn

$publicHops=@($trace.hops | Where-Object {$_.scope -eq "PUBLIC"})

# A public hop attributed to an ASN that is neither source nor target is
# direct evidence that the path crossed a third-party (transit) network.
$thirdPartyHops=@($publicHops | Where-Object {
  $_.asn -and (Get-AsnNumber $_.asn) -ne $sourceAsnNum -and (Get-AsnNumber $_.asn) -ne $targetAsnNum
})

# Hops that already landed inside the target's own ASN.
$targetHops=@($publicHops | Where-Object {$_.asn -and (Get-AsnNumber $_.asn) -eq $targetAsnNum})

# Build a lookup of PeeringDB interconnect IPs (from common_ix) -> IX name,
# so a traceroute hop that lands exactly on one of these IPs is strong,
# specific evidence (not just "both are members of the same IX").
$ixIpMap=@{}
if($peeringDb.common_ix){
  foreach($ix in $peeringDb.common_ix){
    if($ix.source_ipaddr4){$ixIpMap[[string]$ix.source_ipaddr4]=$ix.name}
    if($ix.target_ipaddr4){$ixIpMap[[string]$ix.target_ipaddr4]=$ix.name}
  }
}

$ixMatchHops=@($publicHops | Where-Object {$_.ip -and $ixIpMap.ContainsKey([string]$_.ip)})

$internetTransit=$thirdPartyHops.Count -gt 0
$directPeer=($targetHops.Count -gt 0) -and (-not $internetTransit)
$specificIx=$ixMatchHops.Count -gt 0

$status=
  if($publicHops.Count -eq 0){"NOT_PROVEN"}
  elseif($directPeer -or $specificIx){"CONFIRMED"}
  elseif($internetTransit){"REFUTED"}
  else{"NOT_PROVEN"}

[pscustomobject]@{
  direct_peer_proven=if($publicHops.Count -eq 0){$null}else{$directPeer}
  specific_ix_path_proven=if($publicHops.Count -eq 0){$null}else{$specificIx}
  internet_transit=if($publicHops.Count -eq 0){$null}else{$internetTransit}
  matched_ix=@($ixMatchHops | ForEach-Object {[pscustomobject]@{hop=$_.hop;ip=$_.ip;ix_name=$ixIpMap[[string]$_.ip]}})
  third_party_asns=@($thirdPartyHops | Select-Object -ExpandProperty asn -Unique)
  target_hops=@($targetHops | Select-Object -ExpandProperty hop)
  peeringdb_common_ix_count=@($peeringDb.common_ix).Count
  status=$status
  note="Cross-references traceroute hop ASNs and PeeringDB common-IX interconnect IPs against the configured source/target ASN. A public hop resolving to a third-party ASN is evidence the path used transit rather than direct peering; a hop IP matching a PeeringDB common_ix entry is stronger, specific evidence of the exact interconnect used. This is still control/data-plane evidence gathered from one measurement host at one point in time: it does not account for MPLS-hidden hops, ICMP rate-limiting, asymmetric return paths, or IX peerings whose interfaces do not respond to traceroute."
}
