#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();
my $state=_state_dir();
my $status_file=File::Spec->catfile($state,'unlocode-status.json');
my $error_file=File::Spec->catfile($state,'unlocode-last-error.txt');
my $status={};
if (-f $status_file && -r $status_file && -s $status_file < 4096) {
    my $value=eval { JSON::PP::decode_json(read_file_contents($status_file)||'') };
    $status=$value if ref($value) eq 'HASH';
}
my $error='';
my $error_mtime=0;
if (-f $error_file && -r $error_file && -s $error_file < 2048) {
    $error=read_file_contents($error_file)||'';
    $error =~ s/[\r\n]+/ /g;
    $error_mtime=(stat($error_file))[9]||0;
}
json_response({
    ok=>JSON::PP::true(),
    updated_at=>0+($status->{'updated_at'}||0),
    entries=>0+($status->{'entries'}||0),
    error=>$error,
    error_mtime=>0+$error_mtime
});
