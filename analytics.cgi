#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();

ui_print_header(undef,$text{'analytics_title'},'',undef,1,1);
print wg_build_banner();
print '<ul class="nav nav-tabs" style="margin-bottom:15px"><li><a href="index.cgi">'.
    html_escape($text{'analytics_interfaces_tab'}).'</a></li><li class="active"><a href="analytics.cgi">'.
    html_escape($text{'analytics_title'}).'</a></li></ul>';
my $settings = collector_effective_settings(\%config);
print ui_alert_box(html_escape($text{'analytics_error_disabled'}),'warning')
    if (!$settings->{'analytics_enabled'});
my $url = html_escape(module_script_url('analytics_data.cgi'));
my $selected = $in{'peer_id'} || '';
$selected = '' if ($selected !~ /^[a-f0-9]{64}$/);
my $selected_json = json_encode_utf8($selected);
my $initial_interface = $in{'interface'} || '';
$initial_interface = '' if $initial_interface && !valid_interface_name($initial_interface);
my $initial_interface_json = json_encode_utf8($initial_interface);
my %labels = map { $_ => $text{$_} || $_ } qw(
    analytics_all_peers analytics_empty analytics_loading analytics_rx analytics_tx
    analytics_truncated analytics_partial analytics_warning analytics_first_seen
    analytics_last_seen analytics_peer_active analytics_peer_inactive
    analytics_events_limited analytics_db_size analytics_bucket_note
    analytics_resets analytics_gaps
    analytics_event_first_seen analytics_event_endpoint_observed
    analytics_event_endpoint_changed analytics_event_handshake_observed
    analytics_event_active analytics_event_inactive analytics_event_interface_changed
    analytics_event_counter_reset analytics_event_sample_gap
    analytics_event_legacy_history_imported
    analytics_last_handshake analytics_handshake_ip analytics_no_handshake
    analytics_event_endpoint_ip_observed analytics_event_endpoint_ip_changed
    analytics_graph_rx analytics_graph_tx analytics_graph_empty analytics_graph_scale
    analytics_filters_heading analytics_summary_heading analytics_interface
    analytics_all_interfaces analytics_peer_open analytics_maintenance_warning
    analytics_6h analytics_month analytics_quarter analytics_halfyear analytics_year
    analytics_auto_refresh analytics_auto_off analytics_auto_10m analytics_auto_30m
    analytics_auto_custom_note analytics_graph_zero analytics_error_time
    analytics_tab_graph analytics_tab_events
);
my $strings = json_encode_utf8(\%labels);
print wg_table_sort_script();
print <<HTML;
<div id="wg-analytics" data-url="$url">
 <section class="panel panel-default wg-analytics-section">
  <div class="panel-heading"><strong>$text{'analytics_filters_heading'}</strong></div>
  <div class="panel-body">
 <div class="wg-analytics-filters">
  <label>$text{'analytics_interface'} <select class="form-control" data-interface><option value="">$text{'analytics_all_interfaces'}</option></select></label>
  <label>$text{'analytics_peer'} <select class="form-control" data-peer></select></label>
  <label>$text{'analytics_period'} <select class="form-control" data-period>
   <option value="21600">$text{'analytics_6h'}</option>
   <option value="86400" selected>$text{'analytics_24h'}</option>
   <option value="604800">$text{'analytics_7d'}</option>
   <option value="month">$text{'analytics_month'}</option>
   <option value="quarter">$text{'analytics_quarter'}</option>
   <option value="halfyear">$text{'analytics_halfyear'}</option>
   <option value="year">$text{'analytics_year'}</option>
   <option value="custom">$text{'analytics_custom'}</option>
  </select></label>
  <span data-custom hidden>
   <label>$text{'analytics_from'} <input type="datetime-local" class="form-control" data-from></label>
   <label>$text{'analytics_to'} <input type="datetime-local" class="form-control" data-to></label>
  </span>
  <label>$text{'analytics_auto_refresh'} <select class="form-control" data-auto-refresh>
    <option value="0" selected>$text{'analytics_auto_off'}</option>
    <option value="600">$text{'analytics_auto_10m'}</option>
    <option value="1800">$text{'analytics_auto_30m'}</option>
  </select></label>
  <button class="btn btn-default" data-apply type="button">$text{'analytics_apply'}</button>
 </div>
 <p class="help-block" data-auto-custom-note hidden>$text{'analytics_auto_custom_note'}</p>
 <div data-error class="alert alert-warning" hidden></div>
  </div>
 </section>
 <section class="panel panel-default wg-analytics-section">
  <div class="panel-heading"><strong>$text{'analytics_summary_heading'}</strong></div>
  <div class="panel-body">
   <div class="wg-analytics-summary">
    <div class="wg-analytics-summary-item" data-rx></div>
    <div class="wg-analytics-summary-item" data-tx></div>
    <div class="wg-analytics-summary-item" data-last-handshake></div>
    <div class="wg-analytics-summary-item" data-handshake-ip></div>
   </div>
   <p class="help-block" data-db-size></p>
  </div>
 </section>
 <ul class="nav nav-tabs wg-analytics-subtabs" role="tablist" aria-label="$text{'analytics_title'}">
  <li class="active" role="presentation"><a href="#wg-analytics-chart-pane" role="tab" aria-controls="wg-analytics-chart-pane" aria-selected="true" data-wg-analytics-tab="graph">$text{'analytics_tab_graph'}</a></li>
  <li role="presentation"><a href="#wg-analytics-events-pane" role="tab" aria-controls="wg-analytics-events-pane" aria-selected="false" data-wg-analytics-tab="events">$text{'analytics_tab_events'}</a></li>
 </ul>
 <div id="wg-analytics-chart-pane" data-wg-analytics-pane="graph" role="tabpanel">
 <section class="panel panel-default wg-analytics-section">
  <div class="panel-heading"><strong>$text{'analytics_chart'}</strong></div>
  <div class="panel-body">
 <div class="wg-analytics-chart-legend">
   <span class="wg-analytics-dot wg-analytics-tx-dot"></span> $text{'analytics_graph_tx'}
   <span class="wg-analytics-dot wg-analytics-rx-dot"></span> $text{'analytics_graph_rx'}
   <small data-chart-scale></small>
 </div>
 <div class="wg-analytics-chart" data-chart role="img" aria-label="$text{'analytics_chart'}">
   <svg class="wg-traffic-canvas wg-analytics-svg" data-chart-svg width="100%" height="300" role="presentation"></svg>
 </div>
 <div data-notes class="wg-analytics-notes help-block"></div>
 <p class="help-block">$text{'analytics_bucket_note'}</p>
  </div>
 </section>
 </div>
 <div id="wg-analytics-events-pane" data-wg-analytics-pane="events" role="tabpanel" hidden>
 <section class="panel panel-default wg-analytics-section">
  <div class="panel-heading"><strong>$text{'analytics_events'}</strong></div>
  <div class="panel-body">
 <div class="table-responsive wg-analytics-table" data-wg-event-sort-table><table class="table table-striped table-hover">
 <thead><tr><th>$text{'analytics_event_time'}</th><th>$text{'analytics_peer'}</th><th>$text{'analytics_event_type'}</th><th>$text{'analytics_event_endpoint'}</th><th>$text{'analytics_event_previous'}</th></tr></thead>
 <tbody data-events></tbody></table></div>
 <p class="help-block">$text{'analytics_warning'}</p>
  </div>
 </section>
 </div>
</div>
<style>
/* Theme-native panels, form controls and responsive tables; only layout
   dimensions are local. No independent analytics color palette. */
.wg-analytics-subtabs{margin:14px 0 0}
.wg-analytics-subtabs>li>a{cursor:pointer}
.wg-analytics-section{margin:12px 0}
.wg-analytics-section>.panel-heading{padding:8px 10px}
.wg-analytics-section>.panel-body{padding:12px}
.wg-analytics-filters{display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end}
.wg-analytics-filters label{display:flex;flex-direction:column;gap:4px;margin:0}
.wg-analytics-filters select,.wg-analytics-filters input{min-width:150px;max-width:100%}
.wg-analytics-filters [data-peer]{min-width:260px}
.wg-analytics-filters [data-custom]{display:flex;flex-wrap:wrap;gap:10px}
.wg-analytics-filters [hidden],#wg-analytics [hidden]{display:none!important}
.wg-analytics-summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px}
.wg-analytics-summary-item{padding:9px 12px;border:1px solid rgba(127,127,127,.25);border-radius:3px}
.wg-analytics-summary-item:empty::after{content:'—'}
.wg-analytics-notes{margin-top:8px}
.wg-analytics-table{overflow:auto;max-height:420px}
.wg-analytics-table table{width:100%;margin:0}
.wg-analytics-table td,.wg-analytics-table th{vertical-align:middle}
.wg-analytics-peer-link{color:inherit;text-decoration:underline}
.wg-analytics-steps{display:flex;flex-wrap:wrap;gap:10px;align-items:flex-end}
.wg-analytics-steps form{display:flex;flex-wrap:wrap;align-items:flex-end;gap:8px;margin:4px 0}
.wg-analytics-steps label{display:flex;flex-direction:column;gap:4px;margin:0}
.wg-analytics-steps input,.wg-analytics-steps select{max-width:260px}
.wg-analytics-danger{border-color:rgba(190,50,40,.45)}
\@media(max-width:700px){.wg-analytics-filters label,.wg-analytics-filters [data-peer],
.wg-analytics-steps label{width:100%;min-width:0}}
.wg-analytics-chart{display:block;width:100%;min-height:300px}
.wg-analytics-svg{display:block;width:100%;height:300px;border:1px solid rgba(127,127,127,.25);
  border-radius:4px;overflow:hidden}
.wg-analytics-chart-legend,.wg-analytics-chart-axis{display:flex;align-items:center;gap:8px;margin:8px 0}
.wg-analytics-chart-legend small{margin-left:auto;opacity:.85}
.wg-analytics-chart-axis{justify-content:space-between;font-size:12px;opacity:.85}
.wg-analytics-dot{display:inline-block;width:10px;height:10px;border-radius:2px}
.wg-analytics-rx-dot{background-color:var(--success-color,#42a878)}
.wg-analytics-tx-dot{background-color:var(--primary-color,#4f8dd6)}
</style>
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
  function bytes(v) {
    if (!Number.isFinite(v)) return '—';
    const units=['B','KiB','MiB','GiB','TiB'];
    let i=0;
    while(v>=1024 && i<units.length-1){v/=1024;i++;}
    return (i===0 || v>=100 ? v.toFixed(0):v.toFixed(1))+' '+units[i];
  }
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
    const style=getComputedStyle(document.documentElement);
    const colors={
      tx:style.getPropertyValue('--primary-color').trim()||'#4f8dd6',
      rx:style.getPropertyValue('--success-color').trim()||'#42a878',
      grid:'rgba(127,127,127,.22)',zero:'rgba(190,190,190,.8)',
      text:style.color||'#aaa'
    };
    const width=Math.max(320,Math.round(chartSvg.clientWidth||graph.clientWidth||900));
    const height=300,pad={l:76,r:12,t:18,b:28};
    const pw=width-pad.l-pad.r,half=(height-pad.t-pad.b)/2,zero=pad.t+half;
    const max=Math.max(1024,...values.map(v=>Math.max(v.tx,v.rx)));
    const power=Math.pow(1024,Math.floor(Math.log(max)/Math.log(1024)));
    const scaled=Math.ceil(max/power),tickStep=scaled<=2?.5:scaled<=5?1:2;
    const limit=Math.max(power,Math.ceil(scaled/tickStep)*tickStep*power);
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

if ($access{'manage'}) {
    print '<section class="panel panel-default wg-analytics-section wg-analytics-danger wg-danger-zone">'.
          '<div class="panel-heading"><strong>'.html_escape($text{'danger_zone'}).
          ' — '.html_escape($text{'analytics_maintenance'}).'</strong></div>'.
          '<div class="panel-body"><p class="help-block">'.html_escape($text{'analytics_maintenance_help'}).
          '</p><div class="wg-analytics-steps">';
    for my $item (
        [ 'delete_before', 'analytics_delete_before' ],
        [ 'delete_peer', 'analytics_delete_peer' ],
        [ 'purge', 'analytics_purge' ],
        [ 'vacuum', 'analytics_vacuum' ]
    ) {
        my ($action, $key) = @$item;
        print ui_form_start('analytics_maintenance.cgi','post'), csrf_hidden();
        print ui_hidden('action',$action);
        if ($action eq 'delete_before') {
            print '<label>'.html_escape($text{'analytics_to'}).
                ' <input type="datetime-local" class="form-control" data-maintenance-before></label> ';
            print '<input type="hidden" name="before" data-maintenance-epoch>';
        }
        if ($action eq 'delete_peer') {
            print '<label>'.html_escape($text{'analytics_peer'}).
                ' <select name="peer_id" class="form-control" data-maintenance-peer></select></label> ';
        }
        if ($action ne 'vacuum') {
            print '<label>'.html_escape($text{'analytics_confirm'}).
                ' <input name="confirm" class="form-control" autocomplete="off" placeholder="DELETE" required></label> ';
        }
        my $button_class = $action eq 'vacuum' ? 'btn btn-default' : 'btn btn-danger';
        print '<button type="submit" class="'.$button_class.'">'.html_escape($text{$key}).'</button>';
        print '</form>';
    }
    print '</div></div></section>';
    print <<'SCRIPT';
<script>
(function(){
 const root=document.getElementById('wg-analytics');
 const peer=root.querySelector('[data-peer]');
 const chooser=document.querySelector('[data-maintenance-peer]');
 if(chooser){
  const sync=()=>{
   const chosen=chooser.value;
   chooser.replaceChildren();
   for(const src of peer.options)if(src.value){
    const opt=document.createElement('option');opt.value=src.value;
    opt.textContent=src.textContent;chooser.append(opt);
   }
   if(chosen)chooser.value=chosen;
  };
  new MutationObserver(sync).observe(peer,{childList:true});sync();
 }
 for(const form of document.querySelectorAll('form[action="analytics_maintenance.cgi"]')){
  form.addEventListener('submit',e=>{
   const date=form.querySelector('[data-maintenance-before]');
   if(date){
    const stamp=Math.floor(new Date(date.value).getTime()/1000);
    if(!Number.isFinite(stamp)||stamp<=0||stamp>Date.now()/1000){e.preventDefault();return;}
    form.querySelector('[data-maintenance-epoch]').value=String(stamp);
   }
   const action=form.querySelector('[name="action"]').value;
   if(action==='delete_peer' && !form.querySelector('[name="peer_id"]').value){e.preventDefault();return;}
   if(action!=='vacuum' && form.querySelector('[name="confirm"]').value!=='DELETE'){e.preventDefault();return;}
   if(!window.confirm('Proceed with analytics storage maintenance?'))e.preventDefault();
  });
 }
})();
</script>
SCRIPT
}

print ui_config_link('index_config');
ui_print_footer('index.cgi',$text{'index_title'});
