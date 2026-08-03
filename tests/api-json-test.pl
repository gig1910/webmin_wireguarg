#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
use JSON::PP qw(decode_json);
our (%config, %text, $module_name);
$module_name = 'wireguard';
require "$FindBin::Bin/../wireguard-lib.pl";

sub main::urlize {
    my ($v) = @_;
    $v = '' if !defined($v);
    $v =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X', ord($1))/eg;
    return $v;
}

my $url = module_script_url('runtime.cgi', name => 'wg0');
die "bad API URL: $url\n" if $url ne '/wireguard/runtime.cgi?_wg_api=1.0.0&name=wg0';

my $output = '';
{
    open(my $capture, '>', \$output) or die $!;
    local *STDOUT = $capture;
    json_response({ ok => JSON::PP::false(), error => 'cache missing' }, '503 Service Unavailable');
}
die "JSON response contains CGI Status header\n" if $output =~ /^Status:/m;
die "JSON content type missing\n" if $output !~ /Content-Type: application\/json; charset=utf-8/;
die "API build header missing\n" if $output !~ /X-WireGuard-Webmin-API: 1\.0\.0/;
my ($headers, $body) = split(/\r?\n\r?\n/, $output, 2);
die "JSON body missing\n" if !defined($body);
my $decoded = decode_json($body);
die "JSON error payload mismatch\n" if $decoded->{ok} || $decoded->{error} ne 'cache missing';

print "API URL and JSON transport tests passed\n";
