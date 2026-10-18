#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use Cwd qw(getcwd);
our %text = (
    wg_build_label => 'Installed build', wg_build_unstamped => 'Unstamped',
    wg_build_commit => 'Commit', wg_build_date => 'Built',
    wg_build_dirty => 'Local changes',
);
sub html_escape {
    my $x=shift; $x='' if !defined $x;
    $x =~ s/&/&amp;/g; $x =~ s/</&lt;/g;
    $x =~ s/>/&gt;/g; $x =~ s/"/&quot;/g;
    return $x;
}
require "$FindBin::Bin/../lib/version-lib.pl";
my $orig=getcwd();
my $dir=tempdir(CLEANUP=>1);
chdir($dir) or die $!;
my $base=wg_build_version();
die "development version mismatch" if $base ne '0.3.0';
die "unstamped build not shown" unless wg_build_banner() =~ /Unstamped/;
open(my $fh,'>','build.info') or die $!;
print {$fh} "build_version=0.3.0+20261015163000123456789.g0123456789ab\n";
print {$fh} "git_commit=".'0123456789abcdef' x 2 . '01234567'."\n";
print {$fh} "built_at_utc=2026-10-15T16:30:00Z\n";
print {$fh} "source_dirty=1\n";
close($fh);
my $expected='0.3.0+20261015163000123456789.g0123456789ab';
die "build identity not read" if wg_build_version() ne $expected;
my $html=wg_build_banner();
die "build identity not rendered" unless $html =~ /\Q$expected\E/;
die "dirty state not rendered" unless $html =~ /Local changes/;
die "date missing" unless $html =~ /2026-10-15T16:30:00Z/;
open($fh,'>','build.info') or die $!;
print {$fh} "build_version=<script>alert(1)</script>\ngit_commit=garbage\n";
close($fh);
die "invalid metadata accepted" if wg_build_version() ne $base;
die "unsafe markup leaked" if wg_build_banner() =~ /<script>/;
chdir($orig) or die $!;
my $manifest=do {open my $m,'<','MANIFEST.wbm' or die $!; local $/; <$m>};
die "build metadata not packaged" unless $manifest =~ /^build\.info$/m;
for my $path (qw(index.cgi edit_interface.cgi edit_peer.cgi analytics.cgi)) {
    open my $f,'<',$path or die $!;local $/;my $source=<$f>;
    die "build banner missing in $path" unless $source =~ /wg_build_banner\(\)/;
}
print "build metadata and installed identity UI tests passed\n";
