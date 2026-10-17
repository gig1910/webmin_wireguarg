# Analytics page controller, separated from CGI rendering and API handlers.
# Keep JavaScript embedded in a Perl heredoc to use the same trusted JSON
# arguments and Webmin CGI delivery semantics as the original page.
sub wg_analytics_controller_script
{
    my ($strings, $selected_json, $initial_interface_json) = @_;
    return <<HTML;
<script>
(function(){
  'use strict';
  const root=document.getElementById('wg-analytics');
  if (!root)return;
  const labels=$strings, initial=$selected_json, initialInterface=$initial_interface_json;
  const peer=root.querySelector('[data-peer]'), iface=root.querySelector('[data-interface]');
  const period=root.querySelector('[data-period]');
  const auto=root.querySelector('[data-auto-refresh]');
  const custom=root.querySelector('[data-custom]'), start=root.querySelector('[data-from]');
  const end=root.querySelector('[data-to]'), output=root.querySelector('[data-error]');
  const graph=root.querySelector('[data-chart]'), chartSvg=root.querySelector('[data-chart-svg]');
  const eventSort=window.WireGuardTableSort && window.WireGuardTableSort.attach(
    root.querySelector('[data-wg-event-sort-table]'),['time','name','text','ip','ip']);
  let data=null, seq=0, controller=null, autoTimer=null;
  function localInput(t) {
    const d=new Date(t), pad=x=>String(x).padStart(2,'0');
    return d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate())+
       'T'+pad(d.getHours())+':'+pad(d.getMinutes());
  }
  function bytes(v) { return window.WireGuardChart.formatBytes(v,false); }
  function range() {
    let to=Math.floor(Date.now()/1000), from;
    if(period.value==='custom'){
      from=Math.floor(new Date(start.value).getTime()/1000);
      to=Math.floor(new Date(end.value).getTime()/1000);
    }else if(['month','quarter','halfyear','year'].includes(period.value)){
      const d=new Date(to*1000);
      const day=d.getDate();
      // Clamp month/year subtraction at the last day of the target month
      // (e.g., March 31 -> February 28, leap day -> February 28).
      d.setDate(1);
      if(period.value==='year')d.setFullYear(d.getFullYear()-1);
      else d.setMonth(d.getMonth()-({month:1,quarter:3,halfyear:6})[period.value]);
      d.setDate(Math.min(day,new Date(d.getFullYear(),d.getMonth()+1,0).getDate()));
      from=Math.floor(d.getTime()/1000);
    }else from=to-Number(period.value);
    if(!Number.isFinite(from) || !Number.isFinite(to) ||
       from<=0 || to-from<21600 || to>Date.now()/1000+60 ||
       to-from>366*86400)throw new Error(labels.analytics_error_time);
    return {from,to};
  }
  function peerLabel(p){
    const key=(p.public_key||'').slice(0,12)+'…';
    const name=(p.name||'').trim();
    return (name||key)+' ('+(p.interface||'—')+' · '+key+')';
  }
  function draw() {
    if(!data||!chartSvg||graph.closest('[data-wg-analytics-pane]').hidden)return;
    const rows=data.buckets||[];
    const step=Math.max(600,Number(data.bucket_seconds)||600);
    const first=Math.floor(data.from/600)*600;
    const span=Math.max(600,data.to-first);
    const slots=Math.max(1,Math.ceil(span/step));
    const values=Array.from({length:slots},()=>({tx:0,rx:0,observed:false}));
    for(const row of rows){
      const pos=Math.floor((Number(row.period)-first)/step);
      if(pos<0||pos>=slots)continue;
      values[pos].tx+=Math.max(0,Number(row.tx)||0);
      values[pos].rx+=Math.max(0,Number(row.rx)||0);
      values[pos].observed=true;
    }
    const colors=window.WireGuardChart.themeColors();
    const width=Math.max(320,Math.round(chartSvg.clientWidth||graph.clientWidth||900));
    const height=300,pad={l:76,r:12,t:18,b:28};
    const pw=width-pad.l-pad.r,half=(height-pad.t-pad.b)/2,zero=pad.t+half;
    const max=Math.max(1024,...values.map(v=>Math.max(v.tx,v.rx)));
    const limit=window.WireGuardChart.niceLimit(max);
    const svgNs='http://www.w3.org/2000/svg';
    chartSvg.setAttribute('viewBox','0 0 '+width+' '+height);
    chartSvg.replaceChildren();
    function element(tag,attrs,text,parent){
      const node=document.createElementNS(svgNs,tag);
      for(const [key,value] of Object.entries(attrs||{}))node.setAttribute(key,String(value));
      if(text!==undefined&&text!==null)node.textContent=text;
      (parent||chartSvg).append(node);
      return node;
    }
    function line(x1,y1,x2,y2,stroke,weight){
      element('line',{x1,y1,x2,y2,stroke,'stroke-width':weight||1});
    }
    function label(text,x,y,anchor){
      element('text',{x,y,fill:colors.text,'font-size':12,
        'text-anchor':anchor||'end','dominant-baseline':'middle'},text);
    }
    for(let i=0;i<=4;i++){
      const offset=half*i/4,upper=zero-offset,lower=zero+offset;
      if(i){
        line(pad.l,upper,width-pad.r,upper,colors.grid);
        line(pad.l,lower,width-pad.r,lower,colors.grid);
      }
      label(bytes(limit*i/4),pad.l-7,upper);
      if(i)label(bytes(limit*i/4),pad.l-7,lower);
    }
    line(pad.l,zero,width-pad.r,zero,colors.zero,1.5);
    label('TX',pad.l+5,pad.t+8,'start');
    label('RX',pad.l+5,height-pad.b-8,'start');
    if(!rows.length){
      label(labels.analytics_graph_empty,width/2,zero-8,'middle');
    }
    function series(kind,sign){
      const color=colors[kind],segments=[];let current=[];
      for(let i=0;i<slots;i++){
        const v=values[i];
        if(!v.observed){
          if(current.length){segments.push(current);current=[];}
          continue;
        }
        const x=pad.l+pw*Math.max(0,Math.min(1,(first+(i+.5)*step-data.from)/(data.to-data.from)));
        const y=zero+sign*half*Math.min(1,v[kind]/limit);
        current.push({x,y,v:v[kind],time:first+i*step,rx:v.rx,tx:v.tx});
      }
      if(current.length)segments.push(current);
      for(const segment of segments){
        const firstPt=segment[0],lastPt=segment[segment.length-1];
        const coords=segment.map(p=>p.x.toFixed(2)+','+p.y.toFixed(2));
        const lineD='M'+coords.join(' L');
        const areaD='M'+firstPt.x.toFixed(2)+','+zero.toFixed(2)+
          ' L'+coords.join(' L')+' L'+lastPt.x.toFixed(2)+','+zero.toFixed(2)+' Z';
        element('path',{d:areaD,fill:color,'fill-opacity':.22,stroke:'none'});
        element('path',{d:lineD,fill:'none',stroke:color,'stroke-width':2,
          'stroke-linejoin':'round'});
        for(const point of segment){
          const dot=element('circle',{cx:point.x,cy:point.y,r:3,fill:color,'fill-opacity':.01});
          element('title',{},new Date(point.time*1000).toLocaleString()+
            '\\n'+labels.analytics_graph_tx+': '+bytes(point.tx)+
            '\\n'+labels.analytics_graph_rx+': '+bytes(point.rx),dot);
        }
      }
    }
    series('tx',-1);series('rx',1);
    label(new Date(data.from*1000).toLocaleString(),pad.l,height-8,'start');
    label(new Date(data.to*1000).toLocaleString(),width-pad.r,height-8,'end');
    root.querySelector('[data-chart-scale]').textContent=
      labels.analytics_graph_scale+': '+bytes(limit)+
      (step>600?' / '+Math.round(step/600)+' × 10m':' / 10m');
    graph.setAttribute('aria-label',labels.analytics_chart+'; '+
      labels.analytics_graph_rx+': '+bytes(Number(data.totals.rx))+'; '+
      labels.analytics_graph_tx+': '+bytes(Number(data.totals.tx)));
  }
  function render(result) {
    const previous=peer.value;
    const allPeers=result.peers||[];
    const selectedInterface=iface.value;
    const interfaces=[...new Set(allPeers.map(p=>p.interface).filter(Boolean))].sort();
    iface.replaceChildren();
    for(const name of ['',...interfaces]){
      const opt=document.createElement('option');
      opt.value=name;opt.textContent=name||labels.analytics_all_interfaces;
      iface.append(opt);
    }
    iface.value=interfaces.includes(selectedInterface)?selectedInterface:'';
    const filtered=allPeers.filter(p=>!iface.value||p.interface===iface.value);
    const options=[{id:'',public_key:labels.analytics_all_peers},...filtered];
    peer.replaceChildren();
    for(const p of options) {
      const opt=document.createElement('option');
      opt.value=p.id;
      opt.textContent=p.id ? peerLabel(p)+
           (p.active?' • '+labels.analytics_peer_active:' • '+labels.analytics_peer_inactive) :
           labels.analytics_all_peers;
      if(p.id)opt.title='PublicKey: '+p.public_key+'\\nSHA256: '+p.id;
      peer.append(opt);
    }
    peer.value=options.some(o=>o.id===previous)?previous:'';
    root.querySelector('[data-rx]').textContent=labels.analytics_rx+': '+bytes(Number(result.totals.rx));
    root.querySelector('[data-tx]').textContent=labels.analytics_tx+': '+bytes(Number(result.totals.tx));
    root.querySelector('[data-db-size]').textContent=labels.analytics_db_size+': '+
      bytes(Number(result.db_bytes));
    const selectedPeer=(result.peers||[]).find(p=>p.id===peer.value);
    root.querySelector('[data-last-handshake]').textContent=labels.analytics_last_handshake+': '+
      (selectedPeer && Number(selectedPeer.handshake)>0
       ? new Date(Number(selectedPeer.handshake)*1000).toLocaleString()
       : (selectedPeer ? labels.analytics_no_handshake : '—'));
    root.querySelector('[data-handshake-ip]').textContent=labels.analytics_handshake_ip+': '+
      (selectedPeer && selectedPeer.handshake_ip ? selectedPeer.handshake_ip : '—');
    const notes=[];
    if(!result.buckets.length && !result.events.length)notes.push(labels.analytics_empty);
    else {
      const covered=new Set((result.buckets||[]).map(b=>Number(b.period)));
      const expected=Math.ceil((result.to-result.from)/600);
      if(covered.size<expected)notes.push(labels.analytics_partial);
    }
    if(result.truncated)notes.push(labels.analytics_truncated);
    if(result.events_truncated)notes.push(labels.analytics_events_limited);
    if(result.totals.resets)notes.push(labels.analytics_resets);
    if(result.totals.gaps)notes.push(labels.analytics_gaps);
    root.querySelector('[data-notes]').textContent=notes.join(' ');
    const body=root.querySelector('[data-events]');
    body.replaceChildren();
    for(const e of result.events){
      const row=document.createElement('tr');
      const peerData=(result.peers||[]).find(p=>p.id===e.peer_id);
      const columns=[
        new Date(e.at*1000).toLocaleString(),
        peerData?peerLabel(peerData):e.peer_id.slice(0,16)+'…',
        labels['analytics_event_'+e.type]||e.type,e.endpoint||'—',e.previous||'—'
      ];
      for(let i=0;i<columns.length;i++){
        const td=document.createElement('td');
        if(i===1 && peerData && peerData.peer_url){
          const url=new URL(peerData.peer_url,window.location.href);
          if(url.origin===window.location.origin && url.pathname.endsWith('/wireguard/edit_peer.cgi')){
            const link=document.createElement('a');
            link.href=url.toString();
            link.textContent=columns[i];
            link.className='wg-analytics-peer-link';
            link.setAttribute('data-wg-module-navigation','1');
            link.title=labels.analytics_peer_open;
            td.append(link);
          }else td.textContent=columns[i];
        }else td.textContent=columns[i];
        row.append(td);
      }
      body.append(row);
    }
    if(eventSort)eventSort.apply();
    draw();
  }
  function scheduleAuto(){
    if(autoTimer!==null){clearTimeout(autoTimer);autoTimer=null;}
    const interval=Number(auto.value);
    if(!interval||period.value==='custom'||document.hidden||!root.isConnected)return;
    autoTimer=setTimeout(()=>{
      autoTimer=null;
      if(!document.hidden&&root.isConnected)refresh();
    },interval*1000);
  }
  async function refresh(){
    const serial=++seq;
    if(controller)controller.abort();
    controller=new AbortController();
    output.hidden=true;
    try{
      const dates=range();
      const url=new URL(root.dataset.url,window.location.href);
      url.searchParams.set('from',String(dates.from));url.searchParams.set('to',String(dates.to));
      if(iface.value)url.searchParams.set('interface',iface.value);
      if(peer.value)url.searchParams.set('peer_id',peer.value);
      const res=await fetch(url.toString(),{signal:controller.signal,
        cache:'no-store',credentials:'same-origin',redirect:'error',
        headers:{'Accept':'application/json','X-Requested-With':'XMLHttpRequest'}});
      if(!(res.headers.get('content-type')||'').includes('application/json'))throw new Error('Non-JSON server response');
      const json=await res.json();
      if(!json.ok)throw new Error(json.error||'Analytics request failed');
      if(serial!==seq||!root.isConnected)return;
      data=json;render(json);
    }catch(ex){
      if(ex.name==='AbortError'||serial!==seq)return;
      output.textContent=ex.message;output.hidden=false;
    }finally{
      if(serial===seq)scheduleAuto();
    }
  }
  period.addEventListener('change',()=>{
    custom.hidden=period.value!=='custom';
    auto.disabled=!custom.hidden;
    root.querySelector('[data-auto-custom-note]').hidden=custom.hidden;
    if(!custom.hidden){
      if(autoTimer!==null){clearTimeout(autoTimer);autoTimer=null;}
      end.value=localInput(Date.now());start.value=localInput(Date.now()-86400000);
    }else refresh();
  });
  iface.addEventListener('change',()=>{peer.value='';refresh()});
  peer.addEventListener('change',refresh);
  root.querySelectorAll('[data-wg-analytics-tab]').forEach(button=>{
    button.addEventListener('click',event=>{
      event.preventDefault();
      const selected=button.dataset.wgAnalyticsTab;
      root.querySelectorAll('[data-wg-analytics-pane]').forEach(pane=>{
        pane.hidden=pane.dataset.wgAnalyticsPane!==selected;
      });
      root.querySelectorAll('[data-wg-analytics-tab]').forEach(item=>{
        const active=item===button;
        item.setAttribute('aria-selected',active?'true':'false');
        item.parentElement.classList.toggle('active',active);
      });
      if(selected==='graph')draw();
    });
  });
  root.querySelector('[data-apply]').addEventListener('click',refresh);
  auto.addEventListener('change',scheduleAuto);
  document.addEventListener('visibilitychange',()=>{
    if(document.hidden){
      if(autoTimer!==null){clearTimeout(autoTimer);autoTimer=null;}
      if(controller)controller.abort();
    }else if(auto.value!=='0'&&period.value!=='custom'&&root.isConnected)refresh();
  });
  window.addEventListener('resize',draw);
  window.addEventListener('pagehide',()=>{
    window.removeEventListener('resize',draw);
    if(autoTimer!==null){clearTimeout(autoTimer);autoTimer=null;}
    if(controller)controller.abort();
  });
  if(initialInterface){
    const option=document.createElement('option');
    option.value=initialInterface;option.textContent=initialInterface;
    iface.append(option);iface.value=initialInterface;
  }
  const originalOption=document.createElement('option');originalOption.value=initial;
  originalOption.textContent=labels.analytics_loading;peer.append(originalOption);
  refresh().then(()=>{if(initial && peer.querySelector('option[value="'+initial+'"]')){peer.value=initial;refresh();}});
})();
</script>
HTML
}

1;
