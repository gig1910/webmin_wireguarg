#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);
require "$FindBin::Bin/../lib/index-page-ui-lib.pl";
require "$FindBin::Bin/../lib/ui-transport-lib.pl";

sub read_file {
    open(my $fh,'<',$_[0]) or die "$_[0]: $!\n";
    local $/; my $s=<$fh>;close($fh);return $s;
}
my $cgi=read_file("$FindBin::Bin/../index.cgi");
die "Dashboard is not wired to extracted controllers\n"
    unless $cgi =~ m{require './lib/index-page-ui-lib.pl'} &&
           $cgi =~ /wg_index_collector_script\(/ &&
           $cgi =~ /wg_index_runtime_script\(/;
die "Transport must load before collector script\n"
    unless index($cgi,"print wg_ui_transport_script()") >= 0 &&
           index($cgi,"print wg_ui_transport_script()") <
           index($cgi,"print wg_index_collector_script(");
my $manifest=read_file("$FindBin::Bin/../MANIFEST.wbm");
die "Dashboard controller not packaged\n"
    unless $manifest =~ /^lib\/index-page-ui-lib\.pl$/m;
my $collector=wg_index_collector_script((map { q{"test"} } 1..20));
my $runtime=wg_index_runtime_script((map { q{"test"} } 1..4));
for my $spec (
    [$collector,qr/data-role="status"/,qr/WireGuardTransport\.requestJson/],
    [$runtime,qr/wg-runtime/,qr/data-wg-orphan/],
) {
    for my $pattern (@$spec[1,2]){
        die "Rendered dashboard JavaScript feature missing\n"
            unless $spec->[0] =~ $pattern;
    }
}
my $node=qx(command -v node 2>/dev/null);
$node=~s/[\r\n]+\z//;
if($node) {
    for my $markup ($collector,$runtime) {
        my ($script)=$markup=~m{<script>\s*(.*?)\s*</script>}s;
        die "Controller HTML has no JavaScript\n" if !defined $script;
        my ($fh,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
        print {$fh} $script;close($fh);
        system($node,'--check',$path)==0 or die "Rendered dashboard JS invalid\n";
    }
}
print "dashboard controller rendering and JavaScript checks passed\n";
