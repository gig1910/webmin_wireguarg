#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();

my $collector_unit = 'webmin-wireguard-stats.service';

sub collector_health
{
    my $path = File::Spec->catfile(stats_dir(), 'health.json');
    my $health = diagnostic_read_json($path) || {};
    my $timestamp = 0 + ($health->{'timestamp'} || 0);
    my $interval = int($config{'stats_refresh_interval'} || 5);
    $interval = 2 if ($interval < 2);
    my $age = $timestamp ? time() - $timestamp : 0;
    my $stale_after = $interval * 4;
    $stale_after = 30 if ($stale_after < 30);
    my $stale = !$timestamp || $age > $stale_after;
    return {
        %$health,
        timestamp => $timestamp,
        age => $age > 0 ? $age : 0,
        stale_after => $stale_after,
        stale => $stale ? JSON::PP::true() : JSON::PP::false(),
        available => $timestamp ? JSON::PP::true() : JSON::PP::false(),
    };
}

sub collector_service_status
{
    my $systemctl = command_path('systemctl_cmd', '/usr/bin/systemctl');
    return {
        available => JSON::PP::false(), installed => JSON::PP::false(),
        active => JSON::PP::false(), state => 'unavailable', substate => '',
        error => text('error_command', $systemctl),
    } if (!$systemctl || !has_command($systemctl));

    my ($ok, $out) = run_command([
        $systemctl, 'show', $collector_unit, '--no-pager',
        '--property=LoadState,ActiveState,SubState,MainPID,Result,ExecMainStatus'
    ], 1, 10, 12000);
    my %props;
    foreach my $line (split(/\r?\n/, $out || '')) {
        my ($key, $value) = split(/=/, $line, 2);
        $props{$key} = defined($value) ? $value : '' if (defined($key) && $key =~ /^[A-Za-z][A-Za-z0-9]+$/);
    }
    my $load = $props{'LoadState'} || '';
    my $state = $props{'ActiveState'} || 'unknown';
    return {
        available => $ok || %props ? JSON::PP::true() : JSON::PP::false(),
        installed => ($load && $load ne 'not-found') ? JSON::PP::true() : JSON::PP::false(),
        active => $state eq 'active' ? JSON::PP::true() : JSON::PP::false(),
        state => $state,
        substate => $props{'SubState'} || '',
        load_state => $load,
        main_pid => 0 + ($props{'MainPID'} || 0),
        result => $props{'Result'} || '',
        exec_main_status => 0 + ($props{'ExecMainStatus'} || 0),
        error => (!$ok && !%props) ? ($out || 'systemctl show failed') : '',
    };
}

sub collector_snapshot
{
    my $service = collector_service_status();
    my $health = collector_health();
    my $current_settings = collector_effective_settings(\%config);
    my $current_fingerprint = collector_settings_fingerprint($current_settings);
    my $config_state = collector_applied_config_state($service, $health, $current_fingerprint);
    $health->{'current_config_fingerprint'} = $current_fingerprint;
    $health->{'config_state'} = $config_state;
    $health->{'restart_required'} = $config_state eq 'restart_required'
        ? JSON::PP::true() : JSON::PP::false();
    $health->{'config_pending'} = $config_state eq 'pending'
        ? JSON::PP::true() : JSON::PP::false();
    # Include names only, not values: a real mismatch should be actionable,
    # and Webmin should not accidentally echo custom paths or other settings.
    my $observed = $health->{'effective_settings'} || {};
    my @changed = $config_state eq 'restart_required'
        ? grep { (defined($current_settings->{$_}) ? $current_settings->{$_} : '') ne
                 (defined($observed->{$_}) ? $observed->{$_} : '') } sort keys(%$current_settings)
        : ();
    $health->{'config_mismatch_keys'} = \@changed;
    $health->{'current_effective_settings'} = $current_settings;
    return { health => $health, service => $service };
}

sub wait_for_service_state
{
    my ($action) = @_;
    my $deadline = time() + 8;
    my $expected = $action eq 'stop' ? '' :
        collector_settings_fingerprint(collector_effective_settings(\%config));
    my $status;
    while (1) {
        $status = collector_service_status();
        my $state = $status->{'state'} || '';
        if ($action eq 'stop') {
            last if ($state eq 'inactive' || $state eq 'failed' || !$status->{'installed'});
        }
        elsif ($state eq 'failed' || $state eq 'inactive') {
            # Failure must not be reported as a successful start.
            last if (time() >= $deadline);
        }
        elsif ($state eq 'active') {
            my $applied = collector_applied_config_state($status, collector_health(), $expected);
            # Do not report success immediately after systemd says active if
            # health.json still belongs to the previous process.
            last if ($applied ne 'pending');
        }
        last if (time() >= $deadline);
        select(undef, undef, undef, 0.25);
    }
    return $status;
}

sub collector_action_output
{
    my ($action, $command_output, $action_ok, $operation_ok, $service, $config_state) = @_;
    my $systemctl = command_path('systemctl_cmd', '/usr/bin/systemctl');
    my $output = '$ '.join(' ', map { shell_quote($_) } ($systemctl, $action, $collector_unit))."\n";
    $output .= length($command_output || '') ? $command_output : "(systemctl не вывел сообщений)\n";
    $output .= "\n---\n";
    $output .= 'Результат systemctl: '.($action_ok ? 'команда принята' : 'ошибка')."\n";
    my $outcome = $operation_ok ? 'успешно' : 'ошибка';
    if ($operation_ok && $action ne 'stop') {
        $outcome = 'служба запущена; ожидается подтверждение настроек'
            if (($config_state || '') eq 'pending');
        $outcome = 'служба запущена; настройки не подтверждены'
            if (($config_state || '') eq 'unverified');
        $outcome = 'служба запущена; настройки не совпадают'
            if (($config_state || '') eq 'restart_required');
    }
    $output .= 'Итог операции: '.$outcome."\n";
    $output .= 'Состояние службы: '.($service->{'state'} || 'unknown');
    $output .= '/'.$service->{'substate'} if ($service->{'substate'});
    $output .= "\nMainPID: ".($service->{'main_pid'} || 0)."\n";
    $output .= 'Result: '.$service->{'result'}."\n" if ($service->{'result'});

    my ($status_ok, $status_out) = run_command([
        $systemctl, 'status', $collector_unit, '--no-pager', '--full', '--lines=30'
    ], 1, 10, 30000);
    if (length($status_out || '')) {
        $output .= "\n--- systemctl status ---\n$status_out";
    }
    return $output;
}

if (($ENV{'REQUEST_METHOD'} || 'GET') eq 'POST') {
    assert_manage_access();
    assert_post_and_csrf();
    request_rate_limit('collector_control', 10, 300);
    my $action = $in{'action'} || '';
    error($text{'action_invalid'}) if ($action !~ /^(?:start|stop|restart)$/);
    my $systemctl = command_path('systemctl_cmd', '/usr/bin/systemctl');
    require_command($systemctl);

    my ($command_ok, $command_out, $status_code) = run_command([
        $systemctl, $action, $collector_unit
    ], 1, 30, 30000);
    my $service = wait_for_service_state($action);
    my $desired = $action eq 'stop'
        ? (($service->{'state'} || '') eq 'inactive')
        : (($service->{'state'} || '') eq 'active');
    my $ok = $command_ok && $desired;
    my $snapshot = collector_snapshot();
    my $config_state = $snapshot->{'health'}->{'config_state'} || '';
    my $output = collector_action_output($action, $command_out, $command_ok, $ok, $service, $config_state);
    if (!$desired) {
        $output .= "\nОжидаемое состояние службы не достигнуто за отведённое время.\n";
    }
    webmin_log($action, 'collector', $collector_unit, {
        ok => $ok ? 1 : 0,
        service_state => $service->{'state'} || '',
        command_status => 0 + ($status_code || 0),
    });
    $snapshot->{'service'} = $service;
    json_response({
        ok => $ok ? JSON::PP::true() : JSON::PP::false(),
        output => $output,
        %$snapshot,
    });
    exit;
}
json_response({ ok => JSON::PP::true(), %{collector_snapshot()} });
