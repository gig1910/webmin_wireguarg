=head1 network-icons-ui-lib.pl

Manual network icon editing and country badge rendering.
No network requests or module mutations occur in this browser controller.

=cut

sub wg_network_icons_page_script
{
    my ($js_page_id)=@_;
    my $html=<<'NETWORK_UI';
<style>
.wg-ui .wg-network-edit-link{font:inherit}
</style>
<script>
(function(){
    'use strict';
    const pageId=__WG_PAGE_ID__;
    const root=document.querySelector('[data-wg-network-page="'+pageId+'"]');
    if(!root)return;
    const editor=root.querySelector('#wg-network-editor');
    if(!editor)return;
    const cidr=editor.querySelector('[name="cidr"]');
    const icon=editor.querySelector('[name="icon"]');
    const label=editor.querySelector('[name="label"]');
    const city=editor.querySelector('[name="city"]');
    const cityCode=editor.querySelector('[name="city_code"]');
    const choices=editor.querySelector('[data-wg-city-choices]');
    const locodeSource=root.querySelector('[data-wg-unlocode-search-url]');
    let countryHint='';
    let searchSequence=0;
    editor.querySelector('[data-wg-city-clear]')?.addEventListener('click',()=>{
        if(city)city.value='';
        if(cityCode)cityCode.value='';
        searchSequence++;
        const matches=editor.querySelector('[data-wg-city-choices]');
        if(matches){matches.replaceChildren();matches.hidden=true;}
        city?.focus();
    });
    if(choices){choices.className='wg-unlocode-choices';}
    root.querySelectorAll('[data-wg-edit-range]').forEach(function(button){
        button.addEventListener('click',function(){
            cidr.value=button.dataset.cidr||'';
            icon.value=button.dataset.icon||'?';
            label.value=button.dataset.label||'';
            if(city)city.value=button.dataset.city||button.dataset.suggestedCity||'';
            countryHint=button.closest('tr')?.querySelector('[data-wg-country]')?.dataset.wgCountry||'';
            if(choices)choices.hidden=true;
            if(cityCode)cityCode.value=button.dataset.cityCode||button.dataset.suggestedCode||'';
            editor.scrollIntoView({behavior:'smooth',block:'center'});
            icon.focus({preventScroll:true});
        });
    });
    if(city&&cityCode&&choices&&locodeSource){
        const searchUrl=locodeSource.dataset.wgUnlocodeSearchUrl;
        let timeoutId=null;
        const clear=()=>{choices.replaceChildren();choices.hidden=true;};
        const search=()=>{
            clear();
            const query=city.value.trim()||cityCode.value.trim();
            if(timeoutId)clearTimeout(timeoutId);
            const seq=++searchSequence;
            if(query.length<2)return;
            timeoutId=setTimeout(async()=>{
                choices.hidden=false;
                choices.textContent='Поиск UN/LOCODE…';
                try{
                    const url=searchUrl+'?'+new URLSearchParams({
                        term:query,country:countryHint||''
                    }).toString();
                    const response=await window.WireGuardTransport.requestJson(url,{
                        method:'GET'
                    },{requireOk:true});
                    if(seq!==searchSequence)return;
                    clear();
                    if(!Array.isArray(response.matches)||!response.matches.length){
                        choices.hidden=false;
                        choices.textContent='Совпадений нет';
                        return;
                    }
                    response.matches.forEach(place=>{
                        const button=document.createElement('button');
                        button.type='button';
                        button.className='btn btn-default wg-city-choice';
                        button.textContent=place.name+' · '+place.code+
                            (place.subdivision?' ('+place.subdivision+')':'');
                        button.addEventListener('click',()=>{
                            city.value=place.name;
                            cityCode.value=place.code;
                            clear();
                        });
                        choices.append(button);
                    });
                    choices.hidden=false;
                }catch(error){
                    if(seq===searchSequence){
                        choices.hidden=false;
                        choices.textContent='Поиск недоступен: '+(error.message||String(error));
                    }
                }
            },200);
        };
        city.addEventListener('input',()=>{
            cityCode.value='';
            search();
        });
        editor.querySelector('[data-wg-city-search-button]')?.addEventListener('click',search);
        cityCode.addEventListener('input',()=>{
            searchSequence++;
            clear();
            const code=cityCode.value.trim().toUpperCase();
            if(!/^[A-Z]{2}[A-Z0-9]{3}$/.test(code))return;
            const seq=++searchSequence;
            (async()=>{
                try{
                    const url=searchUrl+'?'+new URLSearchParams({term:code}).toString();
                    const result=await window.WireGuardTransport.requestJson(url,{method:'GET'},{requireOk:true});
                    if(seq!==searchSequence)return;
                    const match=(result.matches||[]).find(p=>p.code===code);
                    if(match)city.value=match.name;
                }catch(error){
                    if(seq===searchSequence){
                        choices.hidden=false;
                        choices.textContent='Не удалось найти код: '+(error.message||String(error));
                    }
                }
            })();
        });
        editor.addEventListener('reset',()=>{countryHint='';clear();});
    }
    const saveUrl=root.querySelector('[data-wg-city-save-url]')?.dataset.wgCitySaveUrl;
    const saveForm=editor.querySelector('form');
    if(saveForm&&saveUrl){
        saveForm.addEventListener('submit',async event=>{
            event.preventDefault();
            const data=new URLSearchParams(new FormData(saveForm));
            const display=root.querySelector('[data-wg-cache-dialog]');
            const target=root.querySelector('[data-wg-cache-output]');
            const header=display?.querySelector('.wg-ui-modal-header h3');
            if(!display||!target)return;
            if(header)header.textContent='Сохранение назначения';
            display.hidden=false;
            target.replaceChildren();
            const status=document.createElement('p');
            status.textContent='Сохранение…';
            target.append(status);
            try{
                const result=await window.WireGuardTransport.requestJson(saveUrl,{
                    method:'POST',
                    headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},
                    body:data.toString()
                },{requireOk:true});
                if(result.ok){window.location.reload();return;}
            }catch(error){
                status.textContent=error.message||String(error);
            }
        });
    }
    const dialog=root.querySelector('[data-wg-cache-dialog]');
    const output=root.querySelector('[data-wg-cache-output]');
    const options=root.querySelector('[data-wg-cache-options]');
    let pending=null;
    function add(tag,value,parent) {
        const node=document.createElement(tag);
        if(value!==null && value!==undefined)node.textContent=String(value);
        parent.append(node);
        return node;
    }
    function section(label,source) {
        const block=add('section',null,output);
        block.className='wg-peer-ip-section';
        add('h4',label,block);
        if(!source||!source.ok){
            add('p',source&&source.detail||'No data',block);
            return;
        }
        const table=add('table',null,block);
        table.className='table table-striped';
        const body=add('tbody',null,table);
        (source.fields||[]).forEach(field=>{
            const tr=add('tr',null,body);
            add('th',field.label||'',tr);
            add('td',field.value||'',tr);
        });
        if(source.source)add('small',source.source,block);
        if(source.raw){
            const details=add('details',null,block);
            add('summary','WHOIS raw response',details);
            add('pre',source.raw,details);
        }
    }
    function closeDialog(){
        if(pending){pending.abort();pending=null;}
        if(dialog)dialog.hidden=true;
    }
    if(dialog && output && options){
        root.addEventListener('click',async event=>{
            if(event.target.closest('[data-wg-cache-close]')){
                closeDialog();return;
            }
            const trigger=event.target.closest('[data-wg-cache-refresh]');
            if(!trigger || !root.contains(trigger))return;
            event.preventDefault();
            const group=trigger.closest('.wg-cache-lookup');
            const chosen=group&&group.querySelector('select');
            const ip=chosen?chosen.value:trigger.dataset.wgCacheRefresh;
            if(pending)pending.abort();
            const controller=new AbortController();
            pending=controller;
            dialog.hidden=false;
            const title=dialog.querySelector('.wg-ui-modal-header h3');
            if(title)title.textContent='Обновление кеша IP';
            output.replaceChildren();
            add('p','Loading WHOIS / GeoIP / UN/LOCODE…',output);
            try{
                const payload=new URLSearchParams({ip:ip,_wg_csrf:options.dataset.wgCacheToken});
                const response=await window.WireGuardTransport.requestJson(
                    options.dataset.wgCacheUrl,{
                        method:'POST',signal:controller.signal,
                        headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},
                        body:payload.toString()
                    },{requireOk:true});
                if(controller.signal.aborted || pending!==controller || dialog.hidden)return;
                output.replaceChildren();
                add('h4',response.ip||ip,output);
                section('WHOIS',response.whois);
                section('GeoIP',response.geoip);
                const place=response.city_match||{};
                const city=add('section',null,output);
                city.className='wg-peer-ip-section';
                add('h4','City / UN/LOCODE',city);
                add('p',place.city?
                    place.city+(place.city_code?' — '+place.city_code:'')+
                    (place.source==='manual'?' (manual)':''):'Not determined',city);
                if(!response.network_cached)
                    add('p',response.network_cache_error||'Cache update unavailable',output);
                else{
                    const hint=add('p','Cache updated. Reload the list to view new data.',output);
                    hint.className='help-block';
                }
            }catch(error){
                if(!controller.signal.aborted){
                    output.replaceChildren();
                    add('p',error.message||String(error),output);
                }
            }finally{
                if(pending===controller)pending=null;
            }
        });
        dialog.addEventListener('click',event=>{
            if(event.target===dialog)closeDialog();
        });
        root.addEventListener('keydown',event=>{
            if(event.key==='Escape'&&!dialog.hidden)closeDialog();
        });
    }
    const flagFor=code=>window.WireGuardUI.flag(code);
    root.querySelectorAll('[data-wg-geoip-codes]').forEach(function(node){
        const codes=(node.dataset.wgGeoipCodes||'').split(',').map(s=>s.trim().toUpperCase())
            .filter(s=>/^[A-Z]{2}$/.test(s));
        node.textContent=codes.map(code=>flagFor(code)+' '+code).join(', ');
    });
    root.querySelectorAll('[data-wg-country]').forEach(function(node){
        const code=(node.dataset.wgCountry||'').trim().toUpperCase();
        if(!/^[A-Z]{2}$/.test(code))return;
        const flag=flagFor(code);
        node.textContent=flag+' '+code;
    });
})();
</script>
NETWORK_UI
    # Safe insertion of a JSON-encoded string without an interpolating heredoc.
    # In particular, JavaScript /...$/ must survive Perl's $/ interpolation.
    $html =~ s/__WG_PAGE_ID__/$js_page_id/g;
    return $html;
}

1;
