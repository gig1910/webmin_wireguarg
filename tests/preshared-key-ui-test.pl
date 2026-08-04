#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text, %in, $WG_PSK_ORIGINAL_UI_TABLE_ROW);
$config{'wg_cmd'} = "$FindBin::Bin/bin/wg";
require "$FindBin::Bin/../wireguard-lib.pl";

local $WG_PSK_ORIGINAL_UI_TABLE_ROW = sub {
    my ($label, $value) = @_;
    return '<tr><th>'.$label.'</th><td>'.$value.'</td></tr>';
};

{
    no warnings qw(redefine once);
    local *main::ui_checkbox = sub {
        my ($name, $value, $label) = @_;
        return '<label><input type="checkbox" name="'.$name.'" value="'.$value.'">'.$label.'</label>';
    };
    local $text{'peer_title'} = 'Пир';

    my $configured = preshared_key_form_rows_for_state(1);
    die "concise configured PresharedKey status missing\n"
        if ($configured !~ /alert-success/ || $configured !~ />Установлен</);
    die "configured PresharedKey status contains redundant explanation\n"
        if ($configured =~ /Сохранённое значение|Для этого пира установлен/);
    die "configured PresharedKey remove button missing\n"
        if ($configured !~ /type="submit"/ || $configured !~ /name="remove_preshared_key"/);
    die "configured PresharedKey still shows creation controls\n"
        if ($configured =~ /name="preshared_key"/ || $configured =~ /generate_preshared_key/);

    my $missing = preshared_key_form_rows_for_state(0);
    die "missing PresharedKey input not shown\n"
        if ($missing !~ /type="password"/ || $missing !~ /name="preshared_key"/);
    die "missing PresharedKey generation option not shown\n"
        if ($missing !~ /name="generate_preshared_key"/);
    die "missing PresharedKey incorrectly shows remove action\n"
        if ($missing =~ /name="remove_preshared_key"/);
}

print "PresharedKey UI state tests passed\n";
