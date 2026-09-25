param([Parameter(Mandatory)][string]$Operator)
$ErrorActionPreference="Stop"
. "$PSScriptRoot/common.ps1"
$c=Get-Config $Operator
$root=$c.Root
$target=$c.Project.target
$stamp=(Get-Date).ToString("yyyy-MM-dd")
$identity=& "$PSScriptRoot/identity.ps1" -Operator $Operator
$whois=& "$PSScriptRoot/whois.ps1" -Operator $Operator
$bgp=& "$PSScriptRoot/bgp.ps1" -Operator $Operator
$bgpTools=& "$PSScriptRoot/bgp-tools.ps1" -Operator $Operator
$peeringDb=& "$PSScriptRoot/peeringdb.ps1" -Operator $Operator
$routing=& "$PSScriptRoot/routing.ps1" -Operator $Operator
$trace=& "$PSScriptRoot/traceroute.ps1" -Operator $Operator
$tcp=& "$PSScriptRoot/tcp.ps1" -Operator $Operator
$http=& "$PSScriptRoot/http.ps1" -Operator $Operator
$tcpdump=& "$PSScriptRoot/tcpdump.ps1" -Operator $Operator
$security=& "$PSScriptRoot/security.ps1" -Operator $Operator
$ix=& "$PSScriptRoot/ix.ps1" -Operator $Operator
$ip=[bool]($tcp.'22'.success -or $tcp.'8080'.success)
$app=[bool]$http.success
$status=if($ip -and $app){"CONFIRMED"}elseif($ip){"PARTIAL"}else{"FAILED"}
$data=[ordered]@{
 schema_version="1.0"
 operator=[ordered]@{name=$c.Operator.name;short_name=$c.Operator.short_name;tested_ip=$identity.ip;asn=$c.Operator.asn;prefix=$c.Operator.prefix}
 measurement_target=$target
 measurement=[ordered]@{date=$stamp;status=$status}
 identity=$identity
 whois=$whois
 bgp=$bgp
 bgp_tools=$bgpTools
 peeringdb=$peeringDb
 routing=$routing
 traceroute=$trace
 connectivity=[ordered]@{tcp=$tcp;http=$http;bidirectional=$null}
 tcpdump=$tcpdump
 security=$security
 ix=$ix
 result=[ordered]@{ip_connectivity=$ip;application_connectivity=$app;bgp_reachability=$bgp.reachability;mpls_observed=$routing.mpls_observed;direct_physical_interconnect=$ix.direct_peer_proven;specific_ix_path=$ix.specific_ix_path_proven;internet_transit=$ix.internet_transit;exact_physical_path=$null}
 evidence=@("identity","RDAP/WHOIS","RIPE RIS","bgp.tools","PeeringDB","routing","traceroute","TCP","HTTP")
}
$file="$root/data/$($c.Operator.short_name.ToLower()).json"
Save-Json $file $data
$indexFile="$root/data/data.json"
$index=Get-Content $indexFile -Raw|ConvertFrom-Json
$item=$index.operators|Where-Object {$_.short_name -eq $c.Operator.short_name}
if($item){$item.tested_ip=$data.operator.tested_ip;$item.asn=$data.operator.asn;$item.prefix=$data.operator.prefix;$item.status=$status}
Save-Json $indexFile $index
$data|ConvertTo-Json -Depth 30