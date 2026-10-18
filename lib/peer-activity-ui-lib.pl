# Peer-details activity controller: navigation, history events and sorting.
# Inputs are JSON encoded by the CGI; the returned markup remains scoped to
# the existing peer detail root, preserving the current runtime contract.
sub wg_peer_activity_tabs_script
{
    my ($js_tabs_id, $js_analytics_url, $js_peer_id, $js_activity_labels,
        $js_network_cache_url) = @_;
    $js_network_cache_url ||= '""';
    return <<PEER_TABS_SCRIPT;
<style>
.wg-peer-detail-tabs > .nav-tabs{margin:14px 0}
.wg-peer-detail-tabs [data-wg-peer-pane][hidden]{display:none!important}
.wg-peer-activity-toolbar{display:flex;gap:10px;align-items:end;margin:15px 0;flex-wrap:wrap}
.wg-peer-activity-toolbar label{display:flex;flex-direction:column;gap:4px}
.wg-ui .wg-peer-activity-events th:first-child,.wg-ui .wg-peer-activity-events td:first-child{width:190px;white-space:nowrap;font-variant-numeric:tabular-nums}
.wg-ui .wg-peer-activity-events th:nth-child(3),.wg-ui .wg-peer-activity-events td:nth-child(3){width:34px;text-align:center}
.wg-ui .wg-peer-activity-events th:nth-child(4),.wg-ui .wg-peer-activity-events td:nth-child(4){width:66px;text-align:center}
.wg-ui .wg-peer-activity-events th:last-child,.wg-ui .wg-peer-activity-events td:last-child{width:38px;text-align:center}
.wg-ui .wg-peer-activity-events td:nth-child(5),.wg-ui .wg-peer-activity-events td:nth-child(6){font-family:ui-monospace,Consolas,monospace}
</style>
<script>
(function(){
 'use strict';
 const root=document.getElementById($js_tabs_id);
 if(!root)return;
 const url=$js_analytics_url;
 const peerId=$js_peer_id;
 const labels=$js_activity_labels;
 const networkUrl=$js_network_cache_url;
 const sort=window.WireGuardTableSort&&window.WireGuardTableSort.attach(
     root.querySelector('[data-wg-peer-activity-sort]'),
     ['time','text','actions','actions','ip','ip','actions']);
 const status=root.querySelector('[data-wg-peer-activity-status]');
 const body=root.querySelector('[data-wg-peer-activity-rows]');
 const ipTemplate=root.querySelector('[data-wg-ip-template] button');
 let request=null,seq=0,networkRequest=null;
 function isNumericIp(value){
   const t=String(value||'').trim();
   return t.length>=3&&t.length<=45&&/^[0-9a-f:.]+\$/.test(t) &&
     (t.includes('.')||t.includes(':'));
 }
 function lookupButton(ip,at){
   if(!ipTemplate||!isNumericIp(ip))return null;
   const button=ipTemplate.cloneNode(true);
   button.dataset.wgIpValue=ip;
   button.dataset.wgIpAt=String(at);
   return button;
 }
 async function fillKnownNetworks(serial){
   if(!networkUrl)return;
   const nodes=Array.from(body.querySelectorAll('[data-wg-history-ip]'));
   const ips=Array.from(new Set(nodes.map(x=>x.dataset.wgHistoryIp)))
       .filter(Boolean).slice(0,128);
   if(!ips.length)return;
   if(networkRequest)networkRequest.abort();
   networkRequest=new AbortController();
   const controller=networkRequest;
   const url=new URL(networkUrl,window.location.href);
   url.searchParams.set('ips',ips.join(','));
   try{
     const data=await window.WireGuardTransport.requestJson(url.toString(),
       {signal:controller.signal,credentials:'same-origin'},{requireOk:true});
     if(serial!==seq||controller.signal.aborted||!root.isConnected)return;
     for(const node of nodes){
       const info=data.results&&data.results[node.dataset.wgHistoryIp];
       const badge=node.querySelector('.wg-network-icon');
       const country=node.querySelector('.wg-geoip-country');
       if(!info)continue;
       if(badge){
         badge.textContent=info.icon||'?';
         badge.dataset.custom=info.icon&&info.icon!=='?'?'1':'0';
         badge.title=[info.cidr,info.label,info.country].filter(Boolean).join(' — ');
       }
       if(country&&/^[a-z]{2}\$/i.test(String(info.country||''))){
         const code=info.country.toUpperCase();
         country.textContent=window.WireGuardUI.flag(code)+' '+code;
         country.title=code;
       }
     }
   }catch(_){/* Cache lookup is optional and never sends WHOIS traffic. */}
 }

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
     const result=await window.WireGuardTransport.requestJson(
       requestUrl.toString(),{signal:request.signal},{requireOk:true});
     if(serial!==seq||!root.isConnected)return;
     body.replaceChildren();
     for(const event of result.events||[]){
       const row=window.WireGuardTableSort.appendTextRow(body,[
         new Date(event.at*1000).toLocaleString(),
         labels.events[event.type]||event.type,
         '', '', event.endpoint||'—',event.previous||'—',''
       ]);
       if(isNumericIp(event.endpoint)){
         const marker=document.createElement('span');
         marker.dataset.wgHistoryIp=event.endpoint;
         const badge=document.createElement('span');
         badge.className='wg-network-icon';
         badge.textContent='?';
         marker.append(badge);
         row.cells[2].append(marker);
         const country=document.createElement('span');
         country.dataset.wgHistoryIp=event.endpoint;
         const countryText=document.createElement('span');
         countryText.className='wg-geoip-country';
         country.append(countryText);
         row.cells[3].append(country);
         const button=lookupButton(event.endpoint,event.at);
         if(button)row.cells[6].append(button);
       }
       const oldButton=lookupButton(event.previous,event.at);
       if(oldButton)row.cells[5].append(oldButton);
     }
     if(sort)sort.apply();
     fillKnownNetworks(serial);
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
