const API={dashboard:"../data/data.json"};
let indexData=null,operatorCache={};
const $id=id=>document.getElementById(id);
function esc(v){return String(v??"—").replace(/[&<>"']/g,m=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[m]));}
function badge(v){if(v===true)v="TRUE";if(v===false)v="FALSE";const s=String(v??"—"),u=s.toUpperCase();let c="secondary";if(["SUCCESS","200 OK","CONFIRMED","AVAILABLE","TRUE","FOUND","LOOKUP_OK"].includes(u))c="success";else if(["FAILED","FAIL","DOWN","NOT PROVEN","NOT_PROVEN","НЕДОСТУПЕН","FALSE","ERROR"].includes(u))c="danger";else if(["TIMEOUT","NOT OBSERVED","NOT_OBSERVED","PARTIAL"].includes(u))c="warning";return '<span class="badge text-bg-'+c+'">'+esc(s)+'</span>';}
function card(title,value,sub){return '<div class="col-6 col-xl-3"><div class="card metric"><div class="card-body"><div class="text-secondary small">'+esc(title)+'</div><div class="fs-3 fw-semibold">'+esc(value)+'</div><div class="small text-secondary">'+esc(sub||"")+'</div></div></div></div>';}
function opName(op){return op.operator?.short_name||op.short_name||op.name||"—";}
function renderSummary(ops){
 const tested=ops.filter(o=>o.status&&o.status!=="NOT_TESTED").length;
 const ip=ops.filter(o=>o.result?.ip_connectivity===true).length;
 const app=ops.filter(o=>o.result?.application_connectivity===true).length;
 const ix=ops.filter(o=>o.result?.specific_ix_path===true).length;
 $id("summary").innerHTML=card("Операторов",ops.length,"в конфигурации")+card("Измерено",tested,"имеют результат")+card("IP-связность",ip,"TCP 22 до Selectel")+card("Приложение",app,"HTTP/8080")+card("IX path доказан",ix,"только явные evidence");
}
function rowsFor(op){
 const r=op.result||{},c=op.connectivity||{},p=op.peeringdb||{},rs=op.ripestat||{},x=op.ix||{};
 return [
  {test:"IP connectivity",result:r.ip_connectivity,details:"TCP 22/8080"},
  {test:"Application",result:r.application_connectivity,details:"HTTP/8080"},
  {test:"BGP reachability",result:r.bgp_reachability,details:"RIPEstat routing-status"},
  {test:"RIPEstat AS-path",result:rs.path_observation_count>0,details:String(rs.path_observation_count||0)+" observations"},
  {test:"Direct AS adjacency",result:rs.direct_as_adjacency,details:"RIPEstat"},
  {test:"Common IX",result:p.direct_peering_possible,details:(p.common_ix||[]).map(i=>i.name).filter(Boolean).join(", ")||"PeeringDB"},
  {test:"MPLS observed",result:r.mpls_observed,details:"Local routing evidence"},
  {test:"Direct physical interconnect",result:r.direct_physical_interconnect,details:"Requires data-plane evidence"},
  {test:"Specific IX path",result:r.specific_ix_path,details:"Explicit path evidence only"},
  {test:"Internet transit",result:r.internet_transit,details:"Third-party ASN on measured path"},
  {test:"Resilience hypothesis",result:r.resilience_hypothesis,details:"Passive hypothesis only — not a verified failover test"},
  {test:"Exact physical path",result:r.exact_physical_path,details:"Not inferred"}
 ];
}
function renderMatrix(ops){
 const rows=[];
 for(const op of ops){for(const x of rowsFor(op))rows.push({operator:opName(op),test:x.test,result:badge(x.result),details:x.details});}
 $("#matrix").bootstrapTable("destroy").bootstrapTable({columns:[{field:"operator",title:"Оператор"},{field:"test",title:"Проверка"},{field:"result",title:"Результат",formatter:v=>v},{field:"details",title:"Основание"}],data:rows});
}
function renderRecent(ops){
 const rows=ops.map(op=>({date:op.measurement?.date||"—",operator:opName(op),status:badge(op.measurement?.status||op.status),ip:op.operator?.tested_ip||op.tested_ip||"—",asn:op.operator?.asn||"—"}));
 $("#recent").bootstrapTable("destroy").bootstrapTable({columns:[{field:"date",title:"Дата"},{field:"operator",title:"Оператор"},{field:"ip",title:"IP источника"},{field:"asn",title:"ASN"},{field:"status",title:"Статус",formatter:v=>v}],data:rows.sort((a,b)=>String(b.date).localeCompare(String(a.date)))});
}
function hopLabel(h){return (h.ip||"*")+(h.asn?" ("+h.asn+")":"");}
function renderDetails(op){
 const r=op.result||{},t=op.traceroute||{},p=op.peeringdb||{},rs=op.ripestat||{},x=op.ix||{},bg=op.bgp||{},tcp=op.connectivity?.tcp||{};
 const common=(p.common_ix||[]).map(i=>esc(i.name)+" ("+esc(i.source_ipaddr4)+" ↔ "+esc(i.target_ipaddr4)+")").join("<br>")||"—";
 const path=(t.hops||[]).map(hopLabel).join(" → ");
 $id("details").innerHTML='<div class="row g-3"><div class="col-lg-4"><dl class="row mb-0"><dt class="col-6">IP</dt><dd class="col-6 mono">'+esc(op.operator?.tested_ip)+'</dd><dt class="col-6">ASN</dt><dd class="col-6">'+esc(op.operator?.asn)+'</dd><dt class="col-6">Prefix</dt><dd class="col-6 mono">'+esc(op.operator?.prefix)+'</dd><dt class="col-6">Дата</dt><dd class="col-6">'+esc(op.measurement?.date)+'</dd></dl></div><div class="col-lg-4"><dl class="row mb-0"><dt class="col-6">TCP 22</dt><dd class="col-6">'+badge(tcp["22"]?.success)+'</dd><dt class="col-6">TCP 8080</dt><dd class="col-6">'+badge(tcp["8080"]?.success)+'</dd><dt class="col-6">BGP</dt><dd class="col-6">'+badge(r.bgp_reachability)+'</dd><dt class="col-6">RIPE paths</dt><dd class="col-6">'+esc(rs.path_observation_count||0)+'</dd></dl></div><div class="col-lg-4"><dl class="row mb-0"><dt class="col-6">Common IX</dt><dd class="col-6">'+badge(p.direct_peering_possible)+'</dd><dt class="col-6">IX path</dt><dd class="col-6">'+badge(r.specific_ix_path)+'</dd><dt class="col-6">Transit</dt><dd class="col-6">'+badge(r.internet_transit)+'</dd><dt class="col-6">Physical</dt><dd class="col-6">'+badge(r.direct_physical_interconnect)+'</dd></dl></div></div><hr><div><strong>PeeringDB common IX</strong><div class="mt-1">'+common+'</div></div><div class="mt-3"><strong>Traceroute</strong><div class="mt-1 mono small text-break">'+esc(path||"—")+'</div></div><div class="mt-3 small text-secondary">RIPEstat visibility: '+esc(bg.visibility?.v4?.ris_peers_seeing??"—")+"/"+esc(bg.visibility?.v4?.total_ris_peers??"—")+' RIS peers; origin '+esc((bg.origins||[]).map(o=>"AS"+o.origin).join(", ")||"—")+'. '+esc(rs.note||"")+'</div>';
}
function renderTrace(ops){
 const rows=[];
 for(const op of ops){for(const h of (op.traceroute?.hops||[]))rows.push({operator:opName(op),hop:h.hop,ip:h.ip||"*",asn:h.asn||"—",prefix:h.prefix||"—",scope:h.scope||"—",rtt:(h.rtt_ms||[]).join(", "),status:badge(h.status)});}
 $("#traceTable").bootstrapTable("destroy").bootstrapTable({columns:[{field:"operator",title:"Оператор"},{field:"hop",title:"#",sortable:true},{field:"ip",title:"IP",formatter:v=>'<span class="mono">'+esc(v)+'</span>'},{field:"asn",title:"ASN"},{field:"prefix",title:"Prefix"},{field:"scope",title:"Scope"},{field:"rtt",title:"RTT ms"},{field:"status",title:"Статус",formatter:v=>v}],data:rows});
}
function renderRouting(ops){
 const rows=ops.map(op=>{const r=op.result||{},rs=op.ripestat||{},p=op.peeringdb||{},x=op.ix||{};return{operator:opName(op),bgp:badge(r.bgp_reachability),origin:((op.bgp?.origins||[]).map(o=>"AS"+o.origin).join(", "))||"—",visibility:(op.bgp?.visibility?.v4?.ris_peers_seeing!=null?op.bgp.visibility.v4.ris_peers_seeing+"/"+op.bgp.visibility.v4.total_ris_peers:"—"),risPaths:rs.path_observation_count||0,directAdj:badge(rs.direct_as_adjacency),commonIx:(p.common_ix||[]).map(i=>i.name).join(", ")||"—",ixPath:badge(r.specific_ix_path),transit:badge(r.internet_transit),physical:badge(r.direct_physical_interconnect),ixStatus:x.status||"—"};});
 $("#routingTable").bootstrapTable("destroy").bootstrapTable({columns:[{field:"operator",title:"Оператор"},{field:"bgp",title:"BGP",formatter:v=>v},{field:"origin",title:"Origin"},{field:"visibility",title:"RIS visibility"},{field:"risPaths",title:"RIPE paths"},{field:"directAdj",title:"AS adjacency",formatter:v=>v},{field:"commonIx",title:"Common IX"},{field:"ixPath",title:"IX path",formatter:v=>v},{field:"transit",title:"Transit",formatter:v=>v},{field:"physical",title:"Physical",formatter:v=>v},{field:"ixStatus",title:"IX status"}],data:rows});
}
function renderEvidence(ops){
 const blocks=ops.map(op=>{const rs=op.ripestat||{},p=op.peeringdb||{},x=op.ix||{},rz=op.resilience||{};return '<div class="mb-3"><h6>'+esc(opName(op))+'</h6><ul class="mb-0"><li>PeeringDB: '+esc(p.status||"—")+', common IX: '+esc((p.common_ix||[]).map(i=>i.name).join(", ")||"—")+'</li><li>RIPEstat: '+esc(rs.status||"—")+', AS-path observations: '+esc(rs.path_observation_count||0)+', direct adjacency: '+esc(rs.direct_as_adjacency)+'</li><li>IX classifier: '+esc(x.status||"—")+'; specific path: '+esc(op.result?.specific_ix_path)+'</li><li>Resilience hypothesis: '+esc(rz.hypothesis||"—")+' (passive measurement only — not a verified failover test)</li><li>Note: '+esc(rs.note||p.note||x.note||"—")+'</li></ul></div>';}).join("");
 $id("evidence").innerHTML=blocks||"Нет данных.";
}
async function loadJson(url){const response=await fetch(url+"?t="+Date.now());if(!response.ok)throw new Error("HTTP "+response.status);const data=await response.json();if(data.schema_version!=="1.0")throw new Error("Unsupported schema version: "+(data.schema_version||"unknown"));return data;}
async function selectOperator(short){
 document.querySelectorAll("[data-op]").forEach(b=>b.classList.toggle("active",b.dataset.op===short));
 if(short==="all"){
  const ops=await Promise.all(indexData.operators.filter(x=>x.status!=="NOT_TESTED").map(x=>loadJson("../data/"+x.file)));
  $id("title").textContent="Все операторы";renderSummary(indexData.operators);renderMatrix(ops);renderRecent(ops);renderTrace(ops);renderRouting(ops);renderEvidence(ops);$id("details").innerHTML="Выберите оператора слева для подробностей.";return;
 }
 const meta=indexData.operators.find(x=>x.short_name===short);if(!meta)return;
 const op=operatorCache[short]||(operatorCache[short]=await loadJson("../data/"+meta.file));
 $id("title").textContent=meta.name;renderSummary([op]);renderMatrix([op]);renderRecent([op]);renderTrace([op]);renderRouting([op]);renderEvidence([op]);renderDetails(op);
}
function makeNav(){const items=[{name:"Все операторы",short_name:"all"}].concat(indexData.operators);for(const host of [$id("desktopSide"),$id("mobileSide")]){host.innerHTML='<div class="small text-uppercase text-secondary mb-2">Операторы</div>'+items.map(x=>'<button class="nav-link w-100 text-start mb-1 border-0 rounded '+(x.short_name==="all"?"active":"")+'" data-op="'+esc(x.short_name)+'">'+esc(x.name||x.short_name)+'</button>').join("");host.querySelectorAll("[data-op]").forEach(b=>b.onclick=()=>selectOperator(b.dataset.op));}}
async function loadDashboard(){try{indexData=await loadJson(API.dashboard);$id("target").textContent=indexData.project.measurement_target.name+" · "+indexData.project.measurement_target.ip+" · "+indexData.project.measurement_target.asn;makeNav();await selectOperator("all");$id("loadStatus").textContent="OK";$id("loadStatus").className="badge text-bg-success";}catch(e){$id("error").textContent="Dashboard loading error: "+e.message;$id("error").classList.remove("d-none");$id("loadStatus").textContent="ERROR";$id("loadStatus").className="badge text-bg-danger";console.error(e);}}
document.addEventListener("DOMContentLoaded",loadDashboard);