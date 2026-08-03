#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

sub slurp {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "$path: $!\n";
    local $/;
    my $data = <$fh>;
    close($fh);
    return $data;
}

my $interface = slurp("$FindBin::Bin/../edit_interface.cgi");
die "peer actions column missing\n" if $interface !~ /interface_peer_actions/;
die "enabled peer color marker missing\n" if $interface !~ /label-success wg-peer-state-enabled/;
die "disabled peer color marker missing\n" if $interface !~ /label-default wg-peer-state-disabled/;
die "peer row toggle control missing\n" if $interface !~ /wg-peer-toggle/;
die "peer row toggle is not a non-submitting button\n" if $interface !~ /type=\"button\"[^>]+data-peer-toggle-button/;
die "peer row toggle does not send POST\n" if $interface !~ /method:\s*'POST'/;
die "peer row toggle does not use an explicit action URL\n" if $interface !~ /data-action-url/;
die "legacy toggle form still present\n" if $interface =~ /ui_form_start\('toggle_peer\.cgi'/;
die "deactivation confirmation missing\n" if $interface !~ /confirmPeerDisable/;
die "runtime refresh after toggle missing\n" if $interface !~ /poller\.tick/;

my $peer_page = slurp("$FindBin::Bin/../edit_peer.cgi");
die "peer detail toggle is not a non-submitting button\n" if $peer_page !~ /id=\"wg-peer-toggle-detail\"/;
die "peer detail toggle does not send POST\n" if $peer_page !~ /method:\s*'POST'/;
die "peer detail still contains legacy toggle form\n" if $peer_page =~ /ui_form_start\('toggle_peer\.cgi'/;

my $toggle = slurp("$FindBin::Bin/../toggle_peer.cgi");
die "peer toggle does not persist configuration\n" if $toggle !~ /atomic_write_config/;
die "peer toggle does not apply runtime configuration\n" if $toggle !~ /action_apply_interface/;
die "peer toggle does not use AJAX JSON response\n" if $toggle !~ /application\/json/;
die "peer toggle has no rollback on runtime failure\n" if $toggle !~ /original_contents/ || $toggle !~ /rollback/;

my ($block) = $interface =~ /print <<SCRIPT;\n(.*?)\nSCRIPT/s;
die "interface JavaScript block missing\n" if !defined $block;
my ($script) = $block =~ m{<script>\s*(.*?)\s*</script>}s;
die "interface JavaScript content missing\n" if !defined $script;
$script =~ s/\$js_[A-Za-z0-9_]+/"test"/g;

my $node = `command -v node 2>/dev/null`;
chomp($node);
if ($node) {
    my $path = "$FindBin::Bin/peer-list-actions-$$.js";
    open(my $fh, '>', $path) or die $!;
    print {$fh} $script;
    close($fh);
    system($node, '--check', $path) == 0 or die "peer list JavaScript syntax check failed\n";
    unlink($path);
}

print "peer list state and action tests passed\n";
