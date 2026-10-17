# Peer-details activity controller: navigation, history events and sorting.
# Inputs are JSON encoded by the CGI; the returned markup remains scoped to
# the existing peer detail root, preserving the current runtime contract.
sub wg_peer_activity_tabs_script
{
    my ($js_tabs_id, $js_analytics_url, $js_peer_id, $js_activity_labels) = @_;
    return <<PEER_TABS_SCRIPT;
<style>
.wg-peer-detail-tabs > .nav-tabs{margin:14px 0}
.wg-peer-detail-tabs [data-wg-peer-pane][hidden]{display:none!important}
.wg-peer-activity-toolbar{display:flex;gap:10px;align-items:end;margin:15px 0;flex-wrap:wrap}
.wg-peer-activity-toolbar label{display:flex;flex-direction:column;gap:4px}
</style>
<script>
(function(){
 'use strict';
 const root=document.getElementById($js_tabs_id);
 if(!root)return;
 const url=$js_analytics_url;
 const peerId=$js_peer_id;
 const labels=$js_activity_labels;
 const sort=window.WireGuardTableSort&&window.WireGuardTableSort.attach(
     root.querySelector('[data-wg-peer-activity-sort]'),
     ['time','text','ip','ip']);
 const status=root.querySelector('[data-wg-peer-activity-status]');
 const body=root.querySelector('[data-wg-peer-activity-rows]');
 let request=null,seq=0;
 function show(tab){
   root.querySelectorAll('[data-wg-peer-pane]').forEach(p=>{
     p.hidden=p.dataset.wgPeerPane!==tab;
   });
   root.querySelectorAll('[data-wg-peer-tab]').forEach(a=>{
     const selected=a.dataset.wgPeerTab===tab;
     a.setAttribute('aria-selected',selected?'true':'false');
     a.parentElement.classList.toggle('active',selected);
   });
   if(tab==='activity')load();
   if(tab==='usage'){
     // A hidden Canvas measures zero width; redraw when visible.
     requestAnimationFrame(()=>window.dispatchEvent(new Event('resize')));
   }
 }
 async function load(){
   const serial=++seq;
   if(request)request.abort();
   request=new AbortController();
   status.textContent=labels.loading;
   const now=Math.floor(Date.now()/1000),span=Number(root.querySelector('[data-wg-peer-activity-period]').value);
   const requestUrl=new URL(url,window.location.href);
   requestUrl.searchParams.set('peer_id',peerId);
   requestUrl.searchParams.set('from',String(now-span));
   requestUrl.searchParams.set('to',String(now));
   try{
     const response=await fetch(requestUrl.toString(),{
       credentials:'same-origin',cache:'no-store',signal:request.signal,headers:{Accept:'application/json'}
     });
     if(!(response.headers.get('content-type')||'').includes('application/json'))
       throw new Error('HTTP '+response.status);
     const result=await response.json();
     if(!result.ok)throw new Error(result.error||'HTTP '+response.status);
     if(serial!==seq||!root.isConnected)return;
     body.replaceChildren();
     for(const event of result.events||[]){
       const tr=document.createElement('tr');
       const cols=[
         new Date(event.at*1000).toLocaleString(),
         labels.events[event.type]||event.type,
         event.endpoint||'—',event.previous||'—'
       ];
       for(const value of cols){
         const td=document.createElement('td');
         td.textContent=value;tr.append(td);
       }
       body.append(tr);
     }
     if(sort)sort.apply();
     status.textContent=result.events_truncated?labels.limited:
       result.events.length?'':labels.empty;
   }catch(err){
     if(err.name!=='AbortError'&&serial===seq)status.textContent=err.message||String(err);
   }
 }
 root.querySelectorAll('[data-wg-peer-tab]').forEach(a=>a.addEventListener('click',e=>{
   e.preventDefault();show(a.dataset.wgPeerTab);
 }));
 root.querySelector('[data-wg-peer-activity-refresh]').addEventListener('click',load);
 root.querySelector('[data-wg-peer-activity-period]').addEventListener('change',load);
 window.addEventListener('pagehide',()=>{if(request)request.abort();});
})();
</script>
PEER_TABS_SCRIPT
}

1;
