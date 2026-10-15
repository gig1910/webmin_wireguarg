#!/usr/local/bin/perl
require './wireguard-lib.pl';
use File::Spec;
use Fcntl qw(:DEFAULT SEEK_SET);

ReadParse();
assert_view_access();
assert_diagnostics_access();

sub api_fail { my ($message) = @_; json_response({ ok => JSON::PP::false(), error => $message }); exit; }

my $job_id = $in{'job'} || '';
api_fail($text{'diagnostics_job_invalid'} || 'Invalid diagnostic job.') if (!valid_diagnostic_job_id($job_id));
my $job_dir = diagnostic_job_dir($job_id);
api_fail($text{'diagnostics_job_missing'} || 'Diagnostic job not found.') if (!-d $job_dir);
my $request = diagnostic_read_json(File::Spec->catfile($job_dir, 'request.json')) || {};
api_fail($text{'diagnostics_job_missing'} || 'Diagnostic job not found.') if (($request->{'owner_hash'} || '') ne _request_identity());

my $status = diagnostic_read_json(File::Spec->catfile($job_dir, 'status.json')) || { state => 'starting' };
if (($status->{'state'} || '') eq 'running' || ($status->{'state'} || '') eq 'starting') {
    my $heartbeat_path = File::Spec->catfile($job_dir, 'heartbeat');
    if (sysopen(my $heartbeat, $heartbeat_path, O_WRONLY|O_CREAT, 0600)) {
        print {$heartbeat} time();
        close($heartbeat);
        utime(time(), time(), $heartbeat_path);
    }
}

my $offset = int($in{'offset'} || 0);
$offset = 0 if ($offset < 0);
my $output_path = File::Spec->catfile($job_dir, 'output.log');
my $size = -f $output_path ? (-s $output_path || 0) : 0;
$offset = 0 if ($offset > $size);
my $chunk = '';
my $max_chunk = 65536;
if ($size > $offset && sysopen(my $output, $output_path, O_RDONLY)) {
    binmode($output);
    seek($output, $offset, SEEK_SET);
    my $wanted = $size - $offset;
    $wanted = $max_chunk if ($wanted > $max_chunk);
    sysread($output, $chunk, $wanted);
    close($output);
}
my $next_offset = $offset + length($chunk);
my $state = $status->{'state'} || 'starting';
my $done = ($state eq 'done' || $state eq 'stopped' || $state eq 'failed') ? 1 : 0;

json_response({
    ok => JSON::PP::true(),
    job_id => $job_id,
    state => $state,
    done => $done ? JSON::PP::true() : JSON::PP::false(),
    infinite => $status->{'infinite'} ? JSON::PP::true() : JSON::PP::false(),
    offset => $next_offset,
    output_size => $size,
    more => $next_offset < $size ? JSON::PP::true() : JSON::PP::false(),
    chunk_b64 => MIME::Base64::encode_base64($chunk, ''),
    exit_code => $status->{'exit_code'},
    signal => $status->{'signal'},
    reason => $status->{'reason'} || '',
});
