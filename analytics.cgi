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
);
my $strings = json_encode_utf8(\%labels);
print <<HTML;
<div id="wg-analytics" data-url="$url">
 <div class="wg-analytics-filters">
  <label>$text{'analytics_peer'} <select data-peer></select></label>
  <label>$text{'analytics_period'} <select data-period>
   <option value="86400">$text{'analytics_24h'}</option>
   <option value="604800">$text{'analytics_7d'}</option>
   <option value="2592000">$text{'analytics_30d'}</option>
   <option value="custom">$text{'analytics_custom'}</option>
  </select></label>
  <span data-custom hidden>
   <label>$text{'analytics_from'} <input type="datetime-local" data-from></label>
   <label>$text{'analytics_to'} <input type="datetime-local" data-to></label>
  </span>
  <button class="btn btn-default" data-apply type="button">$text{'analytics_apply'}</button>
 </div>
 <div data-error class="alert alert-warning" hidden></div>
 <div class="wg-analytics-totals"><strong data-rx></strong><strong data-tx></strong><small data-db-size></small></div>
 <div class="wg-analytics-totals"><strong data-last-handshake></strong><strong data-handshake-ip></strong></div>
 <h3>$text{'analytics_chart'}</h3>
 <div class="wg-analytics-chart-legend">
   <span class="wg-analytics-dot wg-analytics-rx-dot"></span> $text{'analytics_graph_rx'}
   <span class="wg-analytics-dot wg-analytics-tx-dot"></span> $text{'analytics_graph_tx'}
   <small data-chart-scale></small>
 </div>
 <div class="wg-analytics-chart" data-chart role="img" aria-label="$text{'analytics_chart'}">
   <div class="wg-analytics-chart-bars" data-chart-bars></div>
 </div>
 <div class="wg-analytics-chart-axis"><span data-chart-from></span><span data-chart-to></span></div>
 <div data-notes class="wg-analytics-notes"></div>
 <p><small>$text{'analytics_bucket_note'}</small></p>
 <h3>$text{'analytics_events'}</h3>
 <div class="wg-analytics-table"><table class="table table-striped">
 <thead><tr><th>$text{'analytics_event_time'}</th><th>$text{'analytics_peer'}</th><th>$text{'analytics_event_type'}</th><th>$text{'analytics_event_endpoint'}</th><th>$text{'analytics_event_previous'}</th></tr></thead>
 <tbody data-events></tbody></table></div>
 <p><small>$text{'analytics_warning'}</small></p>
</div>
<style>
.wg-analytics-filters,.wg-analytics-totals{display:flex;gap:12px;flex-wrap:wrap;align-items:center;margin:12px 0}
.wg-analytics-filters label{display:inline-flex;gap:6px;align-items:center}
.wg-analytics-filters [hidden],#wg-analytics [hidden]{display:none!important}
.wg-analytics-totals strong{padding:5px 8px;border:1px solid #8885;border-radius:4px}
.wg-analytics-notes{margin-top:8px;opacity:.9}
.wg-analytics-table{overflow:auto;max-height:420px}
.wg-analytics-table table{width:100%}
.wg-analytics-chart{display:block!important;width:100%;height:286px;min-height:286px;overflow:hidden;
  padding:8px 10px 4px;border:1px solid rgba(127,127,127,.45);border-radius:4px}
.wg-analytics-chart-bars{display:flex!important;align-items:stretch;height:264px;min-height:264px;
  gap:1px;background:repeating-linear-gradient(to top,transparent 0,transparent calc(25% - 1px),
  rgba(127,127,127,.23) calc(25% - 1px),rgba(127,127,127,.23) 25%)}
.wg-analytics-bar-group{flex:1 1 0;min-width:0;display:flex;align-items:flex-end;gap:1px;height:100%}
.wg-analytics-bar{display:block;flex:1 1 0;min-width:0;max-height:100%;border-radius:1px 1px 0 0}
.wg-analytics-bar.rx{background-color:#3989d7}
.wg-analytics-bar.tx{background-color:#2aa889}
.wg-analytics-chart-empty{margin:auto;align-self:center;text-align:center;opacity:.8}
.wg-analytics-chart-legend,.wg-analytics-chart-axis{display:flex;align-items:center;gap:8px;margin:8px 0}
.wg-analytics-chart-legend small{margin-left:auto;opacity:.85}
.wg-analytics-chart-axis{justify-content:space-between;font-size:12px;opacity:.85}
.wg-analytics-dot{display:inline-block;width:10px;height:10px;border-radius:2px}
.wg-analytics-rx-dot{background-color:#3989d7}
.wg-analytics-tx-dot{background-color:#2aa889}
</style>
<script>
(function(){
  'use strict';
  const root=document.getElementById('wg-analytics');
  if (!root)return;
  const labels=$strings, initial=$selected_json;
  const peer=root.querySelector('[data-peer]'), period=root.querySelector('[data-period]');
  const custom=root.querySelector('[data-custom]'), start=root.querySelector('[data-from]');
  const end=root.querySelector('[data-to]'), output=root.querySelector('[data-error]');
  const graph=root.querySelector('[data-chart]'), graphBars=root.querySelector('[data-chart-bars]');
  let data=null, seq=0, controller=null;
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
    }else from=to-Number(period.value);
    if(!Number.isFinite(from) || !Number.isFinite(to) ||
       from<=0 || from>=to || to>Date.now()/1000+60 ||
       to-from>366*86400)throw new Error('Invalid date interval');
    return {from,to};
  }
  function peerLabel(p){
    const key=(p.public_key||'').slice(0,12)+'…';
    const name=(p.name||'').trim();
    return (name||key)+' ('+(p.interface||'—')+' · '+key+')';
  }
  function draw() {
    if(!data||!graphBars)return;
    const raw=data.buckets||[];
    const first=Math.floor(data.from/600)*600;
    const last=data.to;
    const span=Math.max(600,last-first);
    // Visualization may downsample, but SQLite always stores 10-minute buckets.
    const step=Math.max(600,Math.ceil(span/(180*600))*600);
    const slots=Math.max(1,Math.ceil(span/step));
    const totals=Array.from({length:slots},()=>({rx:0,tx:0}));
    for(const b of raw){
      const slot=Math.floor((Number(b.period)-first)/step);
      if(slot<0||slot>=slots)continue;
      // Sum same-timestamp samples for all peers, rather than overplotting.
      totals[slot].rx+=Math.max(0,Number(b.rx)||0);
      totals[slot].tx+=Math.max(0,Number(b.tx)||0);
    }
    graphBars.replaceChildren();
    const maximum=Math.max(1,...totals.map(s=>Math.max(s.rx,s.tx)));
    if(!raw.length){
      const empty=document.createElement('div');
      empty.className='wg-analytics-chart-empty';
      empty.textContent=labels.analytics_graph_empty;
      graphBars.append(empty);
    }else{
      const fragment=document.createDocumentFragment();
      for(let i=0;i<slots;i++){
        const item=totals[i];
        const group=document.createElement('div');
        group.className='wg-analytics-bar-group';
        const intervalStart=first+i*step, intervalEnd=Math.min(last,intervalStart+step);
        group.title=new Date(intervalStart*1000).toLocaleString()+' — '+
           new Date(intervalEnd*1000).toLocaleString()+'\n'+
           labels.analytics_graph_rx+': '+bytes(item.rx)+'\n'+
           labels.analytics_graph_tx+': '+bytes(item.tx);
        for(const [kind,value] of [['rx',item.rx],['tx',item.tx]]){
          const bar=document.createElement('span');
          bar.className='wg-analytics-bar '+kind;
          bar.style.height=value>0?Math.max(0.5,100*value/maximum)+'%':'0%';
          group.append(bar);
        }
        fragment.append(group);
      }
      graphBars.append(fragment);
    }
    root.querySelector('[data-chart-scale]').textContent=
       labels.analytics_graph_scale+': '+bytes(maximum);
    root.querySelector('[data-chart-from]').textContent=new Date(data.from*1000).toLocaleString();
    root.querySelector('[data-chart-to]').textContent=new Date(data.to*1000).toLocaleString();
    graph.setAttribute('aria-label',labels.analytics_chart+'; '+
        labels.analytics_graph_rx+': '+bytes(Number(data.totals.rx))+'; '+
        labels.analytics_graph_tx+': '+bytes(Number(data.totals.tx)));
  }
  function render(result) {
    const previous=peer.value;
    const options=[{id:'',public_key:labels.analytics_all_peers},...(result.peers||[])];
    peer.replaceChildren();
    for(const p of options) {
      const opt=document.createElement('option');
      opt.value=p.id;
      opt.textContent=p.id ? peerLabel(p)+
           (p.active?' • '+labels.analytics_peer_active:' • '+labels.analytics_peer_inactive) :
           labels.analytics_all_peers;
      if(p.id)opt.title='PublicKey: '+p.public_key+'\nSHA256: '+p.id;
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
      for(const cell of columns){
        const td=document.createElement('td');td.textContent=cell;row.append(td);
      }
      body.append(row);
    }
    draw();
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
    }
  }
  period.addEventListener('change',()=>{custom.hidden=period.value!=='custom';if(!custom.hidden){
    end.value=localInput(Date.now());start.value=localInput(Date.now()-86400000);
  }else refresh()});
  peer.addEventListener('change',refresh);
  root.querySelector('[data-apply]').addEventListener('click',refresh);
  // The HTML bar chart scales to the available width without Canvas.
  window.addEventListener('pagehide',()=>{if(controller)controller.abort();});
  const originalOption=document.createElement('option');originalOption.value=initial;
  originalOption.textContent=labels.analytics_loading;peer.append(originalOption);
  refresh().then(()=>{if(initial && peer.querySelector('option[value="'+initial+'"]')){peer.value=initial;refresh();}});
})();
</script>
HTML

if ($access{'manage'}) {
    print '<hr><h3>'.html_escape($text{'analytics_maintenance'}).'</h3>';
    print '<p>'.html_escape($text{'analytics_maintenance_help'}).'</p>';
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
                ' <input type="datetime-local" data-maintenance-before></label> ';
            print '<input type="hidden" name="before" data-maintenance-epoch>';
        }
        if ($action eq 'delete_peer') {
            print '<label>'.html_escape($text{'analytics_peer'}).
                ' <select name="peer_id" data-maintenance-peer></select></label> ';
        }
        if ($action ne 'vacuum') {
            print '<label>'.html_escape($text{'analytics_confirm'}).
                ' <input name="confirm" autocomplete="off" placeholder="DELETE" required></label> ';
        }
        print '<button type="submit" class="btn btn-default">'.html_escape($text{$key}).'</button>';
        print '</form>';
    }
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
