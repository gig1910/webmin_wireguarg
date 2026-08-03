#!/usr/local/bin/perl
require './wireguard-lib.pl';
use File::Spec;
use Fcntl qw(:DEFAULT);

ReadParse();
assert_view_access();
assert_diagnostics_access();

sub api_fail { my ($message) = @_; json_response({ ok => JSON::PP::false(), error => $message }); exit; }
sub valid_pid { return defined($_[0]) && $_[0] =~ /^\d+$/ && $_[0] > 1; }
sub process_alive
{
    my ($pid) = @_;
    return 0 if (!valid_pid($pid));
    return kill(0, $pid) ? 1 : 0;
}
sub read_pid_file
{
    my ($path) = @_;
    return undef if (!-r $path);
    my $raw = read_file_contents($path) || '';
    my ($pid) = $raw =~ /^(\d+)/;
    return valid_pid($pid) ? $pid : undef;
}
sub signal_child
{
    my ($signal, $pid) = @_;
    return 0 if (!valid_pid($pid));

    # The diagnostic worker places the command in its own process group. Send
    # to both the group and the process as a fallback in case setpgrp failed or
    # the command replaced itself before the group became visible.
    my $sent = kill($signal, -$pid) || 0;
    $sent += kill($signal, $pid) || 0;
    return $sent;
}

eval { assert_post_and_csrf(); request_rate_limit('diagnostic', 20, 60); 1 } or api_fail($@ || $text{'action_post'});

my $job_id = $in{'job'} || '';
api_fail($text{'diagnostics_job_invalid'} || 'Invalid diagnostic job.') if (!valid_diagnostic_job_id($job_id));
my $job_dir = diagnostic_job_dir($job_id);
api_fail($text{'diagnostics_job_missing'} || 'Diagnostic job not found.') if (!-d $job_dir);
my $request = diagnostic_read_json(File::Spec->catfile($job_dir, 'request.json')) || {};
api_fail($text{'diagnostics_job_missing'} || 'Diagnostic job not found.') if (($request->{'owner_hash'} || '') ne _request_identity());

my $status_path = File::Spec->catfile($job_dir, 'status.json');
my $status = diagnostic_read_json($status_path) || {};
my $state = $status->{'state'} || '';
my $worker_pid = valid_pid($status->{'worker_pid'})
    ? $status->{'worker_pid'}
    : read_pid_file(File::Spec->catfile($job_dir, 'worker.pid'));
my $child_pid = valid_pid($status->{'child_pid'}) ? $status->{'child_pid'} : undef;
my $already_done = ($state eq 'done' || $state eq 'stopped' || $state eq 'failed') ? 1 : 0;
my $term_sent = 0;
my $kill_sent = 0;

if (!$already_done) {
    my $stop_path = File::Spec->catfile($job_dir, 'stop.requested');
    if (sysopen(my $stop, $stop_path, O_WRONLY|O_CREAT|O_TRUNC, 0600)) {
        print {$stop} time()."\n";
        close($stop);
    }
    else {
        api_fail("Cannot create stop request: $!");
    }

    # Do not rely only on the worker noticing the marker on its next polling
    # iteration. Terminate the command group immediately, while leaving the
    # worker alive long enough to drain output and write the final status.
    $term_sent += signal_child('TERM', $child_pid) if ($child_pid);
    if ($worker_pid && ($state eq 'running' || $child_pid)) {
        $term_sent += kill('TERM', $worker_pid) || 0;
    }

    # Give normal termination a short grace period, then force only the child
    # command group. The worker must survive so it can report "stopped".
    if ($child_pid) {
        for (1 .. 10) {
            last if (!process_alive($child_pid));
            select(undef, undef, undef, 0.1);
        }
        if (process_alive($child_pid)) {
            $kill_sent += signal_child('KILL', $child_pid);
        }
    }
}

json_response({
    ok => JSON::PP::true(),
    job_id => $job_id,
    stopping => $already_done ? JSON::PP::false() : JSON::PP::true(),
    state => $state,
    worker_pid => $worker_pid,
    child_pid => $child_pid,
    term_sent => $term_sent,
    kill_sent => $kill_sent,
});
