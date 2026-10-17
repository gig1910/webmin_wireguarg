=head1 network-icons-ui-lib.pl

Manual network icon editing and country badge rendering.
No network requests or module mutations occur in this browser controller.

=cut

sub wg_network_icons_page_script
{
    return <<'NETWORK_UI';
<style>
.wg-network-form{display:flex;gap:10px;align-items:end;flex-wrap:wrap}
.wg-network-form label{display:inline-flex;flex-direction:column;gap:4px}
.wg-network-edit-link{padding:0;border:0;background:none;color:inherit;text-decoration:underline;
    text-underline-offset:2px;cursor:pointer;font:inherit}
.wg-network-edit-link:hover,.wg-network-edit-link:focus{color:var(--link-color,#5bc0de)}
</style>
<script>
(function(){
    'use strict';
    const editor=document.getElementById('wg-network-editor');
    if(!editor)return;
    const cidr=editor.querySelector('[name="cidr"]');
    const icon=editor.querySelector('[name="icon"]');
    const label=editor.querySelector('[name="label"]');
    document.querySelectorAll('[data-wg-edit-range]').forEach(function(button){
        button.addEventListener('click',function(){
            cidr.value=button.dataset.cidr||'';
            icon.value=button.dataset.icon||'?';
            label.value=button.dataset.label||'';
            editor.scrollIntoView({behavior:'smooth',block:'center'});
            icon.focus({preventScroll:true});
        });
    });
    function flagFor(code){
        return String.fromCodePoint(...Array.from(code,c=>127397+c.charCodeAt(0)));
    }
    document.querySelectorAll('[data-wg-geoip-codes]').forEach(function(node){
        const codes=(node.dataset.wgGeoipCodes||'').split(',').map(s=>s.trim().toUpperCase())
            .filter(s=>/^[A-Z]{2}$/.test(s));
        node.textContent=codes.map(code=>flagFor(code)+' '+code).join(', ');
    });
    document.querySelectorAll('[data-wg-country]').forEach(function(node){
        const code=(node.dataset.wgCountry||'').trim().toUpperCase();
        if(!/^[A-Z]{2}$/.test(code))return;
        const flag=flagFor(code);
        node.textContent=flag+' '+code;
    });
})();
</script>
NETWORK_UI
}

1;
