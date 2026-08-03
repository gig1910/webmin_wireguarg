#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text);
$config{'wg_cmd'} = "$FindBin::Bin/bin/wg";
require "$FindBin::Bin/../wireguard-lib.pl";

my ($pub, $err) = derive_public_key('some-private-key');
die "derive failed: $err\n" if (!$pub || $pub ne 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
my ($valid) = validate_public_key($pub);
die "derived public key rejected\n" if (!$valid);
die "invalid public accepted\n" if ((validate_public_key('bad'))[0]);

die "IPv4 /0 network conversion failed
" if (cidr_network('198.51.100.17/0') ne '0.0.0.0/0');
die "IPv4 /32 network conversion failed
" if (cidr_network('198.51.100.17/32') ne '198.51.100.17/32');
die "IPv6 /0 network conversion failed
" if (cidr_network('fd20:66::1234/0') ne '::/0');
die "IPv6 /128 network conversion failed
" if (cidr_network('fd20:66::1234/128') ne 'fd20:66::1234/128');

my ($cfg, $parse_err) = parse_wireguard_config("$FindBin::Bin/sample-wg0.conf");
die $parse_err if (!$cfg);
my ($client, $client_err) = build_client_config($cfg, $cfg->{'peers'}->[0], {});
die "client config failed: $client_err\n" if (!$client);
die "private missing from client config\n" if ($client !~ /^PrivateKey = TEST_PRIVATE_LAPTOP$/m);
die "address mismatch\n" if ($client !~ /^Address = 10\.66\.66\.2\/32$/m);
die "endpoint mismatch\n" if ($client !~ /^Endpoint = vpn\.example\.test:443$/m);
die "explicit interface AllowedIPs mismatch\n" if ($client !~ /^AllowedIPs = 0\.0\.0\.0\/0, ::\/0$/m);

# Peer override has highest priority.
$cfg->{'peers'}->[0]->{'meta'}->{'clientallowedips'} = '10.123.0.0/16';
my ($resolved, $source) = resolve_client_allowed_ips($cfg, $cfg->{'peers'}->[0]);
die "peer override priority failed\n" if ($resolved ne '10.123.0.0/16' || $source ne 'peer');
delete $cfg->{'peers'}->[0]->{'meta'}->{'clientallowedips'};

# Interface override is used when the peer has no override.
($resolved, $source) = resolve_client_allowed_ips($cfg, $cfg->{'peers'}->[0]);
die "interface override priority failed\n" if ($resolved ne '0.0.0.0/0, ::/0' || $source ne 'interface');

# Without overrides, derive canonical and deduplicated networks from Address.
delete $cfg->{'interface'}->{'meta'}->{'clientallowedips'};
$cfg->{'interface'}->{'values'}->{'address'} = [
    '10.66.66.1/24, fd20:66::1/64',
    '10.66.66.9/24',
];
($resolved, $source) = resolve_client_allowed_ips($cfg, $cfg->{'peers'}->[0]);
die "automatic source mismatch: $source\n" if ($source ne 'auto');
die "automatic AllowedIPs mismatch: $resolved\n"
    if ($resolved ne '10.66.66.0/24, fd20:66::/64');
my ($auto_client, $auto_error) = build_client_config($cfg, $cfg->{'peers'}->[0], {});
die "automatic client config failed: $auto_error\n" if (!$auto_client);
die "automatic AllowedIPs not emitted\n"
    if ($auto_client !~ /^AllowedIPs = 10\.66\.66\.0\/24, fd20:66::\/64$/m);

# ClientAllowedIPs is never a blocker. If no route can be inferred, omit it
# and return a non-blocking warning.
$cfg->{'interface'}->{'values'}->{'address'} = [];
my $issues = client_config_static_issues($cfg, $cfg->{'peers'}->[0]);
die "missing ClientAllowedIPs still blocks export\n" if (@$issues);
my ($route_less_client, $route_less_error) = build_client_config($cfg, $cfg->{'peers'}->[0], {});
die "route-less client config failed: $route_less_error\n" if (!$route_less_client);
die "empty AllowedIPs line emitted\n" if ($route_less_client =~ /^AllowedIPs\s*=/m);
my $warnings = client_config_warnings($cfg, $cfg->{'peers'}->[0]);
die "missing non-blocking route warning\n" if (@$warnings != 1);


# A server endpoint without an explicit port inherits Interface.ListenPort.
my ($endpoint_cfg, $endpoint_error) = parse_wireguard_config("$FindBin::Bin/sample-wg0.conf");
die $endpoint_error if (!$endpoint_cfg);
$endpoint_cfg->{'interface'}->{'meta'}->{'clientendpoint'} = 'vpn.example.test';
my ($resolved_endpoint, $endpoint_source) = resolve_client_endpoint(
    $endpoint_cfg, $endpoint_cfg->{'peers'}->[0], {}
);
die "ListenPort was not appended to endpoint: $resolved_endpoint\n"
    if ($resolved_endpoint ne 'vpn.example.test:443' || $endpoint_source ne 'appended');
my ($endpoint_client, $endpoint_client_error) = build_client_config(
    $endpoint_cfg, $endpoint_cfg->{'peers'}->[0], {}
);
die "client config with inherited endpoint port failed: $endpoint_client_error\n" if (!$endpoint_client);
die "inherited endpoint port missing from config\n"
    if ($endpoint_client !~ /^Endpoint = vpn\.example\.test:443$/m);

# An explicit port is never duplicated.
$endpoint_cfg->{'interface'}->{'meta'}->{'clientendpoint'} = 'vpn.example.test:8443';
($resolved_endpoint, $endpoint_source) = resolve_client_endpoint(
    $endpoint_cfg, $endpoint_cfg->{'peers'}->[0], {}
);
die "explicit endpoint port changed: $resolved_endpoint\n"
    if ($resolved_endpoint ne 'vpn.example.test:8443' || $endpoint_source ne 'explicit');

# Bare IPv6 endpoints are bracketed before ListenPort is appended.
$endpoint_cfg->{'interface'}->{'meta'}->{'clientendpoint'} = '2001:db8::10';
($resolved_endpoint, $endpoint_source) = resolve_client_endpoint(
    $endpoint_cfg, $endpoint_cfg->{'peers'}->[0], {}
);
die "IPv6 endpoint was not bracketed: $resolved_endpoint\n"
    if ($resolved_endpoint ne '[2001:db8::10]:443');

# Missing both explicit and interface ports is a blocking endpoint error.
$endpoint_cfg->{'interface'}->{'meta'}->{'clientendpoint'} = 'vpn.example.test';
$endpoint_cfg->{'interface'}->{'values'}->{'listenport'} = [];
my ($missing_port_endpoint, $missing_port_source) = resolve_client_endpoint(
    $endpoint_cfg, $endpoint_cfg->{'peers'}->[0], {}
);
die "missing endpoint port was not detected\n"
    if ($missing_port_source ne 'missing_port');
my $endpoint_issues = client_config_static_issues($endpoint_cfg, $endpoint_cfg->{'peers'}->[0]);
die "missing endpoint port did not block export\n" if (!@$endpoint_issues);


my ($fresh_cfg, $fresh_error) = parse_wireguard_config("$FindBin::Bin/sample-wg0.conf");
die $fresh_error if (!$fresh_cfg);
my ($disabled_client, $disabled_error) = build_client_config($fresh_cfg, $fresh_cfg->{'peers'}->[1], {});
die "disabled peer client config should still be constructible: $disabled_error\n" if (!$disabled_client);

print "key and client configuration tests passed\n";
