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
      play=>'<path d="m8 5 11 7-11 7z"/>',
      stop=>'<rect x="5" y="5" width="14" height="14" rx="2"/>',
      trash=>'<path d="M4 7h16M10 11v6M14 11v6M6 7l1 14h10l1-14M9 7V4h6v3"/>',
      copy=>'<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/>',
      log=>'<path d="M7 3h10l4 4v14H7zM17 3v5h4M10 12h8M10 16h8"/>',
      external=>'<path d="M14 4h6v6M20 4l-9 9M20 14v6H4V4h6"/>',
      chevron=>'<path d="m6 9 6 6 6-6"/>',
      info=>'<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
      gear=>'<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"/>',
    );
    return '' unless exists $paths{$name};
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">'.$paths{$name}.'</svg>';
}
sub wg_ui_icon_action {
    my (%a)=@_;
    my $label=html_escape($a{'label'}||'');
    my $klass='wg-ui-icon-btn'.($a{'danger'}?' wg-ui-icon-danger':'');
    my $attributes=' class="'.html_escape($klass).'" title="'.$label.'" aria-label="'.$label.'"';
    if ($a{'attrs'} && ref($a{'attrs'}) eq 'HASH') {
        for my $key (sort keys %{$a{'attrs'}}) {
            next unless $key =~ /^(?:data-[a-z0-9-]+|aria-[a-z0-9-]+)$/;
            $attributes.=' '.$key.'="'.html_escape($a{'attrs'}{$key}).'"';
        }
    }
    if($a{'href'}) {
        return '<a href="'.html_escape($a{'href'}).'"'.$attributes.'>'.wg_ui_icon($a{'icon'}).'</a>';
    }
    return '<button type="'.html_escape($a{'type'}||'button').'"'.$attributes.'>'.
        wg_ui_icon($a{'icon'}).'</button>';
}
sub wg_ui_action_bar {
    my ($left,$right)=@_;
    return '<div class="wg-ui-action-bar"><div class="wg-ui-action-group">'.
        ($left||'').'</div><div class="wg-ui-action-group wg-ui-action-right">'.
        ($right||'').'</div></div>';
}
sub wg_ui_danger_zone {
    my ($body,$title)=@_;
    $title||=$text{'danger_zone'}||'Опасные операции';
    return '<details class="wg-ui-danger" data-wg-danger-zone>'.
        '<summary>'.wg_ui_icon('chevron').' '.html_escape($title).'</summary>'.
        '<div class="wg-ui-danger-body">'.($body||'').'</div></details>';
}
sub wg_ui_foundation {
    return <<'WG_UI_FOUNDATION';
<style>
.wg-ui .wg-ui-action-bar{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap;margin:10px 0 14px}
.wg-ui .wg-ui-action-group{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.wg-ui .wg-ui-action-right{margin-left:auto}
.wg-ui .wg-ui-icon-btn{display:inline-flex;align-items:center;justify-content:center;width:29px;height:29px;border:1px solid transparent;border-radius:5px;background:transparent;color:inherit;cursor:pointer;text-decoration:none;vertical-align:middle}
.wg-ui .wg-ui-icon-btn:hover,.wg-ui .wg-ui-icon-btn:focus-visible{border-color:var(--primary-color,#4786ca);background:rgba(125,125,125,.15);text-decoration:none;outline-offset:2px}
.wg-ui .wg-ui-icon-danger{color:var(--danger-color,#c4524c)}
.wg-ui .wg-ui-icon-danger:hover{background:rgba(195,55,55,.1);border-color:var(--danger-color,#c4524c)}
.wg-ui .wg-ui-table-actions{display:inline-flex;align-items:center;gap:3px;white-space:nowrap}
.wg-ui .wg-ui-table-actions form{margin:0;display:inline}
.wg-ui .wg-ui-compact-table td:last-child,.wg-ui .wg-ui-compact-table th:last-child{white-space:nowrap}
.wg-ui .wg-ui-mono{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-variant-numeric:tabular-nums}
.wg-ui .wg-ui-danger{margin:15px 0;border:1px solid rgba(195,55,55,.35);border-radius:5px}
.wg-ui .wg-ui-danger>summary{display:flex;align-items:center;gap:7px;padding:10px 12px;font-weight:600;cursor:pointer;list-style:none;color:var(--danger-color,#d27470)}
.wg-ui .wg-ui-danger>summary::-webkit-details-marker{display:none}
.wg-ui .wg-ui-danger[open]>summary svg{transform:rotate(180deg)}
.wg-ui .wg-ui-danger-body{padding:12px;border-top:1px solid rgba(195,55,55,.25)}
.wg-ui .wg-ui-danger-body form{display:inline-flex;flex-wrap:wrap;align-items:end;gap:8px;margin:6px 8px 6px 0}
.wg-ui .wg-ui-danger-body label{display:flex;flex-direction:column;gap:4px}
.wg-ui .wg-ui-summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(195px,1fr));gap:10px}
.wg-ui .wg-ui-summary-card{border:1px solid rgba(127,127,127,.24);border-radius:5px;padding:12px;min-width:0}
.wg-ui .wg-ui-summary-card>span{display:block;font-size:12px;opacity:.7;margin-bottom:6px}
.wg-ui .wg-ui-summary-card>strong{display:block;font-size:16px;font-weight:600;overflow-wrap:anywhere}
.wg-ui .wg-ui-copy{display:inline-flex;align-items:center;gap:5px}
.wg-ui-modal[hidden]{display:none!important}
.wg-ui-modal{position:fixed;inset:0;z-index:100001;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.65);padding:20px}
.wg-ui-modal-panel{background:var(--bg-color,#252629);color:inherit;border:1px solid rgba(127,127,127,.4);box-shadow:0 12px 40px rgba(0,0,0,.35);border-radius:7px;max-width:760px;max-height:88vh;overflow:auto;width:100%;padding:16px}
.wg-ui-modal-header{display:flex;align-items:center;justify-content:space-between;gap:12px}
.wg-ui-modal-body{padding-top:12px}
.wg-ui-modal-body th{width:30%;overflow-wrap:anywhere}
.wg-ui-modal-body td{overflow-wrap:anywhere}
@media(max-width:700px){.wg-ui .wg-ui-action-right{margin-left:0}.wg-ui-modal{padding:8px}}
</style>
<script>
(function(){
 'use strict';
 if(window.WireGuardUI && window.WireGuardUI.version===1)return;
 const ui={
  version:1,
  async copy(value){
   if(!navigator.clipboard||!navigator.clipboard.writeText)
     throw Error('Clipboard unavailable');
   await navigator.clipboard.writeText(value);
  },
  confirm(message){return window.confirm(message);}
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
   ui.copy(target.textContent.trim()).then(()=>{
     button.dataset.wgCopied='1';
     const original=button.title;
     button.title=button.dataset.wgCopiedLabel||'Скопировано';
     setTimeout(()=>{if(button.isConnected)button.title=original;},1800);
   }).catch(()=>{button.title=button.dataset.wgCopyError||'Копирование недоступно';});
 },true);
 function confirmModal(message,word){
  return new Promise(resolve=>{
   const overlay=document.createElement('div');
   overlay.className='wg-ui-modal wg-ui';
   overlay.setAttribute('role','presentation');
   const panel=document.createElement('div');
   panel.className='wg-ui-modal-panel';
   panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','true');
   panel.setAttribute('aria-label','Подтверждение операции');
   const heading=document.createElement('h3');heading.textContent='Подтверждение операции';
   const body=document.createElement('p');body.textContent=message||'Подтвердить действие?';
   panel.append(heading,body);
   let field=null;
   if(word){
    const label=document.createElement('label');
    label.textContent='Для подтверждения введите '+word;
    field=document.createElement('input');
    field.className='form-control';field.autocomplete='off';
    field.setAttribute('aria-label',word);
    label.append(field);panel.append(label);
   }
   const buttons=document.createElement('div');
   buttons.className='wg-ui-action-bar';
   const cancel=document.createElement('button');cancel.type='button';
   cancel.className='btn btn-default';cancel.textContent='Отмена';
   const accept=document.createElement('button');accept.type='button';
   accept.className='btn btn-danger';accept.textContent='Подтвердить';
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
 document.addEventListener('submit',function(ev){
  const form=ev.target.closest('form');
  if(!form||!form.closest('.wg-ui'))return;
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
}
1;
