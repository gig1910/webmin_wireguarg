=head1 subprocess-lib.pl

Bounded, nonblocking capture for the Webmin CGI and standalone collector.
Never execute through a shell; callers supply an argv array reference.

=cut

use strict;
use warnings;
use IPC::Open3 ();
use Symbol ();
use IO::Select ();
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use POSIX qw(WNOHANG);
use Time::HiRes ();
use Errno qw(EAGAIN EWOULDBLOCK EINTR EPIPE);
use Encode ();

sub _wg_nonblocking
{
    my ($fh) = @_;
    my $flags = fcntl($fh, F_GETFL, 0);
    return defined($flags) && fcntl($fh, F_SETFL, $flags | O_NONBLOCK);
}

sub wg_capture_subprocess
{
    my ($argv, $input, %options) = @_;
    return (0, '', 'Invalid argv', -1)
        unless ref($argv) eq 'ARRAY' && @$argv && !grep { !defined($_) || ref($_) } @$argv;
    $input = '' unless defined($input);
    $input = Encode::encode('UTF-8', $input) if utf8::is_utf8($input);
    my $max_input = $options{'max_input'} || 2_097_152;
    return (0, '', 'Subprocess input exceeds limit', -1) if length($input) > $max_input;
    my $max_out = $options{'max_stdout'} || 8_388_608;
    my $max_err = $options{'max_stderr'} || 65_536;
    my $timeout = $options{'timeout'} || 30;
    $timeout = 1 if $timeout < 1;
    $timeout = 7200 if $timeout > 7200;

    my ($stdin, $stdout);
    my $stderr = Symbol::gensym();
    my $pid = eval { IPC::Open3::open3($stdin, $stdout, $stderr, @$argv) };
    return (0, '', "Cannot launch subprocess: $@", -1) if $@ || !$pid;
    my $readers = IO::Select->new($stdout, $stderr);
    my $writers = IO::Select->new();
    $writers->add($stdin) if length($input);
    close($stdin) unless length($input);
    my ($out, $err, $offset) = ('', '', 0);
    my $stdout_fd = fileno($stdout);
    my $problem = '';
    my $status = -1;
    my $reaped = 0;
    for my $fh ($stdout, $stderr, (length($input) ? ($stdin) : ())) {
        if (!_wg_nonblocking($fh)) { $problem = 'Cannot enable nonblocking pipes'; last; }
    }
    # A child can close stdin before consuming the entire request.
    local $SIG{'PIPE'} = 'IGNORE';
    my $deadline = Time::HiRes::time() + $timeout;
    while (!$problem && ( $readers->count() || $writers->count() || !$reaped )) {
        if (Time::HiRes::time() >= $deadline) {
            $problem = "Subprocess exceeded ${timeout}s timeout";
            last;
        }
        my ($readable, $writable) = IO::Select->select($readers, $writers, undef, 0.1);
        for my $fh (@{$writable || []}) {
            my $sent = syswrite($fh, $input, 16_384, $offset);
            if (defined($sent)) {
                $offset += $sent;
                if ($offset >= length($input)) { $writers->remove($fh); close($fh); }
            }
            elsif (!$!{EAGAIN} && !$!{EWOULDBLOCK} && !$!{EINTR}) {
                $writers->remove($fh); close($fh);
                $problem = "Subprocess input write failed: $!" unless $!{EPIPE};
            }
        }
        for my $fh (@{$readable || []}) {
            my $chunk = '';
            my $length = sysread($fh, $chunk, 16_384);
            if (defined($length) && $length > 0) {
                my $target = fileno($fh) == $stdout_fd ? \$out : \$err;
                my $limit = fileno($fh) == $stdout_fd ? $max_out : $max_err;
                if (length($target) + $length > $limit) {
                    if ($options{'truncate_output'}) {
                        my $remaining = $limit - length($target);
                        $target .= substr($chunk, 0, $remaining) if $remaining > 0;
                        next;
                    }
                    $problem = 'Subprocess output exceeds limit';
                    last;
                }
                $target .= $chunk;
            }
            elsif (defined($length) && $length == 0) {
                $readers->remove($fh); close($fh);
            }
            elsif (!$!{EAGAIN} && !$!{EWOULDBLOCK} && !$!{EINTR}) {
                $problem = "Subprocess read failed: $!";
                last;
            }
        }
        if (!$reaped) {
            my $done = waitpid($pid, WNOHANG);
            if ($done == $pid || $done == -1) {
                $reaped = 1;
                $status = $done == $pid ? $? : -1;
            }
        }
    }
    if (!$reaped) {
        kill('TERM', $pid) if $problem;
        my $until = Time::HiRes::time() + 0.3;
        while (Time::HiRes::time() < $until) {
            my $done = waitpid($pid, WNOHANG);
            if ($done == $pid || $done == -1) {
                $reaped = 1;
                $status = $done == $pid ? $? : -1;
                last;
            }
            Time::HiRes::sleep(0.02);
        }
        if (!$reaped) {
            kill('KILL', $pid);
            my $done = waitpid($pid, 0);
            $status = $done == $pid ? $? : -1;
        }
    }
    for my $fh ($stdin, $stdout, $stderr) { close($fh) if defined(fileno($fh)); }
    return (!$problem && $status == 0 ? 1 : 0, $out, $problem || $err, $status);
}

1;
