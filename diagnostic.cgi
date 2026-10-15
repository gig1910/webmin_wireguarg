#!/usr/local/bin/perl
require './wireguard-lib.pl';
use File::Path qw(make_path remove_tree);
use File::Spec;
use Fcntl qw(:DEFAULT);
use Digest::SHA qw(sha256_hex);
use POSIX qw(setsid _exit);

ReadParse();
assert_view_access();
assert_diagnostics_access();

sub api_fail { my ($message) = @_; json_response({ ok => JSON::PP::false(), error => $message }); exit; }

eval { assert_post_and_csrf(); request_rate_limit('diagnostic', 20, 60); 1 } or api_fail($@ || $text{'action_post'});

my $name = $in{'name'};
api_fail($text{'error_invalid_name'}) if (!valid_interface_name($name));
my $target = _trim($in{'target'} || '');
api_fail($text{'error_target'}) if (!valid_host($target));

my $operation = $in{'operation'} || '';
my @command;
my $infinite = 0;
if ($operation eq 'ping') {
    my $ping = command_path('ping_cmd', '/usr/bin/ping');
    api_fail(text('error_command', $ping)) if (!$ping || !has_command($ping));
    if ($in{'infinite'}) {
        $infinite = 1;
        @command = ($ping, '-W', '3', $target);
    }
    else {
        my $count = int($in{'ping_count'} || 3);
        $count = 1 if ($count < 1);
        $count = 1000 if ($count > 1000);
        @command = ($ping, '-c', $count, '-W', '3', $target);
    }
}
elsif ($operation eq 'trace') {
    my $traceroute = command_path('traceroute_cmd', '/usr/bin/traceroute');
    api_fail(text('error_command', $traceroute)) if (!$traceroute || !has_command($traceroute));
    @command = ($traceroute, '-m', '20', '-w', '2', $target);
}
elsif ($operation eq 'port_test') {
    my $port = _trim($in{'port'} || '');
    api_fail($text{'error_port'}) if ($port !~ /^\d+$/ || $port < 1 || $port > 65535);
    my $nc = command_path('nc_cmd', '/usr/bin/nc');
    api_fail(text('error_command', $nc)) if (!$nc || !has_command($nc));
    @command = ($nc, '-vz', '-w', '5', $target, $port);
}
else {
    api_fail($text{'action_invalid'});
}

my @exec_command = @command;
my $stdbuf = command_path('stdbuf_cmd', '/usr/bin/stdbuf');
@exec_command = ($stdbuf, '-oL', '-eL', @command) if ($stdbuf && has_command($stdbuf));

my $base = diagnostic_jobs_dir();
eval { make_path($base, { mode => 0700 }) if (!-d $base); };
api_fail("$@" || "Cannot create $base") if ($@ || !-d $base);
chmod(0700, $base);

cleanup_diagnostic_jobs();
my $owner_hash = _request_identity();
my $max_jobs = int($config{'diagnostic_max_jobs_per_user'} || 2);
$max_jobs = 1 if ($max_jobs < 1); $max_jobs = 10 if ($max_jobs > 10);
my $running_jobs = 0;
foreach my $candidate (glob(File::Spec->catfile($base, '*'))) {
    next if (!-d $candidate);
    my $request = diagnostic_read_json(File::Spec->catfile($candidate, 'request.json')) || {};
    next if (($request->{'owner_hash'} || '') ne $owner_hash);
    my $status = diagnostic_read_json(File::Spec->catfile($candidate, 'status.json')) || {};
    my $state = $status->{'state'} || '';
    $running_jobs++ if ($state eq 'starting' || $state eq 'running');
}
api_fail($text{'diagnostics_too_many_jobs'} || 'Too many concurrent diagnostic jobs.') if ($running_jobs >= $max_jobs);

my $random = '';
if (sysopen(my $random_fh, '/dev/urandom', O_RDONLY)) {
    sysread($random_fh, $random, 32);
    close($random_fh);
}
my $job_id = sha256_hex(join('|', $random, time(), $$, rand(), $target, $operation));
my $job_dir = diagnostic_job_dir($job_id);
api_fail('Cannot create diagnostic job directory') if (!mkdir($job_dir, 0700));
chmod(0700, $job_dir);

my $request = {
    version => '1.0.0',
    created => time(),
    owner_hash => $owner_hash,
    interface => $name,
    peer => "$in{'peer'}",
    target => $target,
    operation => $operation,
    infinite => $infinite ? JSON::PP::true() : JSON::PP::false(),
    command => \@command,
    exec_command => \@exec_command,
    command_display => join(' ', map { shell_quote($_) } @command),
    idle_timeout => int($config{'diagnostic_idle_timeout'} || 30),
    max_output => int($config{'diagnostic_max_output'} || 10485760),
    messages => {
        completed_ok => $text{'diagnostics_completed_ok'},
        completed_error => $text{'diagnostics_completed_error'},
        completed_signal => $text{'diagnostics_completed_signal'},
        stopped => $text{'diagnostics_stopped'},
        disconnected => $text{'diagnostics_disconnected'} || 'Diagnostic stopped because the browser stopped polling.',
        output_limit => $text{'diagnostics_output_limit'} || 'Diagnostic stopped because the output limit was reached.',
        exec_failed => $text{'diagnostics_exec_failed'} || 'Failed to start command.',
    },
};
my ($request_ok, $request_error) = diagnostic_write_json(File::Spec->catfile($job_dir, 'request.json'), $request);
if (!$request_ok) {
    remove_tree($job_dir);
    api_fail($request_error);
}

diagnostic_write_json(File::Spec->catfile($job_dir, 'status.json'), {
    state => 'starting',
    created => time(),
    updated => time(),
    infinite => $infinite ? JSON::PP::true() : JSON::PP::false(),
});
sysopen(my $heartbeat, File::Spec->catfile($job_dir, 'heartbeat'), O_WRONLY|O_CREAT|O_TRUNC, 0600);
if ($heartbeat) { print {$heartbeat} time(); close($heartbeat); }

my $pid = fork();
if (!defined($pid)) {
    remove_tree($job_dir);
    api_fail("fork failed: $!");
}
if ($pid == 0) {
    setsid();
    open(STDIN, '<', '/dev/null');
    open(STDOUT, '>>', File::Spec->catfile($job_dir, 'launcher.log'));
    open(STDERR, '>&STDOUT');
    select(STDOUT); $| = 1;
    for my $fd (3 .. 1024) { POSIX::close($fd); }
    my $worker = File::Spec->rel2abs('diagnostic-worker.pl');
    exec($^X, $worker, $job_dir);
    print STDERR "exec worker failed: $!\n";
    _exit(127);
}

if (sysopen(my $pid_fh, File::Spec->catfile($job_dir, 'worker.pid'), O_WRONLY|O_CREAT|O_TRUNC, 0600)) {
    print {$pid_fh} $pid."\n";
    close($pid_fh);
}

webmin_log('diagnostic', 'peer', $name, { target => $target, operation => $operation });
json_response({
    ok => JSON::PP::true(),
    job_id => $job_id,
    infinite => $infinite ? JSON::PP::true() : JSON::PP::false(),
    status_url => module_script_url('diagnostic_status.cgi'),
    stop_url => module_script_url('diagnostic_stop.cgi'),
});
