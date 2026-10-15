#!/usr/bin/perl
use strict;
use warnings;
use File::Spec;
use Fcntl qw(:DEFAULT);
use IO::Select;
use JSON::PP qw(decode_json);
use POSIX qw(WNOHANG strftime);
use Encode qw(encode);

my $job_dir = shift(@ARGV) || die "Missing job directory\n";
die "Invalid job directory\n" if ($job_dir !~ m{^/[-A-Za-z0-9_./]+$} || !-d $job_dir);

sub read_all {
    my ($path) = @_;
    sysopen(my $fh, $path, O_RDONLY) or return undef;
    binmode($fh);
    local $/;
    my $data = <$fh>;
    close($fh);
    return $data;
}

sub write_json_atomic {
    my ($path, $data) = @_;
    my $json = JSON::PP->new->utf8(1)->canonical(1)->encode($data);
    my $tmp = $path.'.'.$$.'.tmp';
    sysopen(my $fh, $tmp, O_WRONLY|O_CREAT|O_EXCL, 0600) or return 0;
    binmode($fh);
    print {$fh} $json or do { close($fh); unlink($tmp); return 0; };
    close($fh) or do { unlink($tmp); return 0; };
    rename($tmp, $path) or do { unlink($tmp); return 0; };
    chmod(0600, $path);
    return 1;
}

sub append_text {
    my ($fh, $text) = @_;
    print {$fh} encode('UTF-8', $text);
}

my $request_raw = read_all(File::Spec->catfile($job_dir, 'request.json'));
die "Cannot read request\n" if (!defined($request_raw));
my $request = decode_json($request_raw);
my @argv = @{$request->{'exec_command'} || []};
die "Empty command\n" if (!@argv);

my $output_path = File::Spec->catfile($job_dir, 'output.log');
sysopen(my $output, $output_path, O_WRONLY|O_CREAT|O_APPEND, 0600) or die "Cannot open output: $!\n";
binmode($output);
select((select($output), $| = 1)[0]);
append_text($output, '$ '.($request->{'command_display'} || '')."\n\n");

my $status_path = File::Spec->catfile($job_dir, 'status.json');
my $heartbeat_path = File::Spec->catfile($job_dir, 'heartbeat');
my $stop_path = File::Spec->catfile($job_dir, 'stop.requested');
my $max_output = int($request->{'max_output'} || 10485760);
$max_output = 65536 if ($max_output < 65536);
my $idle_timeout = int($request->{'idle_timeout'} || 30);
$idle_timeout = 10 if ($idle_timeout < 10);
my $infinite = $request->{'infinite'} ? 1 : 0;
my $messages = $request->{'messages'} || {};

pipe(my $reader, my $writer) or die "pipe failed: $!\n";
my $child = fork();
die "fork failed: $!\n" if (!defined($child));
if ($child == 0) {
    setpgrp(0, 0);
    close($reader);
    open(STDIN, '<', '/dev/null');
    open(STDOUT, '>&', $writer) or POSIX::_exit(126);
    open(STDERR, '>&STDOUT') or POSIX::_exit(126);
    close($writer);
    $ENV{'LC_ALL'} = 'C.UTF-8' if (!$ENV{'LC_ALL'});
    {
        no warnings 'exec';
        exec(@argv);
    }
    print STDERR "exec failed: $!\n";
    POSIX::_exit(127);
}
close($writer);
binmode($reader);

write_json_atomic($status_path, {
    state => 'running',
    created => $request->{'created'} || time(),
    updated => time(),
    worker_pid => $$,
    child_pid => $child,
    infinite => $infinite ? JSON::PP::true() : JSON::PP::false(),
});

my $stop_reason = '';
my $term_requested = 0;
$SIG{'TERM'} = sub { $term_requested = 1; };
$SIG{'INT'} = sub { $term_requested = 1; };
$SIG{'HUP'} = sub { $term_requested = 1; };

my $selector = IO::Select->new($reader);
my $child_status;
my $output_size = -s $output_path || 0;

while (1) {
    if ($term_requested || -e $stop_path) {
        $stop_reason = 'user';
        kill('TERM', -$child);
        kill('TERM', $child);
    }
    if ($infinite && !$stop_reason) {
        my @heartbeat_stat = stat($heartbeat_path);
        if (!@heartbeat_stat || time() - $heartbeat_stat[9] > $idle_timeout) {
            $stop_reason = 'disconnected';
            kill('TERM', -$child);
            kill('TERM', $child);
        }
    }

    my @ready = $selector->can_read(1);
    foreach my $fh (@ready) {
        my $buffer = '';
        my $read = sysread($fh, $buffer, 16384);
        if (!defined($read)) {
            next if ($!{'EINTR'});
            $selector->remove($fh);
            close($fh);
            next;
        }
        if ($read == 0) {
            $selector->remove($fh);
            close($fh);
            next;
        }
        if ($output_size + $read > $max_output) {
            my $remaining = $max_output - $output_size;
            print {$output} substr($buffer, 0, $remaining) if ($remaining > 0);
            $output_size = $max_output;
            $stop_reason = 'output_limit';
            kill('TERM', -$child);
            kill('TERM', $child);
        }
        else {
            print {$output} $buffer;
            $output_size += $read;
        }
    }

    my $waited = waitpid($child, WNOHANG);
    if ($waited == $child) {
        $child_status = $?;
        last if ($selector->count() == 0);
    }
    last if (defined($child_status) && $selector->count() == 0);

    if ($stop_reason) {
        select(undef, undef, undef, 0.25);
        my $still = waitpid($child, WNOHANG);
        if ($still == 0) {
            kill('KILL', -$child);
            kill('KILL', $child);
        }
    }
}

if (!defined($child_status)) {
    waitpid($child, 0);
    $child_status = $?;
}

append_text($output, "\n---\n");
my ($exit_code, $signal) = ($child_status >> 8, $child_status & 127);
my $final_state = 'done';
if ($stop_reason eq 'user') {
    append_text($output, ($messages->{'stopped'} || 'Command stopped by user.')."\n");
    $final_state = 'stopped';
}
elsif ($stop_reason eq 'disconnected') {
    append_text($output, ($messages->{'disconnected'} || 'Diagnostic stopped because the browser stopped polling.')."\n");
    $final_state = 'stopped';
}
elsif ($stop_reason eq 'output_limit') {
    append_text($output, ($messages->{'output_limit'} || 'Diagnostic output limit reached.')."\n");
    $final_state = 'stopped';
}
elsif ($child_status == 0) {
    append_text($output, ($messages->{'completed_ok'} || 'Command completed successfully.')."\n");
}
elsif ($signal) {
    my $message = $messages->{'completed_signal'} || 'Command was stopped by signal $1.';
    $message =~ s/\$1/$signal/g;
    append_text($output, $message."\n");
}
else {
    my $message = $messages->{'completed_error'} || 'Command exited with code $1.';
    $message =~ s/\$1/$exit_code/g;
    append_text($output, $message."\n");
}
close($output);

write_json_atomic($status_path, {
    state => $final_state,
    created => $request->{'created'} || time(),
    updated => time(),
    worker_pid => $$,
    child_pid => $child,
    infinite => $infinite ? JSON::PP::true() : JSON::PP::false(),
    exit_code => $exit_code,
    signal => $signal,
    reason => $stop_reason,
    output_size => (-s $output_path || 0),
});
exit 0;
