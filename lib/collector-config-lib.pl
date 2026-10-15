=head1 collector-config-lib.pl

Shared normalization and fingerprinting for the background metrics collector.
This file intentionally has no Webmin dependencies so it can be loaded both by
CGI programs and by the standalone systemd service.

=cut

sub _collector_int_setting
{
    my ($cfg, $name, $default, $min, $max) = @_;
    my $raw = exists($cfg->{$name}) ? $cfg->{$name} : $default;
    $raw = $default if (!defined($raw) || $raw !~ /^-?\d+$/);
    my $value = int($raw);
    $value = $min if (defined($min) && $value < $min);
    $value = $max if (defined($max) && $value > $max);
    return $value;
}

sub collector_effective_settings
{
    my ($cfg) = @_;
    $cfg ||= {};
    my $max_file = _collector_int_setting($cfg, 'stats_max_file_bytes', 8388608, 262144, 1073741824);
    my $max_total = _collector_int_setting($cfg, 'stats_max_total_bytes', 268435456, 262144, 1099511627776);
    return {
        wg_cmd => $cfg->{'wg_cmd'} || '/usr/bin/wg',
        stats_dir => $cfg->{'stats_dir'} || '/var/webmin/wireguard/stats',
        analytics_enabled => (($cfg->{'analytics_enabled'} // '1') ne '0') ? 1 : 0,
        analytics_retention_days => _collector_int_setting($cfg,'analytics_retention_days',365,1,3650),
        stats_live_retention => _collector_int_setting($cfg,'stats_live_retention',3600,300,86400),
        prometheus_enabled => (($cfg->{'prometheus_enabled'} || '0') eq '1') ? 1 : 0,
        prometheus_interval => _collector_int_setting($cfg,'prometheus_interval',60,10,3600),
        prometheus_metrics => $cfg->{'prometheus_metrics'} || 'traffic,peer_state,handshake,collector',
        (map { ("prometheus_$_" => (($cfg->{"prometheus_$_"} // ($_ eq 'events' ? '0' : '1')) eq '1') ? 1 : 0) }
            qw(traffic peer_state handshake events collector)),
        prometheus_textfile_path => $cfg->{'prometheus_textfile_path'} ||
          '/var/lib/node_exporter/textfile_collector/webmin_wireguard.prom',
        stats_refresh_interval => _collector_int_setting($cfg, 'stats_refresh_interval', 5, 2, 3600),
        stats_history_retention => _collector_int_setting($cfg, 'stats_history_retention', 86400, 300, 315360000),
        stats_history_enabled => (($cfg->{'stats_history_enabled'} || '1') ne '0') ? 1 : 0,
        runtime_timeout => _collector_int_setting($cfg, 'runtime_timeout', 5, 1, 60),
        stats_max_points => _collector_int_setting($cfg, 'stats_max_points', 20000, 100, 200000),
        stats_max_file_bytes => $max_file,
        stats_max_total_bytes => $max_total,
        stats_effective_file_bytes => $max_file < $max_total ? $max_file : $max_total,
        stats_health_interval => _collector_int_setting($cfg, 'stats_health_interval', 30, 5, 3600),
    };
}

sub collector_settings_fingerprint
{
    my ($settings_or_cfg) = @_;
    my $settings = $settings_or_cfg && exists($settings_or_cfg->{'stats_effective_file_bytes'})
        ? $settings_or_cfg : collector_effective_settings($settings_or_cfg || {});
    my @keys = qw(
        wg_cmd stats_dir stats_refresh_interval stats_history_retention
        analytics_enabled analytics_retention_days stats_live_retention
        prometheus_enabled prometheus_interval prometheus_metrics prometheus_textfile_path
        prometheus_traffic prometheus_peer_state prometheus_handshake prometheus_events prometheus_collector
        stats_history_enabled runtime_timeout stats_max_points
        stats_max_file_bytes stats_max_total_bytes stats_effective_file_bytes
        stats_health_interval
    );
    my $payload = join("\n", map { $_.'='.(defined($settings->{$_}) ? $settings->{$_} : '') } @keys)."\n";
    return Digest::SHA::sha256_hex($payload);
}

# Service activation is not the same as the collector publishing a fresh
# health snapshot. Old health.json can survive a restart while initial history
# compaction is running. Only compare fingerprints when the health PID matches
# the systemd MainPID: otherwise we would recommend an endless restart loop.
sub collector_applied_config_state
{
    my ($service, $health, $expected_fingerprint) = @_;
    return 'inactive' if (($service->{'state'} || '') ne 'active');
    my $running_pid = 0 + ($service->{'main_pid'} || 0);
    my $health_pid = 0 + ($health->{'pid'} || 0);
    return 'pending' if (!$running_pid || !$health_pid || $running_pid != $health_pid);
    my $fingerprint = $health->{'config_fingerprint'} || '';
    return 'unverified' if (!$fingerprint);
    return $fingerprint eq ($expected_fingerprint || '') ? 'current' : 'restart_required';
}

1;
