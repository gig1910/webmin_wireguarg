=head1 peer-usage-ui-lib.pl

Peer-specific historical consumption visualization. Interfaces retain their
original live graph, while peer graphs support explicit time filters.

=cut

sub peer_usage_graph_html
{
    my ($name, $peer, $title) = @_;
    my $id = 'wgpeerusage_'.substr(sha256_hex(join('|', $name, $peer, rand())), 0, 14);
    my $history_url = html_escape(module_script_url('history.cgi', name => $name, peer => $peer));
    my $safe_title = html_escape($title || $text{'graph_title'});
    my $interval = int($config{'stats_refresh_interval'} || 5);
    $interval = 2 if ($interval < 2);
    $interval = 3600 if ($interval > 3600);
    my %labels = map { $_ => ($text{$_} || $_) } qw(
        peer_usage_received peer_usage_sent peer_usage_sampled
        peer_usage_insufficient peer_usage_partial peer_usage_resets
        peer_usage_gaps peer_usage_truncated peer_usage_retention
        peer_usage_loading peer_usage_empty peer_usage_invalid
    );
    my $strings = json_encode_utf8(\%labels);
    my $js_interface = json_encode_utf8($name);
    my $js_peer = json_encode_utf8($peer);
    my $lbl_period = html_escape($text{'peer_usage_period'});
    my $lbl_from = html_escape($text{'peer_usage_from'});
    my $lbl_to = html_escape($text{'peer_usage_to'});
    my $lbl_apply = html_escape($text{'peer_usage_apply'});
    my $lbl_15m = html_escape($text{'peer_usage_15m'});
    my $lbl_1h = html_escape($text{'peer_usage_1h'});
    my $lbl_6h = html_escape($text{'peer_usage_6h'});
    my $lbl_24h = html_escape($text{'peer_usage_24h'});
    my $lbl_custom = html_escape($text{'peer_usage_custom'});
    my $loading = html_escape($text{'peer_usage_loading'});
    my $received = html_escape($text{'peer_usage_received'});
    my $sent = html_escape($text{'peer_usage_sent'});
    my $chart_primitives=wg_chart_ui_script();
    my $transport=wg_ui_transport_script();
    return <<HTML;
$transport
$chart_primitives
<div class="wg-peer-usage" id="$id" data-history-url="$history_url" data-poll-interval="$interval">
 <h3>$safe_title</h3>
 <div class="wg-peer-usage-toolbar">
  <label>$lbl_period <select data-wg-period>
    <option value="900">$lbl_15m</option><option value="3600">$lbl_1h</option>
    <option value="21600">$lbl_6h</option><option value="86400">$lbl_24h</option>
    <option value="custom">$lbl_custom</option>
  </select></label>
  <div class="wg-peer-usage-custom" data-wg-custom hidden>
   <label>$lbl_from <input data-wg-from type="datetime-local"></label>
   <label>$lbl_to <input data-wg-to type="datetime-local"></label>
   <button type="button" data-wg-apply class="btn btn-default">$lbl_apply</button>
  </div>
 </div>
 <div class="wg-peer-usage-summary">
  <strong data-wg-rx>$received: —</strong>
  <strong data-wg-tx>$sent: —</strong>
  <small data-wg-covered></small>
 </div>
 <canvas class="wg-peer-usage-canvas" height="300" style="width:100%;height:300px"></canvas>
 <div data-wg-warning class="wg-peer-usage-warning" role="status"></div>
 <div data-wg-error class="wg-traffic-error" role="alert" hidden></div>
 <small class="wg-peer-usage-hint">$loading</small>
</div>
<style>
.wg-peer-usage{margin:18px 0}
.wg-peer-usage-toolbar,.wg-peer-usage-custom,.wg-peer-usage-summary{display:flex;flex-wrap:wrap;gap:12px;align-items:center;margin:10px 0}
.wg-peer-usage-toolbar label,.wg-peer-usage-custom label{display:flex;gap:6px;align-items:center}
.wg-peer-usage-custom[hidden],.wg-peer-usage [hidden]{display:none!important}
.wg-peer-usage-summary strong{font-weight:600}
.wg-peer-usage-summary small{width:100%;opacity:.85}
.wg-peer-usage-canvas{display:block;border:1px solid rgba(127,127,127,.25);border-radius:4px}
.wg-peer-usage-warning{color:#bd7800;margin:7px 0;line-height:1.6}
.wg-peer-usage-hint{opacity:.8}
</style>
<script>
(function() {
  'use strict';
  const root = document.getElementById('$id');
  if (!root) return;
  const interfaceName = $js_interface;
  const peerKey = $js_peer;
  const labels = $strings;
  const period = root.querySelector('[data-wg-period]');
  const custom = root.querySelector('[data-wg-custom]');
  const inputFrom = root.querySelector('[data-wg-from]');
  const inputTo = root.querySelector('[data-wg-to]');
  const warning = root.querySelector('[data-wg-warning]');
  const error = root.querySelector('[data-wg-error]');
  const canvas = root.querySelector('canvas');
  const ctx = canvas.getContext('2d');
  const minimumRefreshMs = Math.max(30000, Number(root.dataset.pollInterval) * 1000);
  const maxRange = 90 * 86400;
  let rows = [], bounds = null, requestSerial = 0, aborter = null;
  let previousRefresh = 0, disposed = false;

  function bytes(v, rate) {
    return window.WireGuardChart.formatBytes(v,rate);
  }
  function displayTime(epoch) {
    return new Date(epoch * 1000).toLocaleString();
  }
  function toLocalInput(date) {
    const pad = value => String(value).padStart(2, '0');
    return date.getFullYear() + '-' + pad(date.getMonth()+1) + '-' + pad(date.getDate()) +
      'T' + pad(date.getHours()) + ':' + pad(date.getMinutes());
  }
  function selectedRange() {
    if (period.value === 'custom') {
      const start = new Date(inputFrom.value).getTime() / 1000;
      const finish = new Date(inputTo.value).getTime() / 1000;
      if (!Number.isFinite(start) || !Number.isFinite(finish) ||
          !inputFrom.value || !inputTo.value ||
          start <= 0 || start >= finish || finish > Date.now()/1000 + 60 ||
          finish-start > maxRange) return null;
      return {from:Math.floor(start),to:Math.floor(finish)};
    }
    const seconds = Number(period.value);
    const now = Math.floor(Date.now()/1000);
    return {from: now-seconds, to: now};
  }
  function observedRates() {
    const results = [];
    for (let i = 1; i < rows.length; i++) {
      const before = rows[i-1], after = rows[i], elapsed = after.timestamp-before.timestamp;
      if (elapsed <= 0) continue;
      results.push({
        timestamp:after.timestamp,
        rx:after.rx >= before.rx ? (after.rx-before.rx)/elapsed : null,
        tx:after.tx >= before.tx ? (after.tx-before.tx)/elapsed : null
      });
    }
    return results;
  }
  function draw() {
    if (!ctx || !bounds) return;
    const dpr = window.devicePixelRatio || 1;
    const w = Math.max(300, canvas.clientWidth || 300), h = 300;
    if (canvas.width !== Math.round(w*dpr) || canvas.height !== Math.round(h*dpr)) {
      canvas.width = Math.round(w*dpr);
      canvas.height = Math.round(h*dpr);
    }
    ctx.setTransform(dpr,0,0,dpr,0,0);
    ctx.clearRect(0,0,w,h);
    const pad={left:70,right:14,top:22,bottom:42};
    const width=w-pad.left-pad.right, half=(h-pad.top-pad.bottom)/2;
    const center=pad.top+half;
    const rates=observedRates();
    let maxRate=1024;
    for (const v of rates) maxRate=Math.max(maxRate,v.rx || 0,v.tx || 0);
    const scale=window.WireGuardChart.niceLimit(maxRate);
    const colors=window.WireGuardChart.themeColors();
    const txColor=colors.tx,rxColor=colors.rx,ink=colors.text;
    ctx.font='12px sans-serif';ctx.lineWidth=1;
    ctx.strokeStyle='rgba(127,127,127,.23)';ctx.fillStyle=ink;
    for(let i=0;i<=4;i++){
      const yTop=center-half*i/4, yBottom=center+half*i/4;
      for(const y of i ? [yTop,yBottom] : [center]){
        ctx.beginPath();ctx.moveTo(pad.left,y);ctx.lineTo(w-pad.right,y);ctx.stroke();
      }
      const label=bytes(scale*i/4,true);
      ctx.textAlign='right';ctx.textBaseline='middle';
      ctx.fillText(label,pad.left-6,yTop);
      if(i)ctx.fillText(label,pad.left-6,yBottom);
    }
    function drawLine(field,color,sign) {
      ctx.strokeStyle=color;ctx.lineWidth=2;ctx.beginPath();
      let started=false;
      for(const point of rates){
        const value=point[field];
        if(value===null){started=false;continue;}
        const x=pad.left+width*Math.max(0,Math.min(1,(point.timestamp-bounds.from)/(bounds.to-bounds.from)));
        const y=center+sign*half*Math.min(1,value/scale);
        if (!started){ctx.moveTo(x,y);started=true;} else ctx.lineTo(x,y);
      }
      ctx.stroke();
    }
    drawLine('tx',txColor,-1);drawLine('rx',rxColor,1);
    ctx.fillStyle=txColor;ctx.textAlign='left';ctx.fillText('TX',pad.left+4,pad.top+6);
    ctx.fillStyle=rxColor;ctx.fillText('RX',pad.left+4,h-pad.bottom-7);
    ctx.fillStyle=ink;ctx.textBaseline='alphabetic';
    ctx.textAlign='left';ctx.fillText(displayTime(bounds.from),pad.left,h-8);
    ctx.textAlign='right';ctx.fillText(displayTime(bounds.to),w-pad.right,h-8);
  }
  function present(data) {
    rows = (data.history || []).filter(p => p && Number.isFinite(Number(p.timestamp)) &&
        Number.isFinite(Number(p.rx)) && Number.isFinite(Number(p.tx)) &&
        Number(p.timestamp) >= bounds.from && Number(p.timestamp) <= bounds.to
    ).map(p => ({timestamp:Number(p.timestamp),rx:Number(p.rx),tx:Number(p.tx)}))
     .sort((a,b) => a.timestamp-b.timestamp);
    const usage=data.usage || {};
    root.querySelector('[data-wg-rx]').textContent=labels.peer_usage_received+': '+
      (usage.intervals ? bytes(Number(usage.rx),false) : '—');
    root.querySelector('[data-wg-tx]').textContent=labels.peer_usage_sent+': '+
      (usage.intervals ? bytes(Number(usage.tx),false) : '—');
    root.querySelector('[data-wg-covered]').textContent=usage.first && usage.last ?
      labels.peer_usage_sampled+': '+displayTime(usage.first)+' — '+displayTime(usage.last) : '';
    const notices=[];
    if (rows.length===0) notices.push(labels.peer_usage_empty);
    else if (!usage.intervals) notices.push(labels.peer_usage_insufficient);
    else if ((usage.first > bounds.from + 2 * Number(root.dataset.pollInterval)) ||
             (usage.last < bounds.to - 2 * Number(root.dataset.pollInterval)))
      notices.push(labels.peer_usage_partial);
    if (usage.resets) notices.push(labels.peer_usage_resets);
    if (usage.gaps) notices.push(labels.peer_usage_gaps);
    if (data.truncated) notices.push(labels.peer_usage_truncated);
    if (data.retention && bounds.from < data.timestamp-data.retention)
      notices.push(labels.peer_usage_retention);
    warning.textContent=notices.join(' ');
    const hint=root.querySelector('.wg-peer-usage-hint');
    hint.textContent=labels.peer_usage_retention;
    draw();
  }
  async function fetchPeriod() {
    const range=selectedRange();
    if (!range) { error.textContent=labels.peer_usage_invalid;error.hidden=false;return; }
    bounds=range;
    const serial=++requestSerial;
    if (aborter) aborter.abort();
    const controller=new AbortController();
    aborter=controller;
    const url=new URL(root.dataset.historyUrl,window.location.href);
    url.searchParams.set('from',String(range.from));
    url.searchParams.set('to',String(range.to));
    error.hidden=true;
    try {
      const data=await window.WireGuardTransport.requestJson(
        url.toString(),{signal:controller.signal},{requireOk:true});
      if(disposed || serial!==requestSerial || !root.isConnected)return;
      previousRefresh=Date.now();
      present(data);
    } catch(ex) {
      if(disposed || serial!==requestSerial || controller.signal.aborted)return;
      error.textContent=ex.message || String(ex);
      error.hidden=false;
    } finally {
      if(aborter===controller) aborter=null;
    }
  }
  function onChange() {
    custom.hidden=period.value!=='custom';
    if(period.value==='custom'){
      const now=new Date();
      inputTo.value=toLocalInput(now);
      inputFrom.value=toLocalInput(new Date(now.getTime()-3600000));
    } else fetchPeriod();
  }
  function onRuntime(event) {
    if(disposed || !root.isConnected){cleanup();return;}
    if(period.value==='custom' || aborter || Date.now()-previousRefresh<minimumRefreshMs)return;
    const data=event.detail || {};
    const iface=data.interfaces && data.interfaces[interfaceName];
    if(iface && iface.active && (iface.peers||[]).some(p => p.public_key===peerKey)) fetchPeriod();
  }
  function onResize(){draw();}
  function cleanup(){
    if(disposed)return;
    disposed=true;
    requestSerial++;
    if(aborter)aborter.abort();
    document.removeEventListener('wg-runtime',onRuntime);
    window.removeEventListener('resize',onResize);
    window.removeEventListener('pagehide',cleanup);
  }
  period.addEventListener('change',onChange);
  root.querySelector('[data-wg-apply]').addEventListener('click',fetchPeriod);
  document.addEventListener('wg-runtime',onRuntime);
  window.addEventListener('resize',onResize);
  window.addEventListener('pagehide',cleanup,{once:true});
  fetchPeriod();
})();
</script>
HTML
}

1;
