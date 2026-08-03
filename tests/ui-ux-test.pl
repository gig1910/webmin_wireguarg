#!/usr/bin/env perl
use strict; use warnings; use FindBin;
sub slurp { open(my $f,'<',$_[0]) or die $!; local $/; my $s=<$f>; close($f); $s }
my $ru=slurp("$FindBin::Bin/../lang/ru");
die "broken back label remains\n" if $ru =~ /Вернуться к\s+(?:Отмена|Вернуться)/;
die "overlong interface restart label remains\n" if $ru =~ /^interface_restart=Полностью/m;
my $index=slurp("$FindBin::Bin/../index.cgi");
die "redundant Open button used in interface list\n" if $index =~ /index_open|interface_peer_open/;
my $peer=slurp("$FindBin::Bin/../edit_peer.cgi");
die "peer editor lacks direct save form\n" if $peer !~ /save_peer\.cgi/;
die "diagnostic Stop is not delegated\n" if $peer =~ /stopButton\.addEventListener/;
my $iface=slurp("$FindBin::Bin/../edit_interface.cgi");
die "peer list still shows client private-key column
" if $iface =~ /interface_peer_private/;
die "peer list row still renders client private-key status
" if $iface =~ /length\(\$peer->\{'private_key'\}/;
die "peer export controls still use theme ui_link_button
" if $peer =~ /ui_link_button\(\s*
?\s*['"](?:client_config|download_client|peer_qr)\.cgi/;
die "peer export controls do not use direct links
" if $peer !~ /direct_link_button\(/;

my $collector=slurp("$FindBin::Bin/../collector_status.cgi");
die "collector status does not query actual systemd service state\n" if $collector !~ /ActiveState,SubState,MainPID/;
die "collector actions do not return command console output\n" if $collector !~ /systemctl status/ || $collector !~ /output => \$output/;
die "collector UI lacks console panel\n" if $index !~ /data-role=\"console\"/;
die "collector UI still infers stopped service only from stale health data\n" if $index !~ /service\.state/ || $index !~ /stoppedText/;
print "UI/UX naming and action tests passed\n";
