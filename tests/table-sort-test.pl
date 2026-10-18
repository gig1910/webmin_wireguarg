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
die "NULL comparator missing\n"
    unless $html =~ /function missing\(v\)/ &&
           $html =~ /if\(missing\(a\)\)return missing\(b\)\?0:1/;
die "NULL-last sorting must precede direction reversal\n"
    unless $html =~ /if\(am!==bm\)return am\?1:-1/;
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

const cases=[
  ['10.0.0.2',[4,10,0,0,2]],
  ['10.0.0.10:51820',[4,10,0,0,10]],
  ['10.0.0.2/24',[4,10,0,0,2]],
  ['::1',[6,0,0,0,0,0,0,0,1]],
  ['2001:db8::2',[6,8193,3512,0,0,0,0,0,2]],
  ['2001:db8::10/64',[6,8193,3512,0,0,0,0,0,16]],
  ['[2001:db8::2]:51820',[6,8193,3512,0,0,0,0,0,2]],
  ['[::1]:51820',[6,0,0,0,0,0,0,0,1]],
];
for(const [input,expected] of cases)
  if(!eq(parse(input),expected))
    throw new Error('IP sort regression '+input+': '+JSON.stringify(parse(input)));
for(const input of ['256.1.1.1','2001:db8:::1','[2001:db8::1','not an IP'])
  if(parse(input)!==null)throw new Error('Malformed IP accepted: '+input);
if(sort.compare(parse('10.0.0.2'),parse('10.0.0.10'),'ip')>=0)
  throw new Error('IPv4 numeric sort incorrect');
if(sort.compare(parse('2001:db8::2'),parse('2001:db8::10'),'ip')>=0)
  throw new Error('IPv6 numeric sort incorrect');
if(sort.compare(parse('10.0.0.2'),parse('::1'),'ip')>=0)
  throw new Error('IPv4/IPv6 ordering inconsistent');

// The base comparator orders NULL after real values; row sorting must retain
// this order when descending as well.
for(const kind of ['time','handshake','bytes','ip','endpoint','name']){
  const present=kind==='ip'||kind==='endpoint'?[4,10,66,66,2]:12345;
  if(sort.compare(null,present,kind)!==1)
      throw new Error('NULL must be highest: '+kind);
  if(sort.compare(present,null,kind)!==-1)
      throw new Error('Present value must precede NULL: '+kind);
  if(sort.compare(null,null,kind)!==0)
      throw new Error('Identical NULL values should be stable: '+kind);
  if(!sort.missing(null) || sort.missing(0))
      throw new Error('Missing-value detection failed: '+kind);
}
// Table rows are built as text nodes, never parsed as HTML.
global.document={
  createElement(tag){
    return {
      tagName:tag.toUpperCase(),textContent:'',children:[],
      append(node){this.children.push(node)},
      get cells(){return this.children}
    };
  }
};
const body={rows:[],append(row){this.rows.push(row)}};
const dangerous='<img src=x onerror=alert(1)>';
const safeRow=sort.appendTextRow(body,['Name',dangerous,0,null]);
if(body.rows.length!==1||safeRow.cells.length!==4)
  throw new Error('Shared row factory produced incorrect table structure');
if(safeRow.cells[1].textContent!==dangerous||safeRow.cells[1].children.length!==0)
  throw new Error('Untrusted cell content was treated as markup');
if(safeRow.cells[2].textContent!=='0'||safeRow.cells[3].textContent!=='')
  throw new Error('Row factory must preserve numeric zero and empty null');
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
