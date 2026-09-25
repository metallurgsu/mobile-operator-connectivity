param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$target=$c.Project.target.ip
$routes=@()
try{$routes=@(Get-NetRoute -DestinationPrefix "$target/32" -ErrorAction Stop|Select-Object DestinationPrefix,NextHop,InterfaceAlias,RouteMetric)}catch{}
[pscustomobject]@{local_routes=$routes;mpls_observed=$null;internal_selectel=$null;status="NOT_PROVEN"}