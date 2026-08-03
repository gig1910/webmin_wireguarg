#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text);
require "$FindBin::Bin/../wireguard-lib.pl";

my $dir = tempdir(CLEANUP => 1);
$config{'backup_dir'} = "$dir/backups";
$config{'backup_retention'} = 3;
for my $iteration (1..150) {
    my $path = "$dir/wg0.conf";
    my $tag = join('', map { chr(65 + int(rand(26))) } 1..12);
    my $custom_key = "Custom$iteration";
    my $before_peer2 = "[Peer]\t#Peer-B\nPublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=\nAllowedIPs = 10.9.0.3/32\n# untouched-$tag\n";
    my $conf = "# leading-$tag\n\n[Interface]\nAddress = 10.9.0.1/24\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n#$custom_key = value-$tag\nPostUp = echo one\nPostUp = echo two\n\n[Peer]\t#Peer-A\nPublicKey = CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=\n#PrivateKey = DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD=\nAllowedIPs = 10.9.0.2/32\n# custom-peer-$tag\nUnknownOption = keep-$tag\n\n$before_peer2";
    open(my $fh,'>',$path) or die $!; print {$fh} $conf; close($fh);
    my ($cfg,$err)=parse_wireguard_config($path);
    die "parse failed at $iteration: $err\n" if !$cfg;
    die "peer count changed\n" if @{$cfg->{'peers'}} != 2;
    my $peer=$cfg->{'peers'}->[0];
    my %data=(
      name=>'Peer-A-renamed', private_key=>$peer->{'private_key'}||'',
      public_key=>get_section_value($peer,'PublicKey')||'', clientaddress=>'10.9.0.2/32',
      allowed_ips=>['10.9.0.2/32'], endpoint=>'', keepalive=>'', disabled=>0,
      clientendpoint=>'',clientdns=>'',clientallowedips=>'',clientmtu=>'',
    );
    my $new = replace_section($cfg,$peer,build_peer_block(\%data,$peer));
    die "custom peer comment lost\n" if $new !~ /custom-peer-\Q$tag\E/;
    die "unknown peer option lost\n" if $new !~ /UnknownOption\s*=\s*keep-\Q$tag\E/;
    die "other peer changed\n" if index($new,$before_peer2) < 0;
    die "leading comment lost\n" if $new !~ /^# leading-\Q$tag\E/m;
    my ($ok,$write_error)=atomic_write_config($path,$new,$cfg->{'digest'});
    die "atomic write failed: $write_error\n" if !$ok;
    my ($again,$again_error)=parse_wireguard_config($path);
    die "roundtrip parse failed: $again_error\n" if !$again || @{$again->{'peers'}} != 2;
}

# Structural rejection checks.
my $bad = "$dir/bad.conf";
open(my $badfh,'>',$bad) or die $!;
print {$badfh} "[Interface]\nAddress=10.0.0.1/24\n[Interface]\nAddress=10.1.0.1/24\n";
close($badfh);
my ($badcfg,$baderr)=parse_wireguard_config($bad);
die "multiple Interface sections were accepted\n" if $badcfg;

my $target = "$dir/target.conf";
open(my $tf,'>',$target) or die $!; print {$tf} "[Interface]\nAddress=10.0.0.1/24\n"; close($tf);
my $link = "$dir/link.conf";
symlink($target,$link) or die $!;
my ($linkok)=atomic_write_config($link,"[Interface]\nAddress=10.0.0.2/24\n",undef);
die "symbolic-link write was accepted\n" if $linkok;

print "parser fuzz and preservation tests passed\n";
