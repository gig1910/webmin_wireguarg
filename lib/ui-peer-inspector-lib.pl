# Inline peer IP investigation. Never contacts WHOIS until the administrator
# explicitly clicks the globe icon. Uses the existing authenticated CGI.
sub wg_ui_peer_inspector {
    my ($name,$csrf,$page_id)=@_;
    my $title=html_escape($text{'peer_ip_title'}||'WHOIS / GeoIP');
    my $label=html_escape($text{'peer_ip_lookup'}||'WHOIS / GeoIP');
    my $close=html_escape($text{'ui_close'}||'Close');
    my $markup='<div class="wg-ui-modal" data-wg-ip-dialog hidden role="dialog" aria-modal="true" aria-label="'.$title.'">'.
        '<div class="wg-ui-modal-panel panel panel-default">'.
        '<div class="wg-ui-modal-header"><h3>'.$title.'</h3>'.
        wg_ui_button(type=>'button',icon=>'close',
            label=>$text{'ui_close'}||'Close',
            attrs=>{'data-wg-ip-close'=>1}).'</div>'.
        '<div class="wg-ui-modal-body" data-wg-ip-output role="status" aria-live="polite"></div>'.
        '</div></div>';
    $markup.='<div hidden data-wg-ip-options'.
        ' data-wg-ip-name="'.html_escape($name).'"'.
        ' data-wg-ip-token="'.html_escape($csrf).'"'.
        ' data-wg-ip-url="'.html_escape(module_script_url('peer_ip_info.cgi')).'"'.
        ' data-wg-ip-busy="'.html_escape($text{'peer_ip_busy'}||'Загрузка…').'"'.
        ' data-wg-ip-unavailable="'.html_escape($text{'peer_ip_unavailable'}||'Нет данных').'"'.
        ' data-wg-ip-whois="'.html_escape($text{'peer_ip_whois'}||'WHOIS').'"'.
        ' data-wg-ip-geoip="'.html_escape($text{'peer_ip_geoip'}||'GeoIP').'"'.
        ' data-wg-ip-raw="'.html_escape($text{'peer_ip_raw'}||'Raw response').'"'.
        ' data-wg-ip-city-note="'.html_escape($text{'ui_ip_city_note'}||'').'"'.
        '></div>';
    $markup.=wg_ui_peer_inspector_script(json_encode_utf8($page_id));
    return $markup;
}
sub wg_ui_peer_inspector_script {
    my ($page_json)=@_;
    return <<INSPECTOR_SCRIPT;
<script>
(function(){
 'use strict';
 const pageId=$page_json;
 const root=document.querySelector('[data-wg-interface-page="'+pageId+'"]');
 if(!root)return;
 const dialog=root.querySelector('[data-wg-ip-dialog]');
 const out=root.querySelector('[data-wg-ip-output]');
 const options=root.querySelector('[data-wg-ip-options]');
 if(!dialog||!out||!options)return;
 const opts=options.dataset;
 let request=null,oldFocus=null;
 function element(tag,value,parent,klass){
  const n=document.createElement(tag);
  if(value!==undefined&&value!==null)n.textContent=String(value);
  if(klass)n.className=klass;
  (parent||out).append(n);return n;
 }
 function section(label,result){
  const group=element('section',null,out,'wg-peer-ip-section');
  element('h4',label,group);
  if(!result || !result.ok){
   element('p',result&&result.detail||opts.wgIpUnavailable,group,'help-block');return;
  }
  const table=element('table',null,group,'table table-striped');
  const tbody=element('tbody',null,table);
  for(const field of result.fields||[]){
   const tr=element('tr',null,tbody);
   element('th',field.label||'',tr);
   const raw=String(field.value||'');
   const countryField=/country/i.test(String(field.label||''));
   const prefix=raw.trim().slice(0,2).toUpperCase();
   const iso=/^[A-Z]{2}\$/.test(prefix) &&
     (raw.trim().length===2 || raw.trim().charAt(2)===',');
   const country=countryField ? (iso?prefix:result.country_code||'') : '';
   const flag=window.WireGuardUI.flag(country);
   element('td',(flag?flag+' ':'')+raw,tr,'wg-ui-mono');
  }
  if(label===opts.wgIpGeoip && opts.wgIpCityNote &&
     !(result.fields||[]).some(field=>field.label==='City'))
   element('p',opts.wgIpCityNote,group,'help-block');
  if(result.source)element('small',result.source,group,'help-block');
  if(result.raw){
   const detail=element('details',null,group),summary=element('summary',opts.wgIpRaw,detail);
   element('pre',result.raw,detail);
  }
 }
 function close(){
  if(request){request.abort();request=null;}
  dialog.hidden=true;
  if(oldFocus&&oldFocus.isConnected)oldFocus.focus();
 }
 async function open(button){
  oldFocus=button;
  dialog.hidden=false;
  out.replaceChildren();
  element('p',opts.wgIpBusy,out,'help-block');
  dialog.querySelector('[data-wg-ip-close]').focus();
  if(request)request.abort();
  request=new AbortController();
  const controller=request;
  try{
   const payload=new URLSearchParams({
     name:opts.wgIpName,peer:button.dataset.wgIpInspect,
     _wg_csrf:opts.wgIpToken
   });
   // Optional historical endpoint, validated against retained events server-side.
   if(button.dataset.wgIpValue&&button.dataset.wgIpAt){
    payload.set('ip',button.dataset.wgIpValue);
    payload.set('at',button.dataset.wgIpAt);
   }
   const data=await window.WireGuardTransport.requestJson(opts.wgIpUrl,{
     method:'POST',signal:controller.signal,
     headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},
     body:payload.toString()
   },{requireOk:true});
   if(controller.signal.aborted||request!==controller||dialog.hidden||!root.isConnected)return;
   out.replaceChildren();
   if(!data.available){
    element('p',data.detail||opts.wgIpUnavailable,out,'alert alert-info');return;
   }
   element('h4',data.ip||'',out,'wg-ui-mono');
   section(opts.wgIpWhois,data.whois);
   section(opts.wgIpGeoip,data.geoip);
   if(data.city_match && data.city_match.city){
    const group=element('section',null,out,'wg-peer-ip-section');
    const isManual=data.city_match.source==='manual';
    element('h4',isManual?'City (manual override)':'City / UN/LOCODE',group);
    const description=data.city_match.city+
      (data.city_match.city_code?' — '+data.city_match.city_code:'');
    element('p',description,group,'wg-ui-mono');
   }
   if(data.network_cached)
     root.dispatchEvent(new CustomEvent('wg-network-cache-updated',{bubbles:true}));
  }catch(err){
   if(!controller.signal.aborted&&request===controller&&!dialog.hidden&&root.isConnected){
    out.replaceChildren();element('p',err.message||String(err),out,'alert alert-warning');
   }
  }finally{if(request===controller)request=null;}
 }
 function onClick(e){
  const trigger=e.target.closest('[data-wg-ip-inspect]');
  if(trigger&&root.contains(trigger)){e.preventDefault();open(trigger);return;}
  if(!dialog.hidden&&(e.target.closest('[data-wg-ip-close]')||e.target===dialog))close();
 }
 function onKey(e){if(e.key==='Escape'&&!dialog.hidden){e.preventDefault();close();}}
 root.addEventListener('click',onClick);
 document.addEventListener('keydown',onKey);
 const observer=new MutationObserver(function(){
  if(root.isConnected)return;
  close();observer.disconnect();document.removeEventListener('keydown',onKey);
  root.removeEventListener('click',onClick);
 });
 observer.observe(document.documentElement,{subtree:true,childList:true});
})();
</script>
INSPECTOR_SCRIPT
}
1;
