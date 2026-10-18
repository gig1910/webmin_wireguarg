#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use JSON::PP qw(encode_json);
require "$FindBin::Bin/node-harness.pl";
require "$FindBin::Bin/../lib/index-page-ui-lib.pl";

my $markup1=wg_index_collector_script(q{"collector-one"},(map { q{"test"} } 1..19));
my $markup2=wg_index_collector_script(q{"collector-two"},(map { q{"test"} } 1..19));
my ($js1)=$markup1=~m{<script>\s*(.*?)</script>}s;
my ($js2)=$markup2=~m{<script>\s*(.*?)</script>}s;
die "Collector scripts not generated\n" unless $js1 && $js2;
my $js = "const vm=require('vm');\\n" .
    "const first=".encode_json($js1).";\\n" .
    "const second=".encode_json($js2).";\\n" . <<'JS';
const timers=new Map(),pagehide=new Set();
let timerId=0;
global.window=global;
global.document={
  hidden:false,
  getElementById(id){return roots[id]||null}
};
global.setInterval=(fn,delay)=>{const id=++timerId;timers.set(id,fn);return id};
global.clearInterval=id=>timers.delete(id);
window.addEventListener=(event,fn)=>{if(event==='pagehide')pagehide.add(fn)};
window.removeEventListener=(event,fn)=>{if(event==='pagehide')pagehide.delete(fn)};
window.WireGuardTransport={
  async requestJson(){return {ok:true,service:{state:'inactive'},health:{}}}
};
function makeRoot(){
 const events=new Map();
 return {
  isConnected:true,
  dataset:{url:'/wireguard/collector_status.cgi',csrf:'test'},
  listeners:events,
  addEventListener(type,fn){events.set(type,fn)},
  removeEventListener(type,fn){if(events.get(type)===fn)events.delete(type)},
  querySelector(selector){
    if(selector==='[data-role="status"]'||selector==='[data-role="details"]')
      return {textContent:'',className:''};
    return null;
  }
 };
}
const roots={'collector-one':makeRoot(),'collector-two':makeRoot()};
vm.runInThisContext(first);
if(window.__wgCollectorController.root!==roots['collector-one']||
   timers.size!==1||roots['collector-one'].listeners.size!==1)
  throw Error('Initial collector not registered correctly');
vm.runInThisContext(second);
if(window.__wgCollectorController.root!==roots['collector-two']||
   timers.size!==1||roots['collector-one'].listeners.size!==0||
   roots['collector-two'].listeners.size!==1||pagehide.size!==1)
  throw Error('Old collector timer/listener survived SPA navigation');
window.__wgCollectorController.destroy();
if(timers.size!==0||roots['collector-two'].listeners.size!==0||pagehide.size!==0)
  throw Error('Collector lifecycle did not clean up');
console.log('collector SPA lifecycle checks passed');
JS
wg_test_node_script($js, 'collector SPA lifecycle');
print "collector SPA lifecycle tests passed\n";
