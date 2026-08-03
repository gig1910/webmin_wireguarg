#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
sub slurp { my ($p)=@_; open(my $f,'<',$p) or die "$p: $!\n"; local $/; my $d=<$f>; close($f); return $d; }
for my $file (qw(toggle_peer.cgi save_peer.cgi delete_peer.cgi)) {
    my $data = slurp("$FindBin::Bin/../$file");
    die "$file does not invalidate runtime cache\n" if $data !~ /runtime_snapshot_path\(\)/ || $data !~ /unlink\(\$runtime_path\)/;
}
my $toggle=slurp("$FindBin::Bin/../toggle_peer.cgi");
die "toggle invalidates cache before apply\n" if index($toggle,'unlink($runtime_path)') < index($toggle,'action_apply_interface');
die "toggle response lacks invalidation status\n" if $toggle !~ /runtime_cache_invalidated/;
my $save=slurp("$FindBin::Bin/../save_peer.cgi");
die "new peer does not return to table\n" if $save !~ /\$is_new\s*&&\s*\$apply_ok[\s\S]+redirect\('edit_interface\.cgi\?name='/;
die "save redirects before cache invalidation\n" if index($save,'redirect(') < index($save,'unlink($runtime_path)');
my $delete=slurp("$FindBin::Bin/../delete_peer.cgi");
die "delete does not return to table\n" if $delete !~ /redirect\('edit_interface\.cgi\?name='/;
die "delete redirects before cache invalidation\n" if index($delete,'redirect(') < index($delete,'unlink($runtime_path)');
print "peer CRUD runtime cache invalidation tests passed\n";
