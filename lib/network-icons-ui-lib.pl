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
    const picker=root.querySelector('[data-wg-locode-dialog]');
    const queryInput=picker?.querySelector('[data-wg-locode-query]');
    const count=picker?.querySelector('[data-wg-locode-count]');
    const results=picker?.querySelector('[data-wg-locode-results]');
    const page=picker?.querySelector('[data-wg-locode-page]');
    const prev=picker?.querySelector('[data-wg-locode-prev]');
    const next=picker?.querySelector('[data-wg-locode-next]');
    if(city&&cityCode&&picker&&locodeSource&&queryInput&&results){
        const url=locodeSource.dataset.wgUnlocodeSearchUrl;
        let offset=0,total=0,sequence=0,debounce=null,abort=null;
        const normalize=value=>String(value||'').normalize('NFD')
            .replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase();
        function highlight(parent,name,term){
            // Highlight literal matching fragments, never inject server text as HTML.
            const original=String(name||'');
            const plain=normalize(original),needle=normalize(term);
            const at=plain.indexOf(needle);
            if(at<0||!needle){parent.textContent=original;return;}
            const chars=Array.from(original);
            const before=chars.slice(0,at).join('');
            const match=chars.slice(at,at+Array.from(term).length).join('');
            parent.append(document.createTextNode(before));
            const mark=document.createElement('mark');
            mark.textContent=match;
            parent.append(mark,document.createTextNode(chars.slice(at+Array.from(term).length).join('')));
        }
        async function search(){
            const term=queryInput.value.trim();
            const seq=++sequence;
            abort?.abort();
            abort=new AbortController();
            results.replaceChildren();
            prev.disabled=next.disabled=true;
            if(term.length<2){count.textContent='Введите минимум 2 символа';return;}
            count.textContent='Поиск…';
            try{
                const query=new URLSearchParams({term,offset:String(offset)});
                const response=await window.WireGuardTransport.requestJson(
                    url+'?'+query.toString(),{method:'GET',signal:abort.signal},{requireOk:true});
                if(seq!==sequence||picker.hidden)return;
                total=Number(response.total||0);
                count.textContent='Найдено: '+total;
                page.textContent=total?(offset+1)+'–'+Math.min(offset+100,total)+' из '+total:'';
                prev.disabled=offset===0;
                next.disabled=offset+100>=total;
                let lastCountry='';
                const table=document.createElement('table');
                table.className='table table-striped table-hover wg-locode-table';
                const tbody=document.createElement('tbody');
                table.append(tbody);
                (response.matches||[]).forEach(place=>{
                    if(lastCountry!==place.country){
                        lastCountry=place.country;
                        const group=document.createElement('tr');
                        group.className='wg-locode-country';
                        const heading=document.createElement('th');
                        heading.colSpan=3;
                        heading.textContent=lastCountry;
                        group.append(heading);tbody.append(group);
                    }
                    const tr=document.createElement('tr');
                    const name=document.createElement('td');
                    highlight(name,place.name,term);
                    const sub=document.createElement('small');
                    sub.textContent=place.subdivision?' ('+place.subdivision+')':'';
                    name.append(sub);
                    const code=document.createElement('td');
                    highlight(code,place.code,term);
                    const action=document.createElement('td');
                    const choose=document.createElement('button');
                    choose.type='button';choose.className='btn btn-info btn-sm';
                    choose.textContent='Выбрать';
                    choose.addEventListener('click',()=>{
                        city.value=place.name;cityCode.value=place.code;
                        picker.hidden=true;city.focus();
                    });
                    action.append(choose);
                    tr.append(name,code,action);tbody.append(tr);
                });
                if(!tbody.children.length)results.textContent='Совпадений нет';
                else results.append(table);
            }catch(error){
                if(seq===sequence && !abort.signal.aborted){
                    count.textContent='Ошибка поиска';
                    results.textContent=error.message||String(error);
                }
            }
        }
        const schedule=()=>{
            clearTimeout(debounce);offset=0;
            debounce=setTimeout(search,250);
        };
        editor.querySelector('[data-wg-city-search-button]')?.addEventListener('click',()=>{
            picker.hidden=false;
            queryInput.value=city.value.trim()||cityCode.value.trim();
            offset=0;search();queryInput.focus();
        });
        queryInput.addEventListener('input',schedule);
        prev.addEventListener('click',()=>{offset=Math.max(0,offset-100);search();});
        next.addEventListener('click',()=>{if(offset+100<total){offset+=100;search();}});
        picker.querySelector('[data-wg-locode-close]')?.addEventListener('click',()=>{
            picker.hidden=true;abort?.abort();
        });
        picker.addEventListener('click',event=>{
            if(event.target===picker){picker.hidden=true;abort?.abort();}
        });
        root.addEventListener('keydown',event=>{
            if(event.key==='Escape'&&!picker.hidden){picker.hidden=true;abort?.abort();}
        });
        // Code lookup resolves full official names without guessing.
        cityCode.addEventListener('change',async()=>{
            const code=cityCode.value.trim().toUpperCase();
            if(!/^[A-Z]{2}[A-Z0-9]{3}$/.test(code))return;
            try{
                const data=await window.WireGuardTransport.requestJson(
                    url+'?'+new URLSearchParams({term:code}).toString(),
                    {method:'GET'},{requireOk:true});
                const match=(data.matches||[]).find(place=>place.code===code);
                if(match)city.value=match.name;
            }catch(error){}
        });
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
    const confirmation=root.querySelector('[data-wg-cache-confirm]');
    const options=root.querySelector('[data-wg-cache-options]');
    const table=root.querySelector('[data-wg-network-table]');
    let pending=null;
    function add(tag,value,parent){
        const node=document.createElement(tag);
        if(value!==null&&value!==undefined)node.textContent=String(value);
        parent.append(node);
        return node;
    }
    function section(title,data){
        const block=add('section',null,output);
        block.className='wg-peer-ip-section';
        add('h4',title,block);
        if(!data||!data.ok){add('p',data?.detail||'Нет данных',block);return;}
        const body=add('tbody',null,add('table',null,block));
        (data.fields||[]).forEach(field=>{
            const row=add('tr',null,body);
            add('th',field.label||'',row);add('td',field.value||'',row);
        });
        if(data.raw){
            const details=add('details',null,block);
            add('summary','Полный ответ WHOIS',details);
            add('pre',data.raw,details);
        }
    }
    function busy(node,value){
        node.disabled=value;
        node.classList.toggle('wg-cache-busy',value);
        node.setAttribute('aria-busy',String(value));
    }
    function closeDialog(){
        pending?.abort();pending=null;
        dialog.hidden=true;
        confirmation.hidden=true;
        confirmation.replaceChildren();
    }
    async function refreshTable(signal){
        // Fetch the latest server-rendered network table and replace only its DOM.
        // No navigation, page reload, or replacement of the editor/modal.
        const response=await fetch(window.location.href,{
            credentials:'same-origin',cache:'no-store',signal,
            headers:{'X-Requested-With':'XMLHttpRequest'}
        });
        if(!response.ok)throw new Error('Не удалось обновить таблицу: HTTP '+response.status);
        const documentCopy=new DOMParser().parseFromString(await response.text(),'text/html');
        const updated=documentCopy.querySelector('[data-wg-network-table]');
        if(!updated)throw new Error('В ответе отсутствует таблица сетей');
        table.replaceChildren(...Array.from(updated.children).map(node=>node.cloneNode(true)));
        // GeoIP flag placeholders in the replaced table need normal decoration.
        root.querySelectorAll('[data-wg-country]').forEach(node=>{
            const code=node.dataset.wgCountry||'';
            if(/^[A-Z]{2}$/.test(code))node.textContent=window.WireGuardUI.flag(code)+' '+code;
        });
        root.querySelectorAll('[data-wg-geoip-codes]').forEach(node=>{
            const codes=(node.dataset.wgGeoipCodes||'').split(',').filter(c=>/^[A-Z]{2}$/.test(c));
            node.textContent=codes.map(c=>window.WireGuardUI.flag(c)+' '+c).join(', ');
        });
    }
    async function queryIp(ip,commit,controller,preview){
        const body=new URLSearchParams({
            ip:ip,_wg_csrf:options.dataset.wgCacheToken,commit:commit?'1':'0'
        });
        if(commit && preview)body.set('preview',JSON.stringify({
            ip,whois:preview.whois,geoip:preview.geoip
        }));
        return window.WireGuardTransport.requestJson(options.dataset.wgCacheUrl,{
            method:'POST',signal:controller.signal,
            headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},
            body:body.toString()
        },{requireOk:true});
    }
    if(dialog&&output&&confirmation&&options&&table){
        root.addEventListener('click',async event=>{
            if(event.target.closest('[data-wg-cache-close]')){closeDialog();return;}
            const trigger=event.target.closest('[data-wg-cache-refresh]');
            if(!trigger||!root.contains(trigger))return;
            event.preventDefault();
            const group=trigger.closest('.wg-cache-lookup');
            const ip=group?.querySelector('select')?.value||trigger.dataset.wgCacheRefresh;
            pending?.abort();
            const controller=new AbortController();
            pending=controller;
            dialog.hidden=false;
            confirmation.hidden=true;
            confirmation.replaceChildren();
            output.replaceChildren();
            busy(trigger,true);
            add('p','Запрос WHOIS и GeoIP выполняется…',output).className='wg-cache-loading';
            try{
                const result=await queryIp(ip,false,controller);
                if(controller.signal.aborted||pending!==controller||dialog.hidden)return;
                output.replaceChildren();
                add('h4',result.ip||ip,output);
                section('WHOIS',result.whois);
                section('GeoIP',result.geoip);
                const city=result.city_match||{};
                const block=add('section',null,output);
                add('h4','City / UN/LOCODE',block);
                add('p',city.city?
                    city.city+(city.city_code?' — '+city.city_code:'')+
                    (city.source==='manual'?' (вручную)':''):'Не определён',block);
                const approve=add('button','Обновить кеш',confirmation);
                approve.type='button';
                approve.className='btn btn-success';
                const cancel=add('button','Оставить без изменений',confirmation);
                cancel.type='button';
                cancel.className='btn btn-default';
                confirmation.hidden=false;
                cancel.addEventListener('click',()=>{confirmation.hidden=true;});
                approve.addEventListener('click',async()=>{
                    busy(approve,true);confirmation.querySelectorAll('button').forEach(b=>b.disabled=true);
                    const indicator=add('p','Обновление кеша…',output);
                    indicator.className='wg-cache-loading';
                    try{
                        const committed=await queryIp(ip,true,controller,result);
                        if(controller.signal.aborted||pending!==controller)return;
                        if(!committed.network_cached)
                            throw new Error(committed.network_cache_error||'Кеш не обновлён');
                        indicator.textContent='Кеш обновлён. Обновление таблицы…';
                        await refreshTable(controller.signal);
                        indicator.textContent='Кеш и таблица обновлены';
                        indicator.classList.remove('wg-cache-loading');
                        confirmation.hidden=true;
                    }catch(error){
                        if(!controller.signal.aborted)indicator.textContent=error.message||String(error);
                    }finally{
                        confirmation.querySelectorAll('button').forEach(b=>b.disabled=false);
                        busy(approve,false);
                    }
                });
            }catch(error){
                if(!controller.signal.aborted){
                    output.replaceChildren();
                    add('p',error.message||String(error),output);
                }
            }finally{
                busy(trigger,false);
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
