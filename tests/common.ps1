function Get-Config {
  param([string]$Operator)
  $root=Split-Path $PSScriptRoot -Parent
  $project=Get-Content "$root/config/project.json" -Raw|ConvertFrom-Json
  $operators=Get-Content "$root/config/operators.json" -Raw|ConvertFrom-Json
  $item=$operators.operators|Where-Object {$_.short_name -eq $Operator -or $_.name -eq $Operator}
  if(-not $item){throw "Unknown operator: $Operator"}
  [pscustomobject]@{Root=$root;Project=$project;Operator=$item}
}
function Save-Json {
  param([string]$Path,$Object)
  $Object|ConvertTo-Json -Depth 30|Set-Content -Path $Path -Encoding UTF8
}