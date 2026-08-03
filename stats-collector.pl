#!/usr/bin/perl
use strict;
use warnings;
use JSON::PP qw(encode_json decode_json);
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use FindBin;
use Fcntl qw(:DEFAULT :flock F_GETFL F_SETFL O_NONBLOCK SEEK_SET);
use POSIX qw(:sys_wait_h);
use IO::Select;
use Errno qw(EAGAIN EWOULDBLOCK EINTR);

require "$FindBin::Bin/lib/collector-config-lib.pl";

my $cfg_file = $ENV{'WEBMIN_WIREGUARD_CONFIG'} || '/etc/webmin/wireguard/config';
my %cfg;
if (open(my $cf, '<', $cfg_file)) {
    while (<$cf>) {
        chomp;
        next if /^\s*(?:#|$)/;
        my ($key, $value) = split(/=/, $_, 2);
        $cfg{$key} = $value if (defined($value));
    }
    close($cf);
}
my $effective = collector_effective_settings(\%cfg);
my $config_fingerprint = collector_settings_fingerprint($effective);
my $history_enabled = $effective->{'stats_history_enabled'};
my $wg = $effective->{'wg_cmd'};
my $dir = $effective->{'stats_dir'};
my $interval = $effective->{'stats_refresh_interval'};
my $retention = $effective->{'stats_history_retention'};
my $runtime_timeout = $effective->{'runtime_timeout'};
my $max_points = $effective->{'stats_max_points'};
my $max_file_bytes = $effective->{'stats_effective_file_bytes'};
my $max_total_bytes = $effective->{'stats_max_total_bytes'};
my $health_interval = $effective->{'stats_health_interval'};

make_path($dir, { mode => 0700 }) if (!-d $dir);
chmod(0700, $dir);
my $collector_lock_path = "$dir/.collector.lock";
sysopen(my $collector_lock, $collector_lock_path, O_RDWR|O_CREAT, 0600)
    or die "Cannot open collector lock: $!\n";
flock($collector_lock, LOCK_EX|LOCK_NB)
    or die "Another collector instance is already running\n";

sub valid_interface_name {
    my ($name) = @_;
    return defined($name) && $name =~ /^[A-Za-z0-9_=+.-]{1,15}$/;
}

my $stop_requested = 0;
sub request_stop { $stop_requested = 1; }
$SIG{'TERM'} = \&request_stop;
$SIG{'INT'} = \&request_stop;
$SIG{'HUP'} = \&request_stop;

sub interruptible_pause
{
    my ($seconds) = @_;
    my $deadline = time() + ($seconds || 0);
    while (!$stop_requested) {
        my $remaining = $deadline - time();
        last if ($remaining <= 0);
        my $slice = $remaining > 0.20 ? 0.20 : $remaining;
        select(undef, undef, undef, $slice);
    }
}

sub terminate_child
{
    my ($pid) = @_;
    return if (!$pid || $pid <= 0);
    my $sent = kill('TERM', -$pid);
    kill('TERM', $pid) if (!$sent);
    my $deadline = time() + 0.8;
    while (time() < $deadline) {
        my $rv = waitpid($pid, WNOHANG);
        return if ($rv == $pid || $rv == -1);
        select(undef, undef, undef, 0.05);
    }
    $sent = kill('KILL', -$pid);
    kill('KILL', $pid) if (!$sent);
    my $deadline2 = time() + 0.8;
    while (time() < $deadline2) {
        my $rv = waitpid($pid, WNOHANG);
        return if ($rv == $pid || $rv == -1);
        select(undef, undef, undef, 0.05);
    }
    waitpid($pid, WNOHANG);
}

sub run_wg_dump
{
    pipe(my $reader, my $writer) || return undef;
    my $pid = fork();
    if (!defined($pid)) {
        close($reader); close($writer);
        return undef;
    }
    if ($pid == 0) {
        close($reader);
        eval { POSIX::setpgid(0, 0); };
        open(STDOUT, '>&', $writer) || exit 126;
        open(STDERR, '>', '/dev/null');
        close($writer);
        exec { $wg } $wg, 'show', 'all', 'dump';
        exit 127;
    }

    close($writer);
    eval { POSIX::setpgid($pid, $pid); };
    my $flags = fcntl($reader, F_GETFL, 0);
    fcntl($reader, F_SETFL, ($flags || 0) | O_NONBLOCK);
    my $selector = IO::Select->new($reader);
    my $output = '';
    my $deadline = time() + $runtime_timeout;
    my $child_exited = 0;
    my $child_status;
    my $pipe_open = 1;

    while (1) {
        if ($stop_requested || time() >= $deadline) {
            terminate_child($pid);
            close($reader) if ($pipe_open);
            return undef;
        }

        foreach my $fh ($selector->can_read(0.20)) {
            my $chunk = '';
            my $read = sysread($fh, $chunk, 65536);
            if (defined($read) && $read > 0) {
                $output .= $chunk;
            }
            elsif (defined($read) && $read == 0) {
                $selector->remove($fh);
                close($fh);
                $pipe_open = 0;
            }
            elsif (!$!{EAGAIN} && !$!{EWOULDBLOCK} && !$!{EINTR}) {
                $selector->remove($fh);
                close($fh);
                $pipe_open = 0;
            }
        }

        if (!$child_exited) {
            my $rv = waitpid($pid, WNOHANG);
            if ($rv == $pid) {
                $child_status = $?;
                $child_exited = 1;
            }
            elsif ($rv == -1) {
                $child_status = 255 << 8;
                $child_exited = 1;
            }
        }
        last if ($child_exited && !$pipe_open);
    }
    return defined($child_status) && $child_status == 0 ? $output : undef;
}

sub parse_dump {
    my ($output) = @_;
    my %interfaces;
    foreach my $line (grep { length($_) } split(/\r?\n/, $output || '')) {
        last if ($stop_requested);
        my @f = split(/\t/, $line, -1);
        if (@f == 5) {
            my $name = $f[0];
            next if (!valid_interface_name($name));
            $interfaces{$name} = {
                name => $name,
                interface => {
                    public_key => $f[2] || '',
                    listen_port => $f[3] || '',
                    fwmark => $f[4] || '',
                },
                peers => {}, peer_list => [], rx_bytes => 0, tx_bytes => 0,
            };
            next;
        }
        next if (@f < 9);
        my $name = $f[0];
        next if (!$interfaces{$name});
        my $peer = {
            public_key => $f[1] || '', endpoint => $f[3] || '',
            allowed_ips => $f[4] || '', latest_handshake => 0 + ($f[5] || 0),
            rx_bytes => 0 + ($f[6] || 0), tx_bytes => 0 + ($f[7] || 0),
            persistent_keepalive => 0 + ($f[8] || 0),
        };
        $interfaces{$name}->{'peers'}->{$peer->{'public_key'}} = $peer;
        push(@{$interfaces{$name}->{'peer_list'}}, $peer);
        $interfaces{$name}->{'rx_bytes'} += $peer->{'rx_bytes'};
        $interfaces{$name}->{'tx_bytes'} += $peer->{'tx_bytes'};
    }
    return \%interfaces;
}

sub atomic_json_write {
    my ($path, $data) = @_;
    my $tmp = $path.'.tmp.'.$$;
    sysopen(my $fh, $tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600) || return 0;
    binmode($fh);
    my $ok = print {$fh} encode_json($data);
    $ok &&= close($fh);
    if (!$ok) {
        close($fh);
        unlink($tmp);
        return 0;
    }
    chmod(0600, $tmp);
    if (!rename($tmp, $path)) {
        unlink($tmp);
        return 0;
    }
    chmod(0600, $path);
    return 1;
}

sub history_storage_stats
{
    my $bytes = 0;
    my $files = 0;
    foreach my $path (grep { -f $_ } glob("$dir/*.jsonl")) {
        $files++;
        $bytes += (-s $path || 0);
    }
    return ($files, $bytes);
}

sub total_storage_stats
{
    my $bytes = 0;
    my $files = 0;
    foreach my $path (glob("$dir/*")) {
        next if (!-f $path);
        $files++;
        $bytes += (-s $path || 0);
    }
    return ($files, $bytes);
}

my %last_compaction_summary;
my $maintenance_error = '';
sub write_health
{
    my (%extra) = @_;
    my ($history_files, $history_bytes) = history_storage_stats();
    my ($all_files, $all_bytes) = total_storage_stats();
    atomic_json_write("$dir/health.json", {
        timestamp => time(), pid => $$, interval => $interval,
        history_enabled => $history_enabled ? JSON::PP::true() : JSON::PP::false(),
        history_files => $history_files,
        history_storage_bytes => $history_bytes,
        storage_files => $all_files,
        storage_bytes => $all_bytes,
        max_total_bytes => $max_total_bytes,
        max_file_bytes => $max_file_bytes,
        max_points => $max_points,
        retention => $retention,
        config_fingerprint => $config_fingerprint,
        effective_settings => $effective,
        (%last_compaction_summary ? (last_compaction => \%last_compaction_summary) : ()),
        %extra,
    });
}

sub _retained_history_line
{
    my ($line, $cutoff) = @_;
    my $data = eval { decode_json($line) };
    return 0 if (!$data || ref($data) ne 'HASH');
    return 0 if (($data->{'timestamp'} || 0) < $cutoff);
    return 1;
}

sub _compact_one_history
{
    my ($path, $byte_cap) = @_;
    return 1 if (!-f $path);
    return 0 if ($stop_requested);
    $byte_cap = $max_file_bytes if (!defined($byte_cap) || $byte_cap <= 0);
    my $cutoff = time() - $retention;
    open(my $in, '<', $path) || return 0;
    flock($in, LOCK_SH);

    my ($valid_count, $valid_bytes) = (0, 0);
    while (my $line = <$in>) {
        if ($stop_requested) { close($in); return 0; }
        next if (!_retained_history_line($line, $cutoff));
        $valid_count++;
        $valid_bytes += length($line);
        if ($ENV{'WEBMIN_WIREGUARD_TEST_COMPACT_DELAY_USEC'}) {
            select(undef, undef, undef, int($ENV{'WEBMIN_WIREGUARD_TEST_COMPACT_DELAY_USEC'}) / 1_000_000);
        }
    }

    my $skip_count = $valid_count > $max_points ? $valid_count - $max_points : 0;
    my $skip_bytes = $valid_bytes > $byte_cap ? $valid_bytes - $byte_cap : 0;
    seek($in, 0, SEEK_SET) || do { close($in); return 0; };
    my $tmp = "$path.tmp.$$";
    sysopen(my $out, $tmp, O_WRONLY|O_CREAT|O_EXCL, 0600) || do { close($in); return 0; };
    my ($written_lines, $written_bytes) = (0, 0);
    while (my $line = <$in>) {
        if ($stop_requested) {
            close($in); close($out); unlink($tmp); return 0;
        }
        next if (!_retained_history_line($line, $cutoff));
        if ($skip_count > 0 || $skip_bytes > 0) {
            $skip_count-- if ($skip_count > 0);
            $skip_bytes -= length($line) if ($skip_bytes > 0);
            next;
        }
        print {$out} $line or do { close($in); close($out); unlink($tmp); return 0; };
        $written_lines++;
        $written_bytes += length($line);
    }
    close($in);
    close($out) || do { unlink($tmp); return 0; };
    chmod(0600, $tmp);
    if ($written_lines == 0) {
        unlink($tmp);
        unlink($path);
        return 1;
    }
    rename($tmp, $path) || do { unlink($tmp); return 0; };
    chmod(0600, $path);
    return 1;
}

sub append_sample
{
    my ($name, $peer, $sample) = @_;
    return if ($stop_requested || !valid_interface_name($name));
    my $id = length($peer) ? 'peer-'.sha256_hex($peer) : 'interface';
    my $path = "$dir/$name-$id.jsonl";
    open(my $fh, '>>', $path) || return;
    flock($fh, LOCK_EX);
    print {$fh} encode_json($sample)."\n";
    close($fh);
    chmod(0600, $path);
    if (!$stop_requested && (-s $path || 0) > $max_file_bytes) {
        $maintenance_error = 'history file compaction failed'
            if (!_compact_one_history($path, $max_file_bytes));
    }
}

sub _enforce_total_storage
{
    my @paths = grep { -f $_ } glob("$dir/*.jsonl");
    return 1 if ($stop_requested || !@paths);
    my $total = 0; $total += (-s $_ || 0) for @paths;
    return 1 if ($total <= $max_total_bytes);

    # First preserve a recent tail for every interface/peer by sharing the
    # aggregate budget across all history files.
    my $fair_cap = int($max_total_bytes / scalar(@paths));
    $fair_cap = 1 if ($fair_cap < 1);
    foreach my $path (@paths) {
        return 0 if ($stop_requested);
        _compact_one_history($path, $fair_cap) || return 0;
    }
    @paths = grep { -f $_ } @paths;
    $total = 0; $total += (-s $_ || 0) for @paths;

    # Line granularity or exceptionally large records may still leave a small
    # excess. Remove the oldest complete histories only as a final fallback.
    if ($total > $max_total_bytes) {
        @paths = sort { (stat($a))[9] <=> (stat($b))[9] } @paths;
        foreach my $path (@paths) {
            return 0 if ($stop_requested);
            last if ($total <= $max_total_bytes);
            my $size = -s $path || 0;
            if (unlink($path)) { $total -= $size; }
        }
    }
    return $total <= $max_total_bytes ? 1 : 0;
}

sub compact_history
{
    my ($before_files, $before_bytes) = history_storage_stats();
    my @paths = grep { -f $_ } glob("$dir/*.jsonl");
    foreach my $path (@paths) {
        return 0 if ($stop_requested);
        _compact_one_history($path, $max_file_bytes) || return 0;
    }
    _enforce_total_storage() || return 0;
    my ($after_files, $after_bytes) = history_storage_stats();
    %last_compaction_summary = (
        timestamp => time(),
        files_before => $before_files,
        files_after => $after_files,
        bytes_before => $before_bytes,
        bytes_after => $after_bytes,
        bytes_removed => $before_bytes > $after_bytes ? $before_bytes - $after_bytes : 0,
    );
    return 1;
}

write_health(ok => JSON::PP::true(), running => JSON::PP::true(),
    state => 'compacting', error => '', started_at => time());
my $startup_compaction_ok = compact_history();
if ($stop_requested) {
    write_health(ok => JSON::PP::true(), running => JSON::PP::false(),
        state => 'stopped', error => '', stopped_at => time());
    exit 0;
}
if (!$startup_compaction_ok) {
    $maintenance_error = 'history compaction failed';
    write_health(ok => JSON::PP::false(), running => JSON::PP::true(),
        state => 'starting', error => $maintenance_error);
}
else {
    write_health(ok => JSON::PP::true(), running => JSON::PP::true(),
        state => 'starting', error => '');
}

my $last_compact = time();
my $last_health = 0;
while (!$stop_requested) {
    my $now = time();
    my $output = run_wg_dump();
    last if ($stop_requested);
    my $last_error = $maintenance_error;
    if (defined($output)) {
        my $interfaces = parse_dump($output);
        last if ($stop_requested);
        atomic_json_write("$dir/runtime.json", {
            timestamp => $now,
            interfaces => $interfaces,
        });

        if ($history_enabled) {
            foreach my $name (keys(%$interfaces)) {
                last if ($stop_requested);
                my $iface = $interfaces->{$name};
                append_sample($name, '', {
                    timestamp => $now,
                    rx => 0 + ($iface->{'rx_bytes'} || 0),
                    tx => 0 + ($iface->{'tx_bytes'} || 0),
                });
                foreach my $peer (@{$iface->{'peer_list'} || []}) {
                    last if ($stop_requested);
                    append_sample($name, $peer->{'public_key'}, {
                        timestamp => $now,
                        rx => 0 + ($peer->{'rx_bytes'} || 0),
                        tx => 0 + ($peer->{'tx_bytes'} || 0),
                    });
                }
            }
        }
    }
    else { $last_error = join('; ', grep { length($_) } ($maintenance_error, 'wg show all dump failed or timed out')); }

    last if ($stop_requested);
    if ($now - $last_compact >= 600) {
        write_health(ok => $last_error ? JSON::PP::false() : JSON::PP::true(),
            running => JSON::PP::true(), state => 'compacting', error => $last_error);
        if (compact_history()) { $maintenance_error = ''; }
        else { $maintenance_error = 'history compaction failed' if (!$stop_requested); }
        $last_error = join('; ', grep { length($_) } ($last_error, $maintenance_error));
        $last_compact = time();
        last if ($stop_requested);
    }
    if ($now - $last_health >= $health_interval) {
        my (undef, $current_history_bytes) = history_storage_stats();
        if ($current_history_bytes > $max_total_bytes) {
            if (compact_history()) { $maintenance_error = ''; }
            else { $maintenance_error = 'history compaction failed' if (!$stop_requested); }
            $last_error = join('; ', grep { length($_) } ($last_error, $maintenance_error));
            last if ($stop_requested);
        }
        write_health(ok => $last_error ? JSON::PP::false() : JSON::PP::true(),
            running => JSON::PP::true(), state => 'running', error => $last_error);
        $last_health = time();
    }
    last if ($ENV{'WEBMIN_WIREGUARD_ONCE'});
    interruptible_pause($interval);
}
write_health(ok => JSON::PP::true(), running => JSON::PP::false(),
    state => 'stopped', error => '', stopped_at => time());
exit 0;
