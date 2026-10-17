=head1 chart-ui-lib.pl

Common, side-effect-free chart primitives. Rendering and data ownership remain
with live traffic, peer history and long-term analytics respectively.

=cut

sub wg_chart_ui_script
{
    return <<'CHART_UI';
<script>
(function(){
 'use strict';
 if(window.WireGuardChart)return;
 const units=['B','KiB','MiB','GiB','TiB'];
 function formatBytes(value,rate){
   if(value===null||value===undefined||!Number.isFinite(Number(value)))return '—';
   let n=Number(value);
   if(n<0)return '—';
   let i=0;
   while(n>=1024&&i<units.length-1){n/=1024;i++;}
   return (i===0||n>=100?n.toFixed(0):n>=10?n.toFixed(1):n.toFixed(2))+
       ' '+units[i]+(rate?'/s':'');
 }
 function themeColors(){
   const style=getComputedStyle(document.documentElement);
   return {
     tx:style.getPropertyValue('--primary-color').trim()||'#4f8dd6',
     rx:style.getPropertyValue('--success-color').trim()||'#42a878',
     text:style.color||'#aaa',
     grid:'rgba(127,127,127,.22)',
     zero:'rgba(190,190,190,.8)'
   };
 }
 function niceLimit(value){
   const max=Math.max(1024,Number.isFinite(Number(value))?Number(value):1024);
   const power=Math.pow(1024,Math.floor(Math.log(max)/Math.log(1024)));
   const scaled=Math.ceil(max/power);
   const tickStep=scaled<=2?0.5:scaled<=5?1:2;
   return Math.max(power,Math.ceil(scaled/tickStep)*tickStep*power);
 }
 window.WireGuardChart=Object.freeze({formatBytes,themeColors,niceLimit});
})();
</script>
CHART_UI
}

1;
