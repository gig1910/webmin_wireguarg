package WebminWireGuardFirewall;
use strict;
use warnings;
use Fcntl qw(:flock);

# This library deliberately has no dependency on WebminCore. wg-quick hooks
# run under systemd and must work when Webmin is not running.
sub _execute {
    my ($argv) = @_;
    local $ENV{'LC_ALL'} = 'C';
    my $pid = open(my $pipe, '-|', @$argv);
    return (0, "Cannot execute @$argv: $!") if (!defined($pid));
    my $out = '';
    while (my $line = <$pipe>) {
        $out .= $line if (length($out) < 100000);
    }
    close($pipe);
    return ($? == 0, $out);
}

sub _managed_rules {
    my ($output, $name) = @_;
    my $tag = 'webmin-wg:'.$name;
    my @rules;
    foreach my $line (split(/\r?\n/, $output || '')) {
        if ($line =~ /^\s*\[\s*(\d+)\]\s+(\d+)\/udp(?:\s+\(v6\))?\s+ALLOW(?:\s+IN)?\s+.*\#\s*\Q$tag\E\s*$/) {
            push(@rules, { number => int($1), port => int($2) });
        }
    }
    return @rules;
}

sub manage {
    my ($action, $name, $port, %options) = @_;
    return (0, 'Invalid firewall action') if ($action ne 'up' && $action ne 'down');
    return (0, 'Invalid interface name')
        if (!defined($name) || $name !~ /^[A-Za-z0-9_=+.-]{1,15}$/);
    return (0, 'Invalid UDP port')
        if ($action eq 'up' && (!defined($port) || $port !~ /^[0-9]+$/ || $port < 1 || $port > 65535));
    my $ufw = $options{'ufw'} || '/usr/sbin/ufw';
    my $runner = $options{'runner'} || \&_execute;
    # UFW is optional. Never abort wg-quick when it is not installed.
    return (1, "WARNING: UFW unavailable ($ufw); $action rule management skipped")
        if (!-x $ufw && !$options{'runner'});

    # Serialize our own hook invocations so numbered-rule deletion is stable.
    # This cannot prevent independent administrators from changing UFW rules
    # between status and delete, so the rule comment is verified on every pass.
    my $lock_path = $options{'lock_path'} || '/run/lock/webmin-wireguard-ufw.lock';
    open(my $lock, '>>', $lock_path) or return (0, "Cannot lock $lock_path: $!");
    flock($lock, LOCK_EX) or return (0, "Cannot lock $lock_path: $!");
    my $tag = 'webmin-wg:'.$name;
    my $status = sub { return $runner->([ $ufw, 'status', 'numbered' ]); };
    my ($ok, $output) = $status->();
    return (0, "UFW status failed: $output") if (!$ok);
    # Inactive UFW has no live filtering policy to update. Leave WireGuard
    # operational and avoid creating/deleting rules on an inactive firewall.
    # An unrecognized or failed status remains an error: it might be active.
    return (1, "WARNING: UFW inactive; $action rule management skipped")
        if ($output =~ /^Status:\s+inactive\b/im);
    return (0, "Unrecognized UFW status: $output")
        if ($output !~ /^Status:\s+active\b/im);

    if ($action eq 'up') {
        my @current = _managed_rules($output, $name);
        if (!grep { $_->{'port'} == $port } @current) {
            my ($allow_ok, $allow_output) = $runner->([
                $ufw, 'allow', "$port/udp", 'comment', $tag
            ]);
            return (0, "UFW allow failed: $allow_output") if (!$allow_ok);
        }
    }

    # Delete only tagged rules for this interface. Iterate in descending
    # status number and re-read before each deletion (IPv4 and IPv6 entries).
    for (1..32) {
        ($ok, $output) = $status->();
        return (0, "UFW status failed: $output") if (!$ok);
        my @owned = grep {
            $action eq 'down' || $_->{'port'} != $port
        } _managed_rules($output, $name);
        last if (!@owned);
        @owned = sort { $b->{'number'} <=> $a->{'number'} } @owned;
        my ($delete_ok, $delete_output) = $runner->([
            $ufw, '--force', 'delete', $owned[0]->{'number'}
        ]);
        return (0, "UFW delete failed: $delete_output") if (!$delete_ok);
        return (0, 'UFW managed rule deletion exceeded safety limit') if ($_ == 32);
    }
    return (1, "$action UFW rule: $name".($action eq 'up' ? " UDP/$port" : ''));
}

1;
