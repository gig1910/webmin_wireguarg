#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text);
require "$FindBin::Bin/../wireguard-lib.pl";

my $escaped = js_escape("Перезапустить O'Brien \"wg0\" & <test>\nДа");
die "apostrophe was not escaped\n" if $escaped !~ /O\\'Brien/;
die "double quote can break HTML attribute\n" if $escaped =~ /\"wg0\"/;
die "double quote was not HTML escaped\n" if $escaped !~ /&quot;wg0&quot;/;
die "ampersand was not HTML escaped\n" if $escaped !~ /&amp;/;
die "angle bracket was not HTML escaped\n" if $escaped !~ /&lt;test&gt;/;
die "newline was not JavaScript escaped\n" if $escaped !~ /\\n/;
my $link = direct_link_button('client_config.cgi', 'Show config', { name => 'wg0', peer => 1 });
die "direct link is not module-absolute\n" if $link !~ m{href="/wireguard/client_config\.cgi\?[^"]*name=wg0[^"]*peer=1};
die "view link is not marked for normal module navigation\n" if $link !~ /data-wg-module-navigation="1"/;
die "view link forces a top-level document navigation\n" if $link =~ /window\.location\.assign|stopPropagation|stopImmediatePropagation/;
die "direct link reused Authentic Theme clipboard-prone class\n" if $link =~ /ui_link_button/;
my $download = direct_link_button('download_client.cgi', 'Download', { name => 'wg0', peer => 1 }, download => 1);
die "download link lacks download attribute\n" if $download !~ / download/;
die "download link is not isolated from SPA handlers\n" if $download !~ /data-wg-direct-download="1"/ || $download !~ /window\.location\.assign/;
print "UI helper tests passed\n";
