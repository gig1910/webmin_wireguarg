#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);
require "$FindBin::Bin/../lib/table-sort-ui-lib.pl";
my $html=wg_table_sort_script();
die "local shared sort helper is missing\n"
    unless $html =~ /WireGuardTableSort/ && $html =~ /aria-sort/ &&
           $html =~ /wg-sort-button/ && $html =~ /addEventListener\('click'/;
die "sort by FIRST AllowedIPs address missing\n"
    unless $html =~ /split\(','\)\[0\]/ && $html =~ /split\('\/'\)\[0\]/;
die "numeric IPv4/IPv6 parsing missing\n"
    unless $html =~ /a\.map\(Number\)/ && $html =~ /parseInt\(v,16\)/;
die "runtime numeric sort keys missing\n"
    unless $html =~ /sortBytes/ && $html =~ /sortEpoch/;
die "stable ordering missing\n" unless $html =~ /new WeakMap/;
die "NULL highest-value comparator missing\n"
    unless $html =~ /function missing\(v\)/ &&
           $html =~ /if\(missing\(a\)\)return missing\(b\)\?0:1/;
my ($js)=$html =~ m{<script>\n(.*?)</script>}s;
die "sort helper JavaScript missing\n" unless defined $js;
my $node=qx(command -v node 2>/dev/null);
$node =~ s/[\r\n]+\z//;
if($node){
    my ($fh,$name)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$fh} "global.window={};\n";
    print {$fh} $js;
    print {$fh} <<'CHECKS';
const sort=window.WireGuardTableSort;
const parse=sort.ip;
const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
if(!eq(parse('10.66.66.2/32,192.168.0.0/24'),[4,10,66,66,2]))
    throw new Error('AllowedIPs primary numeric IPv4 mismatch');
if(!eq(parse('10.66.66.10/32'),[4,10,66,66,10]))
    throw new Error('IPv4 numeric comparison mismatch');
if(!eq(parse('[2001:db8::a]:5000'),[6,8193,3512,0,0,0,0,0,10]))
    throw new Error('IPv6 parsing mismatch');
if(parse('(none)')!==null)throw new Error('Invalid IP accepted');
// NULL/"Никогда" is larger than ANY real value for ASC; DESC reverses it.
for(const kind of ['time','handshake','bytes','ip','endpoint','name']){
  const present=kind==='ip'||kind==='endpoint'?[4,10,66,66,2]:12345;
  if(sort.compare(null,present,kind)!==1)
      throw new Error('NULL must be highest: '+kind);
  if(sort.compare(present,null,kind)!==-1)
      throw new Error('Present value must precede NULL: '+kind);
  if(sort.compare(null,null,kind)!==0)
      throw new Error('Identical NULL values should be stable: '+kind);
  if(-sort.compare(null,present,kind)!==-1)
      throw new Error('Descending must invert NULL placement: '+kind);
}
// Missing or invalid date values must normalize to NULL.
const cell=(text,attribute)=>({
  textContent:text,querySelector:()=>attribute||null
});
const row=cell=>({cells:[cell]});
if(sort.value(row(cell('Никогда')) ,0,'time')!==null)
    throw new Error('Russian Never is not NULL');
if(sort.value(row(cell('never')),0,'time')!==null)
    throw new Error('English never is not NULL');
if(sort.value(row(cell('not a date')),0,'time')!==null)
    throw new Error('Invalid time must be NULL, not NaN');
if(sort.value(row(cell('Никогда',{dataset:{sortEpoch:'0'}})),0,'handshake')!==null)
    throw new Error('Handshake epoch 0 must be NULL');
if(sort.value(row(cell('0 B')),0,'bytes')!==0)
    throw new Error('Zero bytes is valid, not NULL');
CHECKS
    close($fh);
    system($node,'--check',$name)==0 or die "sort helper JavaScript invalid\n";
    system($node,$name)==0 or die "IP sort key tests failed\n";
}
print "shared table sorting tests passed\n";
