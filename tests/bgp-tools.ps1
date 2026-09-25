param([Parameter(Mandatory)][string]$Operator)
. "$PSScriptRoot/common.ps1"

function Get-BgpToolsWhois {
  param([Parameter(Mandatory)][string]$Query)
  try {
    $client=[System.Net.Sockets.TcpClient]::new()
    $client.Connect("bgp.tools",43)
    $stream=$client.GetStream()
    $writer=[System.IO.StreamWriter]::new($stream)
    $writer.NewLine=[Environment]::NewLine
    $writer.AutoFlush=$true
    $writer.WriteLine("-v $Query")
    $reader=[System.IO.StreamReader]::new($stream)
    $text=$reader.ReadToEnd()
    $reader.Dispose();$writer.Dispose();$stream.Dispose();$client.Dispose()
    $lines=@($text -split [Environment]::NewLine | Where-Object {$_.Trim()})
    [pscustomobject]@{
      query=$Query
      success=($lines.Count -gt 0)
      lines=$lines
      raw=$text
      source="bgp.tools whois"
    }
  } catch {
    [pscustomobject]@{
      query=$Query
      success=$false
      lines=@()
      raw=""
      source="bgp.tools whois"
      error=$_.Exception.Message
    }
  }
}

function Parse-BgpToolsAsn {
  param([string[]]$Lines)
  foreach($line in $Lines){
    if($line -match '^\s*(\d+)\s+\|\s+'){
      return "AS$($Matches[1])"
    }
  }
  return $null
}

$c=Get-Config $Operator
$testedIp=& "$PSScriptRoot/identity.ps1" -Operator $Operator | Select-Object -ExpandProperty ip
$targetIp=$c.Project.target.ip
$sourceAsn=$c.Operator.asn
$targetAsn=$c.Project.target.asn

$source=Get-BgpToolsWhois $testedIp
$target=Get-BgpToolsWhois $targetIp

[pscustomobject]@{
  source="bgp.tools"
  source_asn=$sourceAsn
  source_ip=$testedIp
  source_ip_lookup=$source
  target_asn=$targetAsn
  target_ip=$targetIp
  target_ip_lookup=$target
  source_ip_resolved_asn=Parse-BgpToolsAsn $source.lines
  target_ip_resolved_asn=Parse-BgpToolsAsn $target.lines
  direct_as_adjacency=$null
  observed_as_paths=@()
  status=if($source.success -and $target.success){"LOOKUP_OK"}elseif($source.success -or $target.success){"PARTIAL"}else{"ERROR"}
  note="Uses the documented bgp.tools WHOIS service; no HTML scraping. Direct adjacency and AS_PATH require a supported BGP API/feed."
}