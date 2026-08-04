#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
use JSON::PP qw(decode_json);
our (%config, %text, $module_name);
$module_name = 'wireguard';
require "$FindBin::Bin/../wireguard-lib.pl";

{
    package TestMiniServHandle;
    sub TIEHANDLE { bless { output => '' }, shift }
    sub PRINT {
        my ($self, @parts) = @_;
        $self->{output} .= join('', @parts);
        return 1;
    }
    sub output { return $_[0]->{output}; }
    # Deliberately no BINMODE method. Webmin MiniServ's tied STDOUT does not
    # implement it either, which previously caused runtime.cgi to die.
}

my $tied;
my $output;
{
    local *STDOUT;
    $tied = tie(*STDOUT, 'TestMiniServHandle');
    json_response({ ok => JSON::PP::true(), message => "тест" });
    $output = $tied->output;
    undef $tied;
    untie(*STDOUT);
}

die "JSON content type missing\n" if $output !~ /Content-Type: application\/json; charset=utf-8/;
die "API build header missing\n" if $output !~ /X-WireGuard-Webmin-API: 0\.2\.0/;
my (undef, $body) = split(/\r?\n\r?\n/, $output, 2);
die "JSON body missing\n" if !defined($body);
my $decoded = decode_json($body);
die "JSON payload mismatch\n" if !$decoded->{ok} || $decoded->{message} ne "тест";

print "MiniServ tied-STDOUT JSON test passed\n";
