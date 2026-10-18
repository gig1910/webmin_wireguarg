#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use JSON::PP qw(encode_json);
require "$FindBin::Bin/node-harness.pl";
require "$FindBin::Bin/../lib/index-page-ui-lib.pl";
my $markup1=wg_index_runtime_script(q{"page1"},(map { q{"test"} } 1..4));
my $markup2=wg_index_runtime_script(q{"page2"},(map { q{"test"} } 1..4));
my ($js1)=$markup1=~m{<script>\s*(.*?)</script>}s;
my ($js2)=$markup2=~m{<script>\s*(.*?)</script>}s;
die "Rendered dashboard page scripts missing\n" unless $js1 && $js2;
my $js = "const vm=require('vm');\n" .
    "const js1=".encode_json($js1).";\n" .
    "const js2=".encode_json($js2).";\n" . <<'JS';
const events=new Map();
const roots={
  page1:{isConnected:true,querySelectorAll(){return[]},querySelector(){return null}},
  page2:{isConnected:true,querySelectorAll(){return[]},querySelector(){return null}}
};
global.window=global;
global.CSS={escape:s=>s};
global.document={
  documentElement:{},
  querySelector(sel){return Object.entries(roots).find(([name])=>sel.includes(name))?.[1]||null},
  addEventListener(type,fn){
    if(!events.has(type))events.set(type,new Set());
    events.get(type).add(fn);
  },
  removeEventListener(type,fn){events.get(type)?.delete(fn)},
};
global.MutationObserver=class {
  observe(){}
  disconnect(){}
};
global.window.addEventListener=()=>{};
global.window.removeEventListener=()=>{};
vm.runInThisContext(js1);
if(window.__wgIndexRuntimeController.root!==roots.page1)
  throw Error('First dashboard not bound');
for(const name of ['wg-runtime','wg-runtime-error','wg-runtime-warning']){
  if(events.get(name)?.size!==1)throw Error(name+' not initially bound once');
}
vm.runInThisContext(js2);
if(window.__wgIndexRuntimeController.root!==roots.page2)
  throw Error('New dashboard is not the active controller');
for(const name of ['wg-runtime','wg-runtime-error','wg-runtime-warning']){
  if(events.get(name)?.size!==1)
    throw Error('Stale dashboard listener remained: '+name);
}
window.__wgIndexRuntimeController.destroy();
for(const name of ['wg-runtime','wg-runtime-error','wg-runtime-warning']){
  if(events.get(name)?.size!==0)
    throw Error('Dashboard handler not disposed: '+name);
}
console.log('dashboard SPA listener lifecycle passed');
JS
wg_test_node_script($js, 'dashboard SPA lifecycle');
print "dashboard SPA lifecycle checks passed\n";
