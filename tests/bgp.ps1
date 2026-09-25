param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$target=$c.Project.target.prefix
try{
  $r=Invoke-RestMethod "https://stat.ripe.net/data/routing-status/data.json?resource=$([uri]::EscapeDataString($target))" -TimeoutSec 20
  $ok=($r.status -eq "ok")
  $d=$r.data
  $origins=@($d.origins)
  [pscustomobject]@{
    reachability=[bool]($ok -and ($d.first_seen -or $d.last_seen -or $origins.Count -gt 0))
    status=$r.status
    status_code=$r.status_code
    resource=$d.resource
    query_time=$d.query_time
    first_seen=$d.first_seen
    last_seen=$d.last_seen
    visibility=$d.visibility
    origins=$origins
    origin_count=$origins.Count
    less_specifics=@($d.less_specifics)
    more_specifics=@($d.more_specifics)
  }
}catch{
  [pscustomobject]@{
    reachability=$null
    status="ERROR"
    error=$_.Exception.Message
  }
}