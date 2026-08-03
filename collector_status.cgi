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
    my $running_fingerprint = $health->{'config_fingerprint'} || '';
    my $restart_required = ($service->{'state'} || '') eq 'active' &&
        (!$running_fingerprint || $running_fingerprint ne $current_fingerprint);
    $health->{'current_config_fingerprint'} = $current_fingerprint;
    $health->{'restart_required'} = $restart_required ? JSON::PP::true() : JSON::PP::false();
    $health->{'current_effective_settings'} = $current_settings;
    return { health => $health, service => $service };
}

sub wait_for_service_state
{
    my ($action) = @_;
    my $deadline = time() + 8;
    my $status;
    while (1) {
        $status = collector_service_status();
        my $state = $status->{'state'} || '';
        last if ($action eq 'stop' ? ($state eq 'inactive' || $state eq 'failed' || !$status->{'installed'}) : $state eq 'active');
        last if (time() >= $deadline);
        select(undef, undef, undef, 0.25);
    }
    return $status;
}

sub collector_action_output
{
    my ($action, $command_output, $action_ok, $operation_ok, $service) = @_;
    my $systemctl = command_path('systemctl_cmd', '/usr/bin/systemctl');
    my $output = '$ '.join(' ', map { shell_quote($_) } ($systemctl, $action, $collector_unit))."\n";
    $output .= length($command_output || '') ? $command_output : "(systemctl не вывел сообщений)\n";
    $output .= "\n---\n";
    $output .= 'Результат systemctl: '.($action_ok ? 'команда принята' : 'ошибка')."\n";
    $output .= 'Итог операции: '.($operation_ok ? 'успешно' : 'ошибка')."\n";
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
    my $output = collector_action_output($action, $command_out, $command_ok, $ok, $service);
    if (!$desired) {
        $output .= "\nОжидаемое состояние службы не достигнуто за отведённое время.\n";
    }
    webmin_log($action, 'collector', $collector_unit, {
        ok => $ok ? 1 : 0,
        service_state => $service->{'state'} || '',
        command_status => 0 + ($status_code || 0),
    });
    my $snapshot = collector_snapshot();
    $snapshot->{'service'} = $service;
    json_response({
        ok => $ok ? JSON::PP::true() : JSON::PP::false(),
        output => $output,
        %$snapshot,
    });
    exit;
}
json_response({ ok => JSON::PP::true(), %{collector_snapshot()} });
