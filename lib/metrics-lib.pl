=head1 metrics-lib.pl

Internal module.

=cut

sub stats_dir { return $config{'stats_dir'} || '/var/webmin/wireguard/stats'; }
sub runtime_snapshot_path
{
    return File::Spec->catfile(stats_dir(), 'runtime.json');
}

sub read_runtime_snapshot
{
    my $path = runtime_snapshot_path();
    return (undef, $text{'runtime_cache_missing'}) if (!-r $path);
    sysopen(my $fh, $path, O_RDONLY) || return (undef, "$!");
    binmode($fh);
    flock($fh, LOCK_SH | LOCK_NB);
    local $/;
    my $raw = <$fh>;
    close($fh);
    return (undef, $text{'runtime_cache_missing'}) if (!defined($raw) || !length($raw));
    my $snapshot = eval { decode_json($raw) };
    return (undef, $text{'runtime_cache_invalid'}) if (!$snapshot || ref($snapshot) ne 'HASH');
    return ($snapshot, undef);
}

sub write_runtime_snapshot
{
    my ($snapshot) = @_;
    return (0, $text{'runtime_cache_invalid'}) if (!$snapshot || ref($snapshot) ne 'HASH');
    my $dir = stats_dir();
    eval { make_path($dir, { mode => 0700 }) if (!-d $dir); };
    return (0, $@ || "$!") if ($@ || !-d $dir);
    chmod(0700, $dir);
    my $encoded = eval { json_encode_utf8($snapshot) };
    return (0, $@ || $text{'runtime_cache_invalid'}) if (!defined($encoded) || $@);
    return _write_exact_unlocked(runtime_snapshot_path(), $encoded);
}

sub refresh_runtime_snapshot
{
    my ($max_age) = @_;
    $max_age = int($max_age || 0);
    my ($snapshot, $read_error) = read_runtime_snapshot();
    if ($snapshot && $max_age > 0) {
        my $age = time() - int($snapshot->{'timestamp'} || 0);
        return ($snapshot, undef, 0) if ($age >= 0 && $age <= $max_age);
    }

    my $dir = stats_dir();
    eval { make_path($dir, { mode => 0700 }) if (!-d $dir); };
    return ($snapshot, $read_error || $@ || "$!", 0) if ($@ || !-d $dir);
    chmod(0700, $dir);

    # Multiple Webmin pages can request runtime data at once. Only one request
    # may execute the fallback wg command; other requests use an existing stale
    # snapshot or retry on their next polling interval.
    my $lock_path = File::Spec->catfile($dir, '.runtime-refresh.lock');
    sysopen(my $lock, $lock_path, O_RDWR | O_CREAT, 0600) || return ($snapshot, "$!", 0);
    if (!flock($lock, LOCK_EX | LOCK_NB)) {
        close($lock);
        return ($snapshot, $read_error || $text{'runtime_cache_missing'}, 0);
    }

    # Another process may have refreshed the file immediately before this lock
    # was acquired.
    my ($newer) = read_runtime_snapshot();
    if ($newer && $max_age > 0) {
        my $age = time() - int($newer->{'timestamp'} || 0);
        if ($age >= 0 && $age <= $max_age) {
            close($lock);
            return ($newer, undef, 0);
        }
    }

    my ($interfaces, $runtime_error) = get_all_runtime_dump();
    if ($runtime_error) {
        close($lock);
        return ($snapshot, $runtime_error, 0);
    }

    my $fresh = {
        'timestamp' => time(),
        'interfaces' => $interfaces || {},
    };
    my ($write_ok, $write_error) = write_runtime_snapshot($fresh);
    close($lock);
    return ($fresh, $write_ok ? undef : $write_error, 1);
}

sub get_cached_interface_dump
{
    my ($name) = @_;
    my ($snapshot, $error) = read_runtime_snapshot();
    return ({}, $error) if (!$snapshot);
    my $runtime = $snapshot->{'interfaces'}->{$name};
    return ($runtime || {}, undef, $snapshot);
}

sub stats_history_path
{
    my ($name,$peer)=@_; my $id=length($peer||'')?'peer-'.sha256_hex($peer):'interface';
    return File::Spec->catfile(stats_dir(),$name.'-'.$id.'.jsonl');
}
sub read_stats_history
{
    my ($name, $peer, $since, $limit) = @_;
    my $path = stats_history_path($name, $peer);
    return [] if (!-r $path);
    $limit ||= 5000;

    sysopen(my $fh, $path, O_RDONLY) || return [];
    binmode($fh);
    flock($fh, LOCK_SH | LOCK_NB);
    seek($fh, 0, SEEK_END);
    my $position = tell($fh);
    my $buffer = '';
    my @reversed;
    my $done = 0;
    my $chunk_size = 65536;

    while ($position > 0 && @reversed < $limit && !$done) {
        my $read_size = $position < $chunk_size ? $position : $chunk_size;
        $position -= $read_size;
        seek($fh, $position, SEEK_SET) || last;
        my $chunk = '';
        my $got = read($fh, $chunk, $read_size);
        last if (!defined($got) || !$got);
        $buffer = $chunk.$buffer;
        my @lines = split(/\n/, $buffer, -1);
        $buffer = shift(@lines);
        while (@lines && @reversed < $limit) {
            my $line = pop(@lines);
            next if (!length($line));
            my $data = eval { decode_json($line) };
            next if (!$data);
            my $timestamp = $data->{'timestamp'} || 0;
            if ($timestamp < $since) { $done = 1; last; }
            push(@reversed, $data);
        }
    }
    if (!$done && length($buffer) && @reversed < $limit) {
        my $data = eval { decode_json($buffer) };
        push(@reversed, $data) if ($data && ($data->{'timestamp'} || 0) >= $since);
    }
    close($fh);
    return [ reverse(@reversed) ];
}

sub runtime_poll_html
{
    my ($name, $force_first) = @_;
    my $force_first_js = $force_first ? 'true' : 'false';
    my $interval = int($config{'stats_refresh_interval'} || 5);
    $interval = 2 if ($interval < 2);
    $interval = 3600 if ($interval > 3600);
    my $id = 'wgruntime_'.substr(sha256_hex(($name||'all').'|'.rand()),0,12);
    my %params;
    $params{'name'} = $name if (length($name || ''));
    my $url = module_script_url('runtime.cgi', %params);
    my $safe_url = html_escape($url);
    return <<HTML;
<div id="$id" data-wg-runtime-source="$safe_url" data-wg-runtime-interval="$interval" hidden></div>
<script>(function(){
 const API_BUILD='1.0.0';
 const root=document.getElementById('$id');if(!root)return;
 const url=root.dataset.wgRuntimeSource,interval=Math.max(2,Number(root.dataset.wgRuntimeInterval)||5)*1000,forceFirst=$force_first_js;
 window.__wgRuntimePollers=window.__wgRuntimePollers||{};
 if(window.__wgWireGuardApiBuild&&window.__wgWireGuardApiBuild!==API_BUILD){
  Object.values(window.__wgRuntimePollers).forEach(function(p){if(p&&typeof p.cleanup==='function')p.cleanup();});
  window.__wgRuntimePollers={};
 }
 window.__wgWireGuardApiBuild=API_BUILD;
 const previous=window.__wgRuntimePollers[url];
 if(previous&&typeof previous.cleanup==='function')previous.cleanup();
 const state={busy:false,timer:null,controller:null,tick:null,refresh:null,forcePending:false,refreshWaiters:[],root:root,stopped:false};
 window.__wgRuntimePollers[url]=state;
 function cleanup(){
  state.stopped=true;
  if(state.timer){clearInterval(state.timer);state.timer=null;}
  if(state.controller){state.controller.abort();state.controller=null;}
  state.busy=false;state.forcePending=false;
  state.refreshWaiters.splice(0).forEach(function(resolve){resolve(false);});
  if(window.__wgRuntimePollers&&window.__wgRuntimePollers[url]===state)delete window.__wgRuntimePollers[url];
 }
 state.cleanup=cleanup;
 function hostPageVisible(){
  if(!root.isConnected||document.hidden)return false;
  let node=root.parentElement;
  while(node&&node!==document.documentElement){
   const style=window.getComputedStyle(node);
   if(style.display==='none'||style.visibility==='hidden')return false;
   node=node.parentElement;
  }
  return true;
 }
 async function decodeJson(response){
  const body=await response.text();
  const contentType=(response.headers.get('content-type')||'').toLowerCase();
  if(!contentType.includes('application/json')){
   const sample=body.replace(/\s+/g,' ').trim().slice(0,240);
   const error=new Error('HTTP '+response.status+': сервер вернул не JSON ('+(contentType||'без Content-Type')+')'+(sample?': '+sample:''));
   error.nonJson=true;
   throw error;
  }
  try{return JSON.parse(body);}catch(parseError){
   const sample=body.replace(/\s+/g,' ').trim().slice(0,240);
   const error=new Error('Некорректный JSON-ответ'+(sample?': '+sample:''));
   error.nonJson=true;
   throw error;
  }
 }
 async function tick(force){
  if(state.stopped)return false;
  if(!root.isConnected){cleanup();return false;}
  if(!hostPageVisible())return false;
  if(state.busy){if(force)state.forcePending=true;return false;}
  state.busy=true;
  let succeeded=false;
  const controller=new AbortController();state.controller=controller;
  const timeout=setTimeout(function(){controller.abort();},Math.min(Math.max(interval,3000),10000));
  try{
   const requestUrl=force?url+(url.includes('?')?'&':'?')+'refresh=1&_wg_now='+Date.now():url;
   const response=await fetch(requestUrl,{cache:'no-store',credentials:'same-origin',redirect:'error',headers:{'Accept':'application/json','X-Requested-With':'XMLHttpRequest'},signal:controller.signal});
   const data=await decodeJson(response);
   if(!data.ok)throw new Error(data.error||('HTTP '+response.status));
   succeeded=true;
   if(root.isConnected)document.dispatchEvent(new CustomEvent('wg-runtime',{detail:data}));
   if(data.warning&&root.isConnected)document.dispatchEvent(new CustomEvent('wg-runtime-warning',{detail:{url:url,warning:data.warning}}));
  }catch(error){
   if(error.name!=='AbortError'&&root.isConnected){
    document.dispatchEvent(new CustomEvent('wg-runtime-error',{detail:{url:url,error:error.message||String(error)}}));
    // A HTML/404 response will not heal by polling every few seconds and can
    // overload MiniServ via authentic-theme/404.cgi. Stop until page reload.
    if(error.nonJson)cleanup();
   }
  }finally{
   clearTimeout(timeout);
   if(state.controller===controller)state.controller=null;
   state.busy=false;
   const forceAgain=state.forcePending;
   state.forcePending=false;
   if(force){state.refreshWaiters.splice(0).forEach(function(resolve){resolve(succeeded);});}
   if(forceAgain&&!state.stopped)setTimeout(function(){tick(true);},0);
  }
  return succeeded;
 }
 state.tick=function(){return tick(false);};
 state.refresh=function(){
  return new Promise(function(resolve){
   state.refreshWaiters.push(resolve);
   if(state.busy){state.forcePending=true;return;}
   tick(true);
  });
 };
 const visibilityHandler=function(){if(hostPageVisible())tick(false);};
 document.addEventListener('visibilitychange',visibilityHandler);
 const originalCleanup=cleanup;
 state.cleanup=function(){document.removeEventListener('visibilitychange',visibilityHandler);originalCleanup();};
 window.addEventListener('pagehide',state.cleanup,{once:true});
 setTimeout(function(){tick(forceFirst);},0);state.timer=setInterval(function(){tick(false);},interval);
})();</script>
HTML
}

sub graph_html
{
    my ($name,$peer_key,$title)=@_; return '' if (($config{'stats_enabled'}||'1') eq'0');
    my $window=int($config{'stats_live_window'}||900);$window=60if$window<60;$window=86400if$window>86400;
    my$id='wgchart_'.substr(sha256_hex(($name||'').'|'.($peer_key||'').'|'.rand()),0,12);
    my %history_params = (name => $name); $history_params{'peer'} = $peer_key if length($peer_key||''); my$history_url=html_escape(module_script_url('history.cgi', %history_params));
    my$safe=html_escape($title||$text{'graph_title'}); my$updated=html_escape($text{'runtime_updated'}); my$tx_total=html_escape($text{'graph_tx_total'});my$rx_total=html_escape($text{'graph_rx_total'});
    my$inactive=html_escape($text{'status_not_running'});my$loading=html_escape($text{'runtime_loading'});
    my$js_name=json_encode_utf8($name||'');my$js_peer=json_encode_utf8($peer_key||'');
    return <<HTML;
<div class="wg-traffic" id="$id" data-history-url="$history_url" data-window="$window">
 <h3>$safe</h3><canvas class="wg-traffic-canvas" height="300" style="width:100%;height:300px"></canvas>
 <div class="wg-traffic-values"><span class="wg-tx-now">↑ TX: —</span>&nbsp;&nbsp;&nbsp;<span class="wg-rx-now">↓ RX: —</span><br><span class="wg-tx-total">$tx_total: —</span>&nbsp;&nbsp;&nbsp;<span class="wg-rx-total">$rx_total: —</span><br><small>$updated: <span class="wg-updated">$loading</span></small></div><div class="wg-traffic-error" style="display:none"></div>
</div>
<style>.wg-traffic{margin:18px 0}.wg-traffic-canvas{display:block;border:1px solid rgba(127,127,127,.25);border-radius:4px}.wg-traffic-values{margin-top:8px;line-height:1.8}.wg-traffic-error{margin-top:8px;color:#b33}.wg-runtime-time{margin:8px 0;text-align:right;opacity:.8}.wg-actions form{margin-right:8px}.wg-danger-zone{margin:16px 0;padding:12px;border:1px solid rgba(190,50,40,.45);border-radius:4px}</style>
<script>(function(){
 const root=document.getElementById('$id');if(!root)return;const canvas=root.querySelector('canvas'),ctx=canvas.getContext('2d');
 const interfaceName=$js_name,peerKey=$js_peer,windowSec=Number(root.dataset.window)||900,maxPoints=10000;let raw=[],current=null;
 function fmt(v,rate){if(v==null||!isFinite(v))return'—';const u=['B','KiB','MiB','GiB','TiB'];let i=0;while(v>=1024&&i<u.length-1){v/=1024;i++}return(v>=100||i===0?v.toFixed(0):v>=10?v.toFixed(1):v.toFixed(2))+' '+u[i]+(rate?'/s':'')}
 function colors(){const s=getComputedStyle(document.documentElement);return{tx:s.getPropertyValue('--primary-color').trim()||'#4f8dd6',rx:s.getPropertyValue('--success-color').trim()||'#42a878',text:s.color||'#aaa',grid:'rgba(127,127,127,.22)',zero:'rgba(190,190,190,.8)'}}
 function normalize(){const byTime=new Map();for(const p of raw){if(p&&Number.isFinite(Number(p.timestamp)))byTime.set(Number(p.timestamp),{timestamp:Number(p.timestamp),rx:Number(p.rx)||0,tx:Number(p.tx)||0})}raw=Array.from(byTime.values()).sort((a,b)=>a.timestamp-b.timestamp);const cutoff=(raw.length?raw[raw.length-1].timestamp:Math.floor(Date.now()/1000))-windowSec;raw=raw.filter(p=>p.timestamp>=cutoff).slice(-maxPoints)}
 function rates(){const out=[];for(let i=0;i<raw.length;i++){const c=raw[i],p=i?raw[i-1]:null;let txRate=0,rxRate=0;if(p&&c.timestamp>p.timestamp&&c.tx>=p.tx&&c.rx>=p.rx){const dt=c.timestamp-p.timestamp;txRate=(c.tx-p.tx)/dt;rxRate=(c.rx-p.rx)/dt}out.push({time:c.timestamp,txRate:txRate,rxRate:rxRate,tx:c.tx,rx:c.rx})}return out}
 function resize(){const dpr=window.devicePixelRatio||1,w=Math.max(300,canvas.clientWidth),h=300;if(canvas.width!==Math.round(w*dpr)||canvas.height!==Math.round(h*dpr)){canvas.width=Math.round(w*dpr);canvas.height=Math.round(h*dpr);ctx.setTransform(dpr,0,0,dpr,0,0)}draw()}
 function draw(){const samples=rates(),w=canvas.clientWidth,h=300,c=colors(),pad={l:68,r:12,t:18,b:28},pw=w-pad.l-pad.r,ph=h-pad.t-pad.b,zero=pad.t+ph/2;ctx.clearRect(0,0,w,h);let max=1024;for(const p of samples)max=Math.max(max,p.txRate||0,p.rxRate||0);const pow=Math.pow(1024,Math.floor(Math.log(max)/Math.log(1024))),scaled=Math.ceil(max/pow),step=scaled<=2?.5:scaled<=5?1:2,limit=Math.max(pow,Math.ceil(scaled/step)*step*pow);ctx.font='12px sans-serif';ctx.fillStyle=c.text;ctx.strokeStyle=c.grid;ctx.lineWidth=1;for(let i=0;i<=4;i++){const val=limit*i/4,yt=zero-(ph/2)*(i/4),yb=zero+(ph/2)*(i/4);if(i){ctx.beginPath();ctx.moveTo(pad.l,yt);ctx.lineTo(w-pad.r,yt);ctx.stroke();ctx.beginPath();ctx.moveTo(pad.l,yb);ctx.lineTo(w-pad.r,yb);ctx.stroke()}const lab=fmt(val,true);ctx.textAlign='right';ctx.textBaseline='middle';ctx.fillText(lab,pad.l-7,yt);if(i)ctx.fillText(lab,pad.l-7,yb)}ctx.strokeStyle=c.zero;ctx.lineWidth=1.5;ctx.beginPath();ctx.moveTo(pad.l,zero);ctx.lineTo(w-pad.r,zero);ctx.stroke();ctx.fillStyle=c.text;ctx.textAlign='left';ctx.fillText('TX',pad.l+6,pad.t+8);ctx.fillText('RX',pad.l+6,h-pad.b-8);
 if(samples.length>1){const end=samples[samples.length-1].time,start=end-windowSec;function area(field,color,down){ctx.beginPath();ctx.moveTo(pad.l,zero);samples.forEach(p=>{const x=pad.l+pw*Math.max(0,Math.min(1,(p.time-start)/(end-start||1))),y=zero+(down?1:-1)*(ph/2)*Math.min(1,(p[field]||0)/limit);ctx.lineTo(x,y)});ctx.lineTo(w-pad.r,zero);ctx.closePath();ctx.globalAlpha=.22;ctx.fillStyle=color;ctx.fill();ctx.globalAlpha=1;ctx.beginPath();samples.forEach((p,i)=>{const x=pad.l+pw*Math.max(0,Math.min(1,(p.time-start)/(end-start||1))),y=zero+(down?1:-1)*(ph/2)*Math.min(1,(p[field]||0)/limit);i?ctx.lineTo(x,y):ctx.moveTo(x,y)});ctx.strokeStyle=color;ctx.lineWidth=2;ctx.stroke()}area('txRate',c.tx,false);area('rxRate',c.rx,true)}if(samples.length){const end=samples[samples.length-1].time,start=end-windowSec;ctx.fillStyle=c.text;ctx.textAlign='left';ctx.fillText(new Date(start*1000).toLocaleTimeString(),pad.l,h-7);ctx.textAlign='right';ctx.fillText(new Date(end*1000).toLocaleTimeString(),w-pad.r,h-7)}}
 function showSample(sample,timestamp){if(!sample)return;current={timestamp:Number(timestamp)||Math.floor(Date.now()/1000),rx:Number(sample.rx)||0,tx:Number(sample.tx)||0};raw.push(current);normalize();const rs=rates(),last=rs[rs.length-1]||{};root.querySelector('.wg-tx-now').textContent='↑ TX: '+fmt(last.txRate||0,true);root.querySelector('.wg-rx-now').textContent='↓ RX: '+fmt(last.rxRate||0,true);root.querySelector('.wg-tx-total').textContent='$tx_total: '+fmt(current.tx,false);root.querySelector('.wg-rx-total').textContent='$rx_total: '+fmt(current.rx,false);root.querySelector('.wg-updated').textContent=new Date(current.timestamp*1000).toLocaleString();root.querySelector('.wg-traffic-error').style.display='none';draw()}
 async function loadHistory(){try{const response=await fetch(root.dataset.historyUrl,{cache:'no-store',credentials:'same-origin',redirect:'error',headers:{'Accept':'application/json','X-Requested-With':'XMLHttpRequest'}}),body=await response.text(),contentType=(response.headers.get('content-type')||'').toLowerCase();if(!contentType.includes('application/json')){const sample=body.replace(/\s+/g,' ').trim().slice(0,240);throw new Error('HTTP '+response.status+': сервер вернул не JSON'+(sample?': '+sample:''))}let data;try{data=JSON.parse(body)}catch(parseError){const sample=body.replace(/\s+/g,' ').trim().slice(0,240);throw new Error('Некорректный JSON-ответ'+(sample?': '+sample:''))}if(!data.ok)throw new Error(data.error||('HTTP '+response.status));if(Array.isArray(data.history)){raw=raw.concat(data.history);normalize();draw();if(raw.length){const last=raw[raw.length-1];root.querySelector('.wg-tx-total').textContent='$tx_total: '+fmt(last.tx,false);root.querySelector('.wg-rx-total').textContent='$rx_total: '+fmt(last.rx,false);root.querySelector('.wg-updated').textContent=new Date(last.timestamp*1000).toLocaleString()}}}catch(error){const x=root.querySelector('.wg-traffic-error');x.textContent=error.message;x.style.display='block'}}
 document.addEventListener('wg-runtime',function(event){const data=event.detail||{},iface=data.interfaces&&data.interfaces[interfaceName];if(!iface||!iface.active){root.querySelector('.wg-updated').textContent='$inactive';return}if(peerKey){const peer=(iface.peers||[]).find(p=>p.public_key===peerKey);if(peer)showSample({rx:peer.rx,tx:peer.tx},data.timestamp)}else showSample({rx:iface.rx,tx:iface.tx},data.timestamp)});
 window.addEventListener('resize',resize);requestAnimationFrame(function(){resize();setTimeout(loadHistory,0)});
})();</script>
HTML
}

1;

1;
