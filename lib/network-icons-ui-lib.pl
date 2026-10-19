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
    const overrideCountry=editor.querySelector('[name="country_override"]');
    let manualCountry='';
    let searchSequence=0;
    editor.querySelector('[data-wg-city-clear]')?.addEventListener('click',()=>{
        if(city)city.value='';
        if(cityCode)cityCode.value='';
        if(overrideCountry)overrideCountry.value='';
        manualCountry='';
        searchSequence++;
        const matches=editor.querySelector('[data-wg-city-choices]');
        if(matches){matches.replaceChildren();matches.hidden=true;}
        city?.focus();
    });
    if(choices){choices.className='wg-unlocode-choices';}
    root.addEventListener('click',function(event){
        const button=event.target.closest('[data-wg-edit-range]');
        if(!button || !root.contains(button))return;
            cidr.value=button.dataset.cidr||'';
            icon.value=button.dataset.icon||'?';
            label.value=button.dataset.label||'';
            if(city)city.value=button.dataset.city||button.dataset.suggestedCity||'';
            countryHint=button.dataset.observedCountry||'';
            manualCountry=button.dataset.manualCountry||'';
            if(overrideCountry)overrideCountry.value=manualCountry;
            if(choices)choices.hidden=true;
            if(cityCode)cityCode.value=button.dataset.cityCode||button.dataset.suggestedCode||'';
            editor.scrollIntoView({behavior:'smooth',block:'center'});
            icon.focus({preventScroll:true});
    });
    const picker=root.querySelector('[data-wg-locode-dialog]');
    const queryInput=picker?.querySelector('[data-wg-locode-query]');
    const count=picker?.querySelector('[data-wg-locode-count]');
    const results=picker?.querySelector('[data-wg-locode-results]');
    const page=picker?.querySelector('[data-wg-locode-page]');
    const prev=picker?.querySelector('[data-wg-locode-prev]');
    const next=picker?.querySelector('[data-wg-locode-next]');
    const filter=picker?.querySelector('[data-wg-locode-filter]');
    const filterCountry=picker?.querySelector('[data-wg-locode-country]');
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
                const requestUrl=new URL(url,window.location.href);
                requestUrl.searchParams.set('term',term);
                requestUrl.searchParams.set('offset',String(offset));
                if(filter?.checked && countryHint)requestUrl.searchParams.set('country',countryHint);
                const response=await window.WireGuardTransport.requestJson(
                    requestUrl.toString(),{method:'GET',signal:abort.signal},{requireOk:true});
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
                        const chosen=place.country||place.code.slice(0,2);
                        if(countryHint && chosen!==countryHint){
                            const message='Город '+place.name+' ('+place.code+
                                ') относится к стране '+chosen+
                                ', а ранее определённая страна сети — '+countryHint+
                                '. Изменить отображаемую страну вручную на '+chosen+'?';
                            if(!window.confirm(message))return;
                        }
                        city.value=place.name;cityCode.value=place.code;
                        manualCountry=countryHint && chosen!==countryHint ? chosen : '';
                        if(overrideCountry)overrideCountry.value=manualCountry;
                        picker.hidden=true;city.focus();
                    });
                    action.append(choose);
                    tr.append(name,code,action);tbody.append(tr);
                });
                if(!tbody.children.length){
                    results.textContent='Совпадений нет';
                    if(response.diagnostic){
                        const diagnostic=document.createElement('details');
                        const title=document.createElement('summary');
                        title.textContent='Диагностика поиска';
                        diagnostic.append(title);
                        const pre=document.createElement('pre');
                        pre.textContent=JSON.stringify(response.diagnostic,null,2);
                        diagnostic.append(pre);
                        results.append(diagnostic);
                    }
                }
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
            if(filter){filter.checked=!!countryHint;filter.disabled=!countryHint;}
            if(filterCountry)filterCountry.textContent=countryHint||'не определена';
            offset=0;search();queryInput.focus();
        });
        queryInput.addEventListener('input',schedule);
        filter?.addEventListener('change',()=>{offset=0;search();});
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
                    (()=>{const lookupUrl=new URL(url,window.location.href);
                        lookupUrl.searchParams.set('term',code);
                        return lookupUrl.toString();})(),
                    {method:'GET'},{requireOk:true});
                const match=(data.matches||[]).find(place=>place.code===code);
                if(match)city.value=match.name;
            }catch(error){}
        });
    }
    const saveUrl=root.querySelector('[data-wg-city-save-url]')?.dataset.wgCitySaveUrl;
    const statusLine=root.querySelector('[data-wg-network-status]');
    let tableSequence=0;
    function showStatus(message,kind){
        if(!statusLine)return;
        statusLine.textContent=message;
        statusLine.className='alert alert-'+(kind||'info');
        statusLine.hidden=false;
    }
    async function mutate(url,data){
        const result=await window.WireGuardTransport.requestJson(url,{
            method:'POST',credentials:'same-origin',
            headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},
            body:new URLSearchParams(data).toString()
        },{requireOk:true});
        if(!result.ok)throw new Error(result.error||'Не удалось сохранить изменения');
        showStatus('Данные сохранены. Обновление таблицы…','info');
        await refreshTable();
        showStatus('Таблица обновлена','success');
    }
    const saveForm=editor.querySelector('form');
    if(saveForm&&saveUrl){
        saveForm.addEventListener('submit',async event=>{
            event.preventDefault();
            const submit=saveForm.querySelector('[type="submit"]');
            if(submit?.disabled)return;
            if(submit)busy(submit,true);
            showStatus('Сохранение назначения…','info');
            try{
                await mutate(saveUrl,new FormData(saveForm));
            }catch(error){showStatus(error.message||String(error),'danger');}
            finally{if(submit)busy(submit,false);}
        });
    }
    // Destructive forms use the shared confirmation modal; its second
    // submit event (after confirmation) is handled asynchronously here.
    root.addEventListener('submit',async event=>{
        const form=event.target;
        if(!form.matches('[data-wg-network-mutation]'))return;
        event.preventDefault();
        const action=form.querySelector('[name="action"]')?.value;
        const submit=event.submitter||form.querySelector('[type="submit"]');
        if(submit?.disabled)return;
        if(submit)busy(submit,true);
        showStatus(action==='clear_cache'?'Очистка кеша…':'Удаление назначения…','info');
        try{
            const data=new FormData(form);
            data.set('_wg_ajax','1');
            await mutate(form.action,data);
        }catch(error){showStatus(error.message||String(error),'danger');}
        finally{if(submit)busy(submit,false);}
    });
    // Background synchronization is queued, not completed, by its CGI.
    // Poll the read-only status until a new result appears, preserving the page.
    const syncSource=root.querySelector('[data-wg-unlocode-status-url]')?.dataset.wgUnlocodeStatusUrl;
    let syncSequence=0;
    async function syncState(){
        return window.WireGuardTransport.requestJson(syncSource,{
            method:'GET',credentials:'same-origin',cache:'no-store'
        },{requireOk:true});
    }
    async function followUnlocode(before){
        const seq=++syncSequence;
        for(let attempt=0;attempt<120;attempt++){
            await new Promise(resolve=>setTimeout(resolve,5000));
            if(seq!==syncSequence||!root.isConnected)return;
            let state;
            try{state=await syncState();}
            catch(error){
                showStatus('Ошибка проверки синхронизации: '+(error.message||String(error)),'danger');
                return;
            }
            if(state.updated_at!==before.updated_at && state.updated_at){
                showStatus('UN/LOCODE синхронизирован. Обновление таблицы…','info');
                try{await refreshTable();}
                catch(error){return;}
                showStatus('UN/LOCODE и таблица обновлены','success');
                return;
            }
            if(state.error && state.error_mtime>before.error_mtime){
                showStatus('Ошибка UN/LOCODE: '+state.error,'danger');
                return;
            }
        }
        if(seq===syncSequence)showStatus('Синхронизация ещё не подтверждена. Проверьте статус задания.','warning');
    }
    root.addEventListener('submit',async event=>{
        const form=event.target.closest('[data-wg-network-action]');
        if(!form)return;
        event.preventDefault();
        const submit=event.submitter||form.querySelector('[type="submit"]');
        if(submit?.disabled)return;
        const action=form.dataset.wgNetworkAction;
        if(submit)busy(submit,true);
        showStatus(action==='unlocode'?'Запуск синхронизации UN/LOCODE…':'Настройка GeoIP…','info');
        try{
            const before=action==='unlocode' ? await syncState() : null;
            const data=new FormData(form);
            data.set('_wg_ajax','1');
            const result=await window.WireGuardTransport.requestJson(form.action,{
                method:'POST',credentials:'same-origin',
                headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},
                body:new URLSearchParams(data).toString()
            },{requireOk:true});
            if(!result.ok)throw new Error(result.error||'Ошибка операции');
            if(action==='unlocode'){
                showStatus('UN/LOCODE: задание запущено, ожидание завершения…','info');
                void followUnlocode(before);
            }else{
                await refreshTable();
                showStatus('Настройки GeoIP и таблица обновлены','success');
            }
        }catch(error){showStatus(error.message||String(error),'danger');}
        finally{if(submit)busy(submit,false);}
    });
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
        const seq=++tableSequence;
        table.setAttribute('aria-busy','true');
        showStatus('Обновление таблицы…','info');
        try{
            // Read only: rendering the current table must never repeat a POST.
            const url=new URL(window.location.href);
            url.search='';
            const response=await fetch(url.toString(),{
                method:'GET',credentials:'same-origin',cache:'no-store',signal,
                headers:{'X-Requested-With':'XMLHttpRequest'}
            });
            if(!response.ok)throw new Error('Не удалось обновить таблицу: HTTP '+response.status);
            const documentCopy=new DOMParser().parseFromString(await response.text(),'text/html');
            const updated=documentCopy.querySelector('[data-wg-network-table]');
            if(!updated)throw new Error('В ответе отсутствует таблица сетей');
            if(seq!==tableSequence || signal?.aborted)return;
            table.replaceChildren(...Array.from(updated.children).map(node=>node.cloneNode(true)));
            // Refresh status/configuration blocks without replacing the editor
            // or installing duplicate listeners on newly rendered controls.
            for(const selector of ['[data-wg-unlocode-meta]','[data-wg-geoip-meta]']){
                const current=root.querySelector(selector);
                const fresh=documentCopy.querySelector(selector);
                if(current&&fresh)current.replaceWith(fresh.cloneNode(true));
            }
            decorateCountries();
            showStatus('Таблица обновлена','success');
        }catch(error){
            if(seq===tableSequence&&!signal?.aborted)showStatus(error.message||String(error),'danger');
            throw error;
        }finally{
            if(seq===tableSequence)table.removeAttribute('aria-busy');
        }
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
                cancel.addEventListener('click',()=>{confirmation.hidden=true;if(pending===controller)pending=null;});
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
                        if(pending===controller)pending=null;
                    }
                });
            }catch(error){
                if(!controller.signal.aborted){
                    output.replaceChildren();
                    add('p',error.message||String(error),output);
                }
            }finally{
                busy(trigger,false);
                // Keep this controller active while the confirmation is displayed.
                // The commit and table refresh are part of the same operation.
                if(controller.signal.aborted && pending===controller)pending=null;
            }
        });
        dialog.addEventListener('click',event=>{
            if(event.target===dialog)closeDialog();
        });
        root.addEventListener('keydown',event=>{
            if(event.key==='Escape'&&!dialog.hidden)closeDialog();
        });
    }
    function decorateCountries(){
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
    }
    decorateCountries();
})();
</script>
NETWORK_UI
    # Safe insertion of a JSON-encoded string without an interpolating heredoc.
    # In particular, JavaScript /...$/ must survive Perl's $/ interpolation.
    $html =~ s/__WG_PAGE_ID__/$js_page_id/g;
    return $html;
}

1;
