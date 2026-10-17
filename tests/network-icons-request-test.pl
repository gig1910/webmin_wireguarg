#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

sub slurp {
    open(my $fh,'<',$_[0]) or die "$_[0]: $!";
    local $/;
    return <$fh>;
}

# Exercise the actual CGI mutation dispatch, not a reimplementation of it.
my $source=slurp("$FindBin::Bin/../network_icons.cgi");
my ($dispatch)=$source=~/(\Qmy $notice='';\E.*?)(?=\Qmy ($report,$err)=\E)/s;
die "Cannot isolate network directory mutation dispatch\n" unless defined $dispatch;
die "Missing mandatory CSRF gate\n" unless $dispatch =~ /assert_post_and_csrf\(\)/;
die "Missing explicit mutation-action guard\n" unless $dispatch =~ /if \(length\(\$action\)\)/;

our (%in,%text);
$text{'network_icons_invalid'}='Invalid operation';
$text{'network_icons_saved'}='Saved';
my ($csrf_checks,$write_calls,$rate_calls)=(0,0,0);
my $csrf_valid=0;

sub assert_post_and_csrf {
    ++$csrf_checks;
    die "CSRF denied\n" unless ($ENV{'REQUEST_METHOD'}||'GET') eq 'POST' && $csrf_valid;
}
sub request_rate_limit { ++$rate_calls; }
sub analytics_backend {
    my ($method,$payload)=@_;
    ++$write_calls;
    die "Incorrect backend operation" unless $method eq 'network_manage';
    return ({ok=>1},undef);
}
sub error { die "Request rejected: ".($_[0]||'error')."\n" }

my $dispatch_fn=eval "sub { $dispatch return 1; }";
die "Could not compile CGI dispatch: $@\n" if !$dispatch_fn;

sub run_case {
    my ($method,$params,$allow)=@_;
    local $ENV{'REQUEST_METHOD'}=$method;
    local %in=%$params;
    $csrf_valid=$allow;
    my ($prior_checks,$prior_writes,$prior_rate)=($csrf_checks,$write_calls,$rate_calls);
    my $ok=eval { $dispatch_fn->(); 1 };
    return {
        ok=>$ok,
        error=>$@,
        checks=>$csrf_checks-$prior_checks,
        writes=>$write_calls-$prior_writes,
        rate=>$rate_calls-$prior_rate,
    };
}
my $read_get=run_case('GET',{},0);
die "GET directory view unexpectedly requires CSRF or mutates the cache\n"
    unless $read_get->{ok} && !$read_get->{checks} && !$read_get->{writes};
my $nav=run_case('POST',{navigation=>'1',_wg_api=>'0.2.0+fixture'},0);
die "Authentic Theme read-only navigation POST was rejected or wrote data\n"
    unless $nav->{ok} && !$nav->{checks} && !$nav->{writes} && !$nav->{rate};
my $blocked=run_case('POST',{action=>'set_icon',cidr=>'203.0.113.0/24'},0);
die "CSRF-less mutation passed or reached the backend\n"
    if $blocked->{ok} || $blocked->{checks}!=1 || $blocked->{writes};
my $get_mutation=run_case('GET',{action=>'clear_cache',confirm=>'CLEAR'},1);
die "Mutation over GET reached backend or skipped POST/CSRF gate\n"
    if $get_mutation->{ok} || $get_mutation->{checks}!=1 || $get_mutation->{writes};
my $accepted=run_case('POST',{
    action=>'set_icon',cidr=>'203.0.113.0/24',icon=>'?',label=>'Sample'
},1);
die "Authorized POST cannot update network icon\n"
    unless $accepted->{ok} && $accepted->{checks}==1 &&
           $accepted->{writes}==1 && $accepted->{rate}==1;
my $invalid=run_case('POST',{action=>'evil'},1);
die "Unsupported network mutation reached backend\n"
    if $invalid->{ok} || $invalid->{writes};

print "network directory navigation and mutation CSRF regression tests passed\n";
