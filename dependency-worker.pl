#!/usr/bin/env perl
# Standalone package installer. Never load WebminCore in a background job.
use strict;
use warnings;
use FindBin;
use File::Spec;
use File::Basename qw(basename dirname);
use Fcntl qw(:DEFAULT :flock);
use JSON::PP ();
require "$FindBin::Bin/lib/subprocess-lib.pl";

my $job_dir = shift(@ARGV) || die "Missing install job directory\n";
die "Invalid job ID\n" unless basename($job_dir) =~ /^[a-f0-9]{64}$/;
die "Invalid job directory\n" unless -d $job_dir && !-l $job_dir;
my $base = dirname($job_dir);
die "Invalid job root\n" unless basename($base) eq 'dependency-jobs' && !-l $base;

sub read_json
{
    my ($path) = @_;
    sysopen(my $fh, $path, O_RDONLY) || return undef;
    binmode($fh);
    local $/;
    my $body=<$fh>;
    close($fh);
    return eval { JSON::PP::decode_json($body) };
}

sub save_json
{
    my ($name, $value) = @_;
    my $path=File::Spec->catfile($job_dir,$name);
    my $tmp=$path.'.'.$$.'.tmp';
    my $body=JSON::PP->new->utf8(1)->canonical(1)->encode($value);
    sysopen(my $fh, $tmp, O_WRONLY|O_CREAT|O_EXCL, 0600)
        or die "Cannot create status: $!\n";
    binmode($fh);
    print {$fh} $body or die "Cannot write status: $!\n";
    close($fh) or die "Cannot close status: $!\n";
    rename($tmp,$path) or die "Cannot publish status: $!\n";
}

my $request=read_json(File::Spec->catfile($job_dir,'request.json'));
die "Invalid install request\n" unless ref($request) eq 'HASH';
my %allowed=(
    qrencode=>[qw(qrencode)],
    geoip=>[qw(geoipupdate mmdb-bin geoip-bin geoip-database whois)],
);
my $dependency=$request->{'dependency'} || '';
die "Unsupported install target\n" unless exists $allowed{$dependency};
my $apt=$request->{'apt'} || '';
die "Invalid apt-get executable\n" unless $apt =~ m{^/[A-Za-z0-9_./+-]+$} && -x $apt;
my $created=$request->{'created'} || time();

sub report
{
    my (%fields)=@_;
    save_json('status.json',{
        dependency=>$dependency, created=>$created, updated=>time(),
        worker_pid=>$$, %fields,
    });
}
my $lock_path=File::Spec->catfile($base,'.installer.lock');
sysopen(my $lock, $lock_path, O_RDWR|O_CREAT, 0600)
    or die "Cannot create installer lock: $!\n";
if (!flock($lock, LOCK_EX|LOCK_NB)) {
    report(state=>'failed',error=>'Another dependency installation is already running',
        exit_code=>255);
    exit 1;
}
report(state=>'running',error=>'',exit_code=>undef);

# The package set is checked independently of the Webmin CGI; a job request
# cannot supply packages, switches, shell snippets or other executables.
my @argv=(
    $apt, '-o', 'Dpkg::Use-Pty=0', '--yes', '--no-install-recommends',
    'install', @{$allowed{$dependency}}
);
$ENV{'DEBIAN_FRONTEND'}='noninteractive';
$ENV{'APT_LISTCHANGES_FRONTEND'}='none';
$ENV{'NEEDRESTART_MODE'}='l';  # do not automatically restart Webmin services
$ENV{'TERM'}='dumb';
$ENV{'LC_ALL'}='C';
my ($ok,$out,$err,$status)=wg_capture_subprocess(
    \@argv, '', timeout=>1800,
    max_stdout=>4_194_304, max_stderr=>524_288,
    truncate_output=>1,
);
my $output=File::Spec->catfile($job_dir,'output.log');
sysopen(my $log,$output,O_WRONLY|O_CREAT|O_TRUNC,0600)
    or die "Cannot save package output: $!\n";
binmode($log);
print {$log} $out;
print {$log} "\n--- stderr ---\n".$err if length($err);
close($log);
report(state=>($ok?'done':'failed'),error=>($ok?'':($err || 'apt-get failed')),
    exit_code=>($status < 0 ? 255 : ($status >> 8)),
    output_bytes=>(-s $output || 0));
exit($ok?0:1);
