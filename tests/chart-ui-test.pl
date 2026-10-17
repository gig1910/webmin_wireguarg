#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);

require "$FindBin::Bin/../lib/chart-ui-lib.pl";
my $markup=wg_chart_ui_script();
my ($js)=$markup=~m{<script>\s*(.*?)\s*</script>}s;
die "chart component did not return JavaScript\n" unless $js;

sub read_source {
    my ($path)=@_;
    open(my $fd,'<',"$FindBin::Bin/../$path") or die $!;
    local $/; return <$fd>;
}
for my $item (
    ['analytics.cgi', qr/print wg_chart_ui_script\(\)/],
    ['lib/analytics-page-ui-lib.pl', qr/WireGuardChart\.niceLimit/],
    ['lib/peer-usage-ui-lib.pl', qr/WireGuardChart\.formatBytes/],
    ['lib/peer-usage-ui-lib.pl', qr/WireGuardChart\.niceLimit/],
    ['lib/metrics-lib.pl', qr/WireGuardChart\.themeColors/],
    ['lib/metrics-lib.pl', qr/WireGuardChart\.niceLimit/],
) {
    my ($path,$pattern)=@$item;
    die "Shared graph component not used by $path\n"
        unless read_source($path)=~$pattern;
}
my $manifest=read_source('MANIFEST.wbm');
die "chart component is missing from WBM\n"
    unless $manifest=~/^lib\/chart-ui-lib\.pl$/m;

my $node=qx(command -v node 2>/dev/null);
$node=~s/[\r\n]+\z//;
if($node) {
    my ($fh,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$fh} <<"JS_SETUP";
global.window={};
global.document={documentElement:{}};
global.getComputedStyle=()=>({
 color:'#999',
 getPropertyValue:(name)=>({
  '--primary-color':'#123456',
  '--success-color':'#abcdef'
 })[name]||''
});
$js
JS_SETUP
    print {$fh} <<'CHECKS';
const c=window.WireGuardChart;
if(!c || !Object.isFrozen(c))throw new Error('Shared chart object unavailable');
const equal=(actual,expected)=>{if(actual!==expected)
  throw new Error('Expected '+expected+', got '+actual);};
equal(c.formatBytes(0,false),'0 B');
equal(c.formatBytes(1536,false),'1.50 KiB');
equal(c.formatBytes(1536,true),'1.50 KiB/s');
equal(c.formatBytes(1024*1024,false),'1.00 MiB');
equal(c.formatBytes(-1,false),'—');
equal(c.formatBytes(null,false),'—');
equal(c.formatBytes(Infinity,true),'—');
equal(c.niceLimit(0),1024);
equal(c.niceLimit(1536),2048);
equal(c.niceLimit(3100),4096);
equal(c.themeColors().tx,'#123456');
equal(c.themeColors().rx,'#abcdef');
equal(c.themeColors().text,'#999');
// Repeat the script, as several charts may coexist on one Webmin page.
CHECKS
    print {$fh} "$js\n";
    print {$fh} <<'IDEMPOTENCE';
if(window.WireGuardChart!==c)
  throw new Error('Shared component must preserve identity on repeated injection');
console.log('shared chart primitives and repeated-script tests passed');
IDEMPOTENCE
    close($fh);
    system($node,'--check',$path)==0 or die "chart JavaScript invalid\n";
    system($node,$path)==0 or die "chart primitive behavior invalid\n";
}
print "shared chart UI integration passed\n";
