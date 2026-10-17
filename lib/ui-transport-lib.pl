=head1 ui-transport-lib.pl

Read-only browser transport helpers. Distinct polling, cancellation and
authorization policies remain with the calling page controllers.

=cut

sub wg_ui_transport_script
{
    return <<'WG_UI_TRANSPORT';
<script>
(function(){
    'use strict';
    if(window.WireGuardTransport&&window.WireGuardTransport.version===1)return;
    function snippet(body){
        return String(body||'').replace(/\s+/g,' ').trim().slice(0,240);
    }
    async function readJson(response,options){
        const config=options||{};
        const body=await response.text();
        const type=(response.headers.get('content-type')||'').toLowerCase();
        if(!type.includes('application/json')){
            const error=new Error('HTTP '+response.status+': сервер вернул не JSON ('+
                (type||'без Content-Type')+')'+(snippet(body)?': '+snippet(body):''));
            error.nonJson=true;
            throw error;
        }
        let data;
        try{data=JSON.parse(body);}
        catch(parseError){
            const error=new Error('Некорректный JSON-ответ'+
                (snippet(body)?': '+snippet(body):''));
            error.nonJson=true;
            throw error;
        }
        if(config.requireOk && (!data || data.ok!==true)){
            throw new Error(data&&data.error || ('HTTP '+response.status));
        }
        return data;
    }
    function requestOptions(extra){
        const options=Object.assign({
            credentials:'same-origin',cache:'no-store',redirect:'error',
            headers:{Accept:'application/json','X-Requested-With':'XMLHttpRequest'}
        },extra||{});
        options.headers=Object.assign({
            Accept:'application/json','X-Requested-With':'XMLHttpRequest'
        },extra&&extra.headers||{});
        return options;
    }
    async function requestJson(url,options,decodeOptions){
        const response=await fetch(url,requestOptions(options));
        return readJson(response,decodeOptions);
    }
    window.WireGuardTransport=Object.freeze({
        version:1,readJson,requestOptions,requestJson
    });
})();
</script>
WG_UI_TRANSPORT
}

1;
