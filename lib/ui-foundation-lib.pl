# Shared presentation controls for all Webmin WireGuard pages.
# Icon names map to fixed inline SVG paths; nothing caller-provided becomes SVG.
sub wg_ui_icon {
    my ($name)=@_;
    my %paths=(
      history=>'<path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 3v6h6"/><path d="M12 7v5l3 2"/>',
      globe=>'<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18"/>',
      edit=>'<path d="M12 20h9M16.5 3.5a2.12 2.12 0 0 1 3 3L9 17l-4 1 1-4Z"/>',
      plus=>'<path d="M12 5v14M5 12h14"/>',
      refresh=>'<path d="M20 7v5h-5M4 17v-5h5"/><path d="M5 9a8 8 0 0 1 14-2l1 5M19 15a8 8 0 0 1-14 2l-1-5"/>',
      play=>'<path d="m7 4 13 8-13 8z" fill="currentColor"/>',
      stop=>'<rect x="5" y="5" width="14" height="14" rx="2" fill="currentColor"/>',
      trash=>'<path d="M4 7h16M10 11v6M14 11v6M6 7l1 14h10l1-14M9 7V4h6v3"/>',
      copy=>'<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/>',
      log=>'<path d="M7 3h10l4 4v14H7zM17 3v5h4M10 12h8M10 16h8"/>',
      external=>'<path d="M14 4h6v6M20 4l-9 9M20 14v6H4V4h6"/>',
      chevron=>'<path d="m6 9 6 6 6-6"/>',
      close=>'<path d="M18 6 6 18M6 6l12 12"/>',
      info=>'<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
      gear=>'<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"/>',
      save=>'<path d="M4 3h14l3 3v15H3V3zM7 3v7h9V3M7 21v-8h10v8"/>',
      download=>'<path d="M12 3v13M7 11l5 5 5-5M4 17v4h16v-4"/>',
      network=>'<rect x="3" y="3" width="6" height="6" rx="1"/><rect x="15" y="3" width="6" height="6" rx="1"/><rect x="9" y="15" width="6" height="6" rx="1"/><path d="M6 9v3h12V9M12 12v3"/>',
      chart=>'<path d="M3 3v18h18M7 16l4-5 4 3 5-7"/>',
      check=>'<path d="m4 12 5 5L20 6"/>',
      database=>'<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 4 18 4 18 0V5M3 12c0 4 18 4 18 0"/>',
      wrench=>'<path d="M14.5 6.3a5 5 0 0 0-6.1 6.1L3 17.8a2.1 2.1 0 0 0 3.2 3l5.3-5.4a5 5 0 0 0 6.2-6.1l-3.2 3.1-3.1-3.1z"/>',
      shield=>'<path d="M12 2 4 5v6c0 5.2 3.1 8.8 8 11 4.9-2.2 8-5.8 8-11V5z"/><path d="m8 12 3 3 5-5"/>',
      warning=>'<path d="M10.4 3.9 2.2 18.2A1.9 1.9 0 0 0 3.8 21h16.4a1.9 1.9 0 0 0 1.6-2.8L13.6 3.9a1.9 1.9 0 0 0-3.2 0z"/><path d="M12 9v5M12 17h.01"/>',

    );
    return '' unless exists $paths{$name};
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">'.$paths{$name}.'</svg>';
}
# Single whitelist and tone contract for links, buttons and table controls.
sub wg_ui_attrs {
    my ($attrs)=@_;
    return '' unless ref($attrs) eq 'HASH';
    my $html='';
    for my $key (sort keys %$attrs) {
        next unless $key =~ /^(?:data-[a-z0-9-]+|aria-[a-z0-9-]+|name|value|id|disabled|form)$/;
        $html.=' '.$key.'="'.html_escape($attrs->{$key}).'"';
    }
    return $html;
}
sub wg_ui_icon_action {
    my (%a)=@_;
    my $label=html_escape($a{'label'}||'');
    my $tone=$a{'tone'}||($a{'danger'}?'danger':'neutral');
    $tone='neutral' unless $tone =~ /^(?:neutral|success|warning|danger|info)$/;
    my %theme=(neutral=>'text-muted',success=>'text-success',
        warning=>'text-warning',danger=>'text-danger',info=>'text-primary');
    my $attr=' class="btn btn-link wg-ui-icon-btn wg-ui-tone-'.$tone.' '.$theme{$tone}.'" title="'.$label.
        '" aria-label="'.$label.'"'.wg_ui_attrs($a{'attrs'});
    if($a{'href'}) {
        return '<a href="'.html_escape($a{'href'}).'"'.$attr.
            ' data-wg-module-navigation="1">'.wg_ui_icon($a{'icon'}).'</a>';
    }
    return '<button type="'.html_escape($a{'type'}||'button').'"'.$attr.'>'.
        wg_ui_icon($a{'icon'}).'</button>';
}
sub wg_ui_button {
    my (%a)=@_;
    my $tone=$a{'tone'}||'neutral';
    $tone='neutral' unless $tone =~ /^(?:neutral|success|warning|danger|info)$/;
    my $label=html_escape($a{'label'}||'');
    my $body=($a{'icon'}?wg_ui_icon($a{'icon'}).' ':'').'<span>'.$label.'</span>';
    my $extra=($a{'class'}||'');
    $extra='' if $extra =~ /[^A-Za-z0-9 _-]/;
    my %theme=(neutral=>'btn-default',success=>'btn-success',
        warning=>'btn-warning',danger=>'btn-danger',info=>'btn-primary');
    my $attr=' class="btn '.$theme{$tone}.' wg-ui-btn wg-ui-tone-'.$tone.
        ($extra?' '.$extra:'').'"'.
        wg_ui_attrs($a{'attrs'});
    if($a{'href'}) {
        return '<a href="'.html_escape($a{'href'}).'"'.$attr.
            ' data-wg-module-navigation="1">'.$body.'</a>';
    }
    return '<button type="'.html_escape($a{'type'}||'button').'"'.$attr.'>'.$body.'</button>';
}
# Field controls stay browser-native; the backend remains the authority for
# CIDR parsing, port ranges and concurrent configuration changes.
sub wg_ui_number_input {
    my ($name,$value,$min,$max)=@_;
    return '<input type="number" class="form-control wg-ui-number-input"'.
        ' name="'.html_escape($name).'" value="'.html_escape(defined($value)?$value:'').'"'.
        ' min="'.int($min).'" max="'.int($max).'" step="1" inputmode="numeric">';
}
sub wg_ui_validated_input {
    my ($name,$value,$size,$validator,$hint)=@_;
    my $attr=$validator ? ' data-wg-validate="'.html_escape($validator).'"' : '';
    $attr.=' title="'.html_escape($hint).'"' if $hint;
    return '<input type="text" class="form-control wg-ui-validated-input"'.
        ' name="'.html_escape($name).'" value="'.html_escape(defined($value)?$value:'').'"'.
        ' size="'.int($size||42).'"'.$attr.'>';
}
sub wg_ui_panel_start {
    my ($title,%opts)=@_;
    my $danger=($opts{'tone'}||'') eq 'danger';
    return '<details class="wg-ui-panel '.($danger?'wg-ui-danger':'wg-ui-tools').'"'.
        ($danger?' data-wg-danger-zone':' data-wg-tool-panel').'>'.
        '<summary>'.wg_ui_icon('chevron').
        ($danger ? wg_ui_icon('warning') : wg_ui_icon('wrench')).
        ' '.html_escape($title||'').'</summary>'.
        '<div class="'.($danger?'wg-ui-danger-body':'wg-ui-tools-body').'">';
}
sub wg_ui_panel_end { return '</div></details>'; }
sub wg_ui_panel {
    my ($title,$body,%opts)=@_;
    return wg_ui_panel_start($title,%opts).($body||'').wg_ui_panel_end();
}
sub wg_ui_action_bar {
    my ($left,$right)=@_;
    return '<div class="wg-ui-action-bar"><div class="wg-ui-action-group">'.
        ($left||'').'</div><div class="wg-ui-action-group wg-ui-action-right">'.
        ($right||'').'</div></div>';
}
sub wg_ui_danger_zone {
    my ($body,$title)=@_;
    $title||=$text{'danger_zone'}||'Dangerous operations';
    return wg_ui_panel($title,$body,tone=>'danger');
}
sub wg_ui_foundation {
    my $markup= <<'WG_UI_FOUNDATION';
<style>
/* Shared sizing and color semantics. Theme fonts and surfaces are inherited. */
.wg-ui{--wg-success:var(--success-color,#55c899);--wg-info:var(--primary-color,#5d9de2);--wg-warning:var(--warning-color,#e5ac55);--wg-danger:var(--danger-color,#d26d65);--wg-border:rgba(127,127,127,.28)}
.wg-ui .wg-ui-action-bar,.wg-ui .wg-ui-button-row{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap;margin:10px 0 14px}
.wg-ui .wg-ui-action-group{display:inline-flex;align-items:center;gap:8px;flex-wrap:wrap}
.wg-ui .wg-ui-action-right{margin-left:auto}
.wg-ui .wg-ui-action-bar .wg-ui-btn,.wg-ui .wg-ui-button-row .wg-ui-btn,.wg-ui .wg-ui-btn{display:inline-flex;align-items:center;justify-content:center;gap:7px;min-height:31px;padding:5px 10px;margin:0;white-space:nowrap}
/* Authentic Theme owns all button backgrounds, borders, foregrounds and states. */
.wg-ui .wg-ui-btn{text-decoration:none}
.wg-ui .wg-ui-icon-btn.wg-ui-tone-success{color:var(--success-color,#55c899)}
.wg-ui .wg-ui-icon-btn.wg-ui-tone-warning{color:var(--warning-color,#e5ac55)}
.wg-ui .wg-ui-icon-btn.wg-ui-tone-danger{color:var(--danger-color,#d26d65)}
.wg-ui .wg-ui-icon-btn.wg-ui-tone-info{color:var(--primary-color,#5d9de2)}
.wg-ui .wg-ui-icon-btn{display:inline-flex;align-items:center;justify-content:center;width:30px;height:30px;min-width:30px;border:1px solid transparent;border-radius:4px;background:transparent;cursor:pointer;text-decoration:none;padding:0;vertical-align:middle}
.wg-ui .wg-ui-icon-btn svg{display:block;width:17px;height:17px;flex:none;stroke:currentColor;stroke-width:1.9}
.wg-ui .wg-ui-icon-btn:hover,.wg-ui .wg-ui-icon-btn:focus-visible{border-color:currentColor;background:rgba(127,127,127,.15);text-decoration:none;outline-offset:2px}
.wg-ui .wg-ui-icon-btn:disabled{opacity:.5;cursor:wait}
.wg-ui .wg-ui-icon-btn [hidden]{display:none!important}
.wg-ui .wg-ui-table-actions{display:inline-flex;align-items:center;justify-content:center;gap:3px;flex-wrap:nowrap;white-space:nowrap}
.wg-ui .wg-ui-table-actions form,.wg-ui .wg-ui-action-group form{margin:0;display:inline-flex;align-items:center}
.wg-ui .wg-ui-compact-table td:last-child,.wg-ui .wg-ui-compact-table th:last-child{text-align:center;white-space:nowrap}
.wg-ui .wg-ui-compact-table td:nth-last-child(2),.wg-ui .wg-ui-compact-table th:nth-last-child(2){text-align:center}
.wg-ui .wg-ui-mono{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-variant-numeric:tabular-nums}
.wg-ui .wg-ui-copy{display:inline-flex;align-items:center;gap:5px}
.wg-ui .wg-ui-panel,.wg-ui .wg-ui-danger,.wg-ui .wg-ui-tools{margin:12px 0;border:1px solid var(--wg-border);border-radius:5px}
.wg-ui .wg-ui-danger{border-color:rgba(190,75,75,.4)}
.wg-ui .wg-ui-panel>summary,.wg-ui .wg-ui-danger>summary,.wg-ui .wg-ui-tools>summary{display:flex;align-items:center;gap:8px;padding:10px 12px;font-weight:600;cursor:pointer;list-style:none}
.wg-ui .wg-ui-danger>summary{color:var(--wg-danger)}
.wg-ui .wg-ui-panel>summary::-webkit-details-marker,.wg-ui .wg-ui-danger>summary::-webkit-details-marker,.wg-ui .wg-ui-tools>summary::-webkit-details-marker{display:none}
.wg-ui .wg-ui-panel[open]>summary svg,.wg-ui .wg-ui-danger[open]>summary svg,.wg-ui .wg-ui-tools[open]>summary svg{transform:rotate(180deg)}
.wg-ui .wg-ui-danger-body,.wg-ui .wg-ui-tools-body{padding:12px;border-top:1px solid var(--wg-border)}
.wg-ui .wg-ui-danger-body form{display:inline-flex;flex-wrap:wrap;align-items:end;gap:8px;margin:6px 8px 6px 0}
.wg-ui .wg-ui-danger-body label{display:flex;flex-direction:column;gap:4px}
.wg-ui .wg-ui-summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(195px,1fr));gap:10px}
.wg-ui .wg-ui-summary-card{border:1px solid var(--wg-border);border-radius:5px;padding:12px;min-width:0}
.wg-ui .wg-ui-summary-card>span{display:block;font-size:12px;opacity:.7;margin-bottom:6px}
.wg-ui .wg-ui-summary-card>strong{display:block;font-size:16px;font-weight:600;overflow-wrap:anywhere}
.wg-ui .wg-ui-status{display:inline-block;border:1px solid var(--wg-border);border-radius:4px;padding:2px 6px;font-weight:600}
.wg-ui .wg-ui-status--success{color:var(--wg-success);border-color:var(--wg-success)}
.wg-ui .wg-ui-status--muted{opacity:.65}
.wg-ui [data-wg-net-icon][hidden],.wg-ui [data-wg-geoip-country][hidden]{display:none!important}
.wg-ui .wg-endpoint-with-icon{display:inline-flex;align-items:center;gap:5px}
.wg-ui .wg-network-icon{display:inline-flex;align-items:center;justify-content:center;flex:0 0 20px;width:20px;height:20px;box-sizing:border-box;border:1.5px solid currentColor;border-radius:50%;background:rgba(127,127,127,.12);font:inherit;font-weight:600;font-size:11px;line-height:1;white-space:nowrap;overflow:hidden}
.wg-ui .wg-network-icon[data-custom="1"]{font-size:10px}
.wg-ui .wg-geoip-country{font:inherit;font-size:11px;font-weight:600;white-space:nowrap;opacity:.9}

.wg-ui .wg-ui-form-row{display:flex;align-items:end;gap:10px;flex-wrap:wrap}
.wg-ui .wg-ui-form-row label{display:flex;flex-direction:column;gap:4px}
.wg-ui .wg-ui-form-row input,.wg-ui .wg-ui-form-row select{font:inherit}
.wg-ui .wg-ui-number-input{width:105px;max-width:100%;display:inline-block}
.wg-ui .wg-ui-validated-input{width:auto;max-width:100%;display:inline-block}
.wg-ui [data-wg-validate]:invalid{border-color:var(--wg-danger)}

.wg-ui .wg-analytics-table td,.wg-ui .wg-analytics-table th{font-variant-numeric:tabular-nums}
.wg-ui-modal[hidden]{display:none!important}
.wg-ui-modal{position:fixed;inset:0;z-index:100001;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.65);padding:20px}
.wg-ui-modal-panel.panel{box-shadow:0 12px 40px rgba(0,0,0,.35);max-width:760px;max-height:88vh;overflow:auto;width:100%;padding:16px;margin:0}
.wg-ui-modal-header{display:flex;align-items:center;justify-content:space-between;gap:12px}
.wg-ui-modal-body{padding-top:12px}
.wg-ui-modal-body th{width:30%;overflow-wrap:anywhere}
.wg-ui-modal-body td{overflow-wrap:anywhere}
@media(max-width:700px){.wg-ui .wg-ui-action-right{margin-left:0}.wg-ui-modal{padding:8px}.wg-ui .wg-ui-compact-table{overflow-x:auto}}
</style>
<script>
(function(){
 'use strict';
 const messages=__WG_UI_MESSAGES__;
 if(window.WireGuardUI && window.WireGuardUI.version===1)return;
 const ui={
  version:1,
  async copy(value){
   if(!navigator.clipboard||!navigator.clipboard.writeText)
     throw Error('Clipboard unavailable');
   await navigator.clipboard.writeText(value);
  },
  confirm(message){return window.confirm(message);},
  confirmAction(message,word){return confirmModal(message,word||'');},
  flag(code){
   const value=String(code||'').trim().toUpperCase();
   return /^[A-Z]{2}$/.test(value)
    ? String.fromCodePoint(...Array.from(value,c=>127397+c.charCodeAt(0))) : '';
  },
  renderNetwork(badge,country,info,address){
   // Same badge/country contract in the live peer table and history views.
   // This method is presentation-only: it does not trigger WHOIS or GeoIP IO.
   const hasIp=!!String(address||'').trim();
   const network=hasIp&&info&&typeof info==='object'?info:null;
   if(badge){
    badge.hidden=!hasIp;
    badge.textContent=network&&network.icon?String(network.icon):'?';
    badge.dataset.custom=network&&network.icon&&network.icon!=='?'?'1':'0';
    badge.title=network?[network.cidr,network.label,network.country].filter(Boolean).join(' — '):'';
   }
   if(country){
    const raw=network&&typeof network.country==='string'?network.country.trim().toUpperCase():'';
    const code=/^[A-Z]{2}$/.test(raw)?raw:'';
    country.textContent=code?this.flag(code)+' '+code:'';
    country.hidden=!code;
    country.title=code?((network.country_source==='geoip'?'GeoIP':'WHOIS')+': '+code):'';
   }
  }
 };
 window.WireGuardUI=Object.freeze(ui);
 document.addEventListener('click',function(ev){
   const button=ev.target.closest('[data-wg-copy-target]');
   if(!button)return;
   const root=button.closest('.wg-ui');
   if(!root)return;
   const target=root.querySelector('#'+CSS.escape(button.dataset.wgCopyTarget));
   if(!target)return;
   ev.preventDefault();
   ui.copy(('value' in target?target.value:target.textContent).trim()).then(()=>{
     button.dataset.wgCopied='1';
     const original=button.title;
     button.title=button.dataset.wgCopiedLabel||messages.copied;
     setTimeout(()=>{if(button.isConnected)button.title=original;},1800);
   }).catch(()=>{button.title=button.dataset.wgCopyError||messages.clipboardError;});
 },true);
 function confirmModal(message,word){
  return new Promise(resolve=>{
   const overlay=document.createElement('div');
   overlay.className='wg-ui-modal wg-ui';
   overlay.setAttribute('role','presentation');
   const panel=document.createElement('div');
   panel.className='wg-ui-modal-panel panel panel-default';
   panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','true');
   panel.setAttribute('aria-label',messages.confirmTitle);
   const heading=document.createElement('h3');heading.textContent=messages.confirmTitle;
   const body=document.createElement('p');body.textContent=message||messages.confirmPrompt;
   panel.append(heading,body);
   let field=null;
   if(word){
    const label=document.createElement('label');
    label.textContent=messages.confirmType+' '+word;
    field=document.createElement('input');
    field.className='form-control';field.autocomplete='off';
    field.setAttribute('aria-label',word);
    label.append(field);panel.append(label);
   }
   const buttons=document.createElement('div');
   buttons.className='wg-ui-action-bar';
   const cancel=document.createElement('button');cancel.type='button';
   cancel.className='btn btn-default wg-ui-btn';cancel.textContent=messages.cancel;
   const accept=document.createElement('button');accept.type='button';
   accept.className='btn btn-danger wg-ui-btn';accept.textContent=messages.accept;
   if(word)accept.disabled=true;
   buttons.append(cancel,accept);panel.append(buttons);overlay.append(panel);
   const active=document.activeElement;
   let finished=false;
   const onKey=e=>{
    if(e.key==='Escape'){e.preventDefault();finish(false);}
    if(e.key==='Enter'&&field&&document.activeElement===field&&!accept.disabled){
     e.preventDefault();finish(true);
    }
   };
   function finish(result){
    if(finished)return;finished=true;
    document.removeEventListener('keydown',onKey,true);
    overlay.remove();
    if(active&&active.isConnected&&typeof active.focus==='function')active.focus();
    resolve(result);
   }
   overlay.addEventListener('click',e=>{if(e.target===overlay)finish(false);});
   cancel.addEventListener('click',()=>finish(false));
   accept.addEventListener('click',()=>finish(true));
   if(field)field.addEventListener('input',()=>{accept.disabled=field.value!==word;});
   document.addEventListener('keydown',onKey,true);
   document.body.append(overlay);
   (field||cancel).focus();
  });
 }
 // Validation offers early feedback; server-side validation remains required.
 function validCIDR(value){
  const p=value.lastIndexOf('/');
  if(p<1||!/^\d+$/.test(value.slice(p+1)))return false;
  const address=value.slice(0,p),mask=Number(value.slice(p+1));
  if(address.includes(':')){
   if(mask<0||mask>128)return false;
   try{new URL('http://['+address+']/');return true;}catch(_){return false;}
  }
  if(mask<0||mask>32)return false;
  const octets=address.split('.');
  return octets.length===4&&octets.every(x=>/^\d{1,3}$/.test(x)&&Number(x)<=255);
 }
 function validEndpoint(value){
  if(!value)return true;
  let host=value,port='',hasPort=false;
  if(value.startsWith('[')){
   const end=value.indexOf(']');
   if(end<2)return false;
   host=value.slice(1,end);
   const rest=value.slice(end+1);
   if(rest&&rest.charAt(0)!==':')return false;
   if(rest){hasPort=true;port=rest.slice(1);}
   try{new URL('http://['+host+']/');}catch(_){return false;}
  }else if(value.indexOf(':')===value.lastIndexOf(':')&&value.includes(':')){
   const idx=value.lastIndexOf(':');
   host=value.slice(0,idx);port=value.slice(idx+1);
   hasPort=true;
   if(!/^[a-zA-Z0-9_.-]+$/.test(host))return false;
  }else if(!/^[a-zA-Z0-9_.-]+$/.test(value))return false;
  return !hasPort||(/^\d{1,5}$/.test(port)&&Number(port)>=1&&Number(port)<=65535);
 }
 function validateField(field){
  const value=field.value.trim(),kind=field.dataset.wgValidate;
  let ok=true;
  if(value&&kind==='cidr-list'){
   const cidrs=value.split(/[,\n]+/).map(x=>x.trim()).filter(Boolean);
   ok=cidrs.length>0 && cidrs.every(validCIDR);
  }
  if(value&&kind==='endpoint')ok=validEndpoint(value);
  field.setCustomValidity(ok?'':field.dataset.wgInvalidMessage||'Invalid value');
  return ok;
 }
 document.addEventListener('input',function(ev){
  if(ev.target.matches&&ev.target.matches('[data-wg-validate]'))validateField(ev.target);
 },true);
 document.addEventListener('submit',function(ev){
  const form=ev.target.closest('form');
  if(!form||!form.closest('.wg-ui'))return;
  for(const field of form.querySelectorAll('[data-wg-validate]')){
   if(!validateField(field)){ev.preventDefault();field.reportValidity();return;}
  }
  const submitter=ev.submitter;
  const message=form.dataset.wgConfirm || (submitter&&submitter.dataset.wgConfirm);
  const word=form.dataset.wgConfirmWord || (submitter&&submitter.dataset.wgConfirmWord) || '';
  if(!message)return;
  if(form.dataset.wgConfirmed==='1'){delete form.dataset.wgConfirmed;return;}
  ev.preventDefault();ev.stopImmediatePropagation();
  confirmModal(message,word).then(ok=>{
   if(!ok||!form.isConnected)return;
   const token=form.querySelector('input[name="confirm"]');
   if(token&&word)token.value=word;
   form.dataset.wgConfirmed='1';
   if(typeof form.requestSubmit==='function')form.requestSubmit(submitter||undefined);
   else form.submit();
  });
 },true);
 document.addEventListener('click',function(ev){
  const anchor=ev.target.closest('a[data-wg-confirm]');
  if(!anchor||!anchor.closest('.wg-ui'))return;
  if(anchor.dataset.wgConfirmed==='1'){delete anchor.dataset.wgConfirmed;return;}
  ev.preventDefault();ev.stopImmediatePropagation();
  confirmModal(anchor.dataset.wgConfirm,anchor.dataset.wgConfirmWord||'').then(ok=>{
   if(ok&&anchor.isConnected){anchor.dataset.wgConfirmed='1';anchor.click();}
  });
 },true);
})();
</script>
WG_UI_FOUNDATION
    my $strings=json_encode_utf8({
        confirmTitle=>$text{'ui_confirm_title'},
        confirmPrompt=>$text{'ui_confirm_prompt'},
        confirmType=>$text{'ui_confirm_type'},
        cancel=>$text{'ui_confirm_cancel'},
        accept=>$text{'ui_confirm_accept'},
        copied=>$text{'ui_copied'},
        clipboardError=>$text{'ui_copy_unavailable'},
    });
    $markup =~ s/__WG_UI_MESSAGES__/$strings/g;
    return $markup;
}
1;
