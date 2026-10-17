#!/usr/bin/env perl
# Hermetic CGI GET/POST harness for tests/install-dependency-csrf-test.pl.
use strict;
use warnings;
use lib 'tests/stub';
use lib '.';
our (%config,%in);
require './wireguard-lib.pl';
$config{'apt_get_cmd'}=$ENV{'TEST_APT'};
$config{'dpkg_query_cmd'}=$ENV{'TEST_DPKG'};
for my $k (qw(qrencode_cmd geoipupdate_cmd mmdblookup_cmd geoiplookup_cmd whois_cmd)) {
    $config{$k}=$ENV{'TEST_NOT_INSTALLED'}.'/'.$k;
}
{
    no warnings qw(redefine);
    *main::ui_print_header=sub { print "<main>\n"; };
    *main::ui_print_footer=sub { print "</main>\n"; };
    *main::ui_form_start=sub {
        my ($action,$method)=@_;
        return '<form action="'.html_escape($action).'" method="'.html_escape($method).'">'."\n";
    };
    *main::ui_form_end=sub { return "</form>\n"; };
    *main::ui_hidden=sub {
        my ($key,$value)=@_;
        return '<input type="hidden" name="'.html_escape($key).
            '" value="'.html_escape(defined($value) ? $value : '').'">'."\n";
    };
    *main::ui_link_button=sub {
        my ($path,$label)=@_;
        return '<a href="'.html_escape($path).'">'.html_escape($label).'</a>';
    };
    *main::ReadParse=sub {
        my $raw;
        if (($ENV{'REQUEST_METHOD'}||'') eq 'POST') {
            my $bytes=int($ENV{'CONTENT_LENGTH'}||0);
            $raw='';
            while(length($raw)<$bytes) {
                my $part='';
                my $n=read(STDIN,$part,$bytes-length($raw));
                last if !defined($n) || !$n;
                $raw.=$part;
            }
        }
        else { $raw=$ENV{'QUERY_STRING'}||''; }
        %in=();
        for my $pair (split /&/,$raw) {
            my ($k,$v)=split /=/,$pair,2;
            next if !defined($k);
            $v='' if !defined($v);
            for ($k,$v) {
                tr/+/ /;
                s/%([0-9a-fA-F]{2})/chr(hex($1))/eg;
            }
            $in{$k}=$v;
        }
        return 1;
    };
}
do './install_dependency.cgi' or die $@ || $!;
