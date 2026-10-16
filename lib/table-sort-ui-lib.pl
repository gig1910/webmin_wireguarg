=head1 table-sort-ui-lib.pl

Shared accessible column sorting for WireGuard Webmin tables.

=cut

sub wg_table_sort_script
{
    return <<'SORTABLE';
<style>
.wg-sort-button{background:transparent;border:0;color:inherit;font:inherit;font-weight:inherit;
text-align:left;display:inline-flex;gap:5px;align-items:center;cursor:pointer;padding:0}
.wg-sort-button:hover{text-decoration:underline}
.wg-sort-button:focus-visible{outline:2px solid currentColor;outline-offset:2px}
.wg-sort-arrow{font-size:.85em;opacity:.75}
</style>
<script>
(function(){
'use strict';
if(window.WireGuardTableSort&&window.WireGuardTableSort.version===1)return;
const collator=new Intl.Collator(undefined,{numeric:true,sensitivity:'base'});
const unit={B:1,KiB:1024,MiB:1048576,GiB:1073741824,TiB:1099511627776};
function bytes(t){
  const m=String(t||'').trim().match(/^([\d.,]+)\s*(B|KiB|MiB|GiB|TiB)/i);
  if(!m)return null;
  const u=Object.keys(unit).find(k=>k.toLowerCase()===m[2].toLowerCase());
  const n=Number(m[1].replace(',','.'));
  return Number.isFinite(n)&&u?n*unit[u]:null;
}
function ip(t){
  t=String(t||'').split(',')[0].trim().split('/')[0].trim();
  if(t.startsWith('['))t=t.slice(1).split(']')[0];
  else if(t.split(':').length===2)t=t.split(':')[0];
  const a=t.split('.');
  if(a.length===4&&a.every(v=>/^\d{1,3}$/.test(v)&&Number(v)<=255))
    return [4,...a.map(Number)];
  if(!t.includes(':')||!/^[\da-f:]+$/i.test(t))return null;
  const halves=t.toLowerCase().split('::');
  if(halves.length>2)return null;
  const left=halves[0]?halves[0].split(':'):[];
  const right=halves.length===2&&halves[1]?halves[1].split(':'):[];
  if(left.concat(right).some(v=>!/^[a-f\d]{1,4}$/.test(v))||
      (halves.length===1&&left.length!==8)||
      (halves.length===2&&left.length+right.length>=8))return null;
  const middle=halves.length===2?Array(8-left.length-right.length).fill('0'):[];
  return [6,...left.concat(middle,right).map(v=>parseInt(v,16))];
}
function compare(a,b,kind){
  if(kind==='ip'||kind==='endpoint'){
    if(!a||!b)return a?(b?0:-1):(b?1:0);
    for(let i=0;i<Math.max(a.length,b.length);i++){
      const n=(a[i]||0)-(b[i]||0);if(n)return Math.sign(n);
    }return 0;
  }
  if(a==null||a==='')return b==null||b===''?0:1;
  if(b==null||b==='')return -1;
  if(typeof a==='number'&&typeof b==='number')return Math.sign(a-b);
  return collator.compare(String(a),String(b));
}
function value(row,i,kind){
  const cell=row.cells[i];if(!cell)return null;
  const t=cell.textContent.trim();
  if(kind==='name')return (cell.querySelector('a')||cell).textContent.trim();
  if(kind==='state'){
    const el=cell.querySelector('[data-wg-peer-state]');
    return el?(el.dataset.disabled==='1'?0:1):t;
  }
  if(kind==='ip'||kind==='endpoint')return ip(t);
  if(kind==='handshake'){
    const el=cell.querySelector('[data-wg-handshake]');
    return el&&Number(el.dataset.sortEpoch)>0?Number(el.dataset.sortEpoch):null;
  }
  if(kind==='bytes'){
    const el=cell.querySelector('[data-wg-rx],[data-wg-tx]');
    return el&&el.dataset.sortBytes!==undefined&&el.dataset.sortBytes!==''
      ?Number(el.dataset.sortBytes):bytes(t);
  }
  if(kind==='time'){
    const d=t.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4}),?\s+(\d{1,2}):(\d\d)(?::(\d\d))?/);
    return d?new Date(+d[3],+d[2]-1,+d[1],+d[4],+d[5],+(d[6]||0)).getTime():Date.parse(t);
  }
  return t;
}
function attach(wrapper,kinds){
  const table=wrapper&&wrapper.querySelector('table');
  if(!table)return null;
  const header=table.querySelector('thead tr')||table.rows[0];
  if(!header||header.cells.length<kinds.length)return null;
  const original=new WeakMap();let next=0,column=-1,reverse=false;
  const headings=Array.from(header.cells);
  function apply(){
    if(column<0)return;
    const rows=Array.from(table.rows).filter(r=>r!==header&&r.cells.length>=kinds.length);
    for(const row of rows)if(!original.has(row))original.set(row,next++);
    rows.sort((a,b)=>{
      const c=compare(value(a,column,kinds[column]),value(b,column,kinds[column]),kinds[column]);
      return c?(reverse?-c:c):original.get(a)-original.get(b);
    });
    for(const row of rows)row.parentNode.appendChild(row);
  }
  headings.forEach((th,i)=>{
    if(!kinds[i]||kinds[i]==='actions')return;
    const title=th.textContent.trim();th.textContent='';
    const button=document.createElement('button');
    button.type='button';button.className='wg-sort-button';
    button.setAttribute('aria-label',title);button.append(document.createTextNode(title));
    const arrow=document.createElement('span');
    arrow.className='wg-sort-arrow';arrow.textContent='↕';
    arrow.setAttribute('aria-hidden','true');button.append(arrow);th.append(button);
    th.setAttribute('aria-sort','none');
    button.addEventListener('click',()=>{
      if(column===i)reverse=!reverse;else{column=i;reverse=false;}
      headings.forEach((cell,j)=>{
        cell.setAttribute('aria-sort',column===j?(reverse?'descending':'ascending'):'none');
        const span=cell.querySelector('.wg-sort-arrow');
        if(span)span.textContent=column===j?(reverse?'▼':'▲'):'↕';
      });apply();
    });
  });
  return {apply};
}
window.WireGuardTableSort={version:1,attach,ip};
})();
</script>
SORTABLE
}

1;
