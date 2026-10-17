#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);

require "$FindBin::Bin/../lib/ui-transport-lib.pl";
my $markup=wg_ui_transport_script();
my ($js)=$markup=~m{<script>\s*(.*?)\s*</script>}s;
die "Shared transport markup is missing script\n" if !defined $js;
my $node=qx(command -v node 2>/dev/null);
$node=~s/[\r\n]+\z//;
if($node){
    my ($fd,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$fd} "global.window=global;\n";
    print {$fd} $js."\n".$js."\n";
    print {$fd} <<'JS';
const transport=window.WireGuardTransport;
if(!transport||!Object.isFrozen(transport)||transport.version!==1)
  throw new Error('Transport did not initialize');
const response=(status,type,body)=>({
  status,headers:{get(k){if(k!=='content-type')throw Error('wrong header');return type;}},
  async text(){return body;}
});
(async()=>{
  const result=await transport.readJson(response(200,'application/json; charset=UTF-8','{"ok":true,"x":0}'),{requireOk:true});
  if(!result.ok||result.x!==0)throw Error('JSON content lost');
  const errors=[
    [response(404,'text/html','<html>missing</html>'),true],
    [response(200,'application/json','not json'),true],
    [response(200,'application/json','{"ok":false,"error":"failed"}'),false]
  ];
  for(const [r,nonJson] of errors){
    let error;
    try{await transport.readJson(r,{requireOk:true});}
    catch(e){error=e;}
    if(!error||!!error.nonJson!==nonJson)throw Error('Incorrect error type or nonJson flag');
  }
  const opts=transport.requestOptions({method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'}});
  if(opts.credentials!=='same-origin'||opts.redirect!=='error'||opts.cache!=='no-store'||
     opts.headers.Accept!=='application/json'||opts.headers['Content-Type']!=='application/x-www-form-urlencoded')
    throw Error('Secure request defaults not preserved');
  let called;
  global.fetch=async (url,options)=>{
    called={url,options};
    return response(200,'application/json','{"ok":true,"value":123}');
  };
  let out=await transport.requestJson('/wireguard/mock.cgi',{signal:{abort:false}},{requireOk:true});
  if(out.value!==123||called.options.credentials!=='same-origin'||
     called.options.headers['X-Requested-With']!=='XMLHttpRequest')
     throw Error('Request wrapper lost fetch options');
  if(transport!==window.WireGuardTransport)
     throw Error('Repeated script replaced transport singleton');
  console.log('browser JSON transport contract tests passed');
})().catch(e=>{console.error(e);process.exit(1);});
JS
    close($fd);
    system($node,'--check',$path)==0 or die "Transport JS syntax invalid\n";
    system($node,$path)==0 or die "Transport JS behavior invalid\n";
}
print "shared browser transport checks passed\n";
