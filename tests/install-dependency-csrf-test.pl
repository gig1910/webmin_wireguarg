#!/usr/bin/env perl
# Exercise rendered GET confirmation -> form-urlencoded POST against the
# actual dependency CGI using a fake apt-get (never touches host packages).
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use File::Spec;
use JSON::PP ();
use Time::HiRes qw(sleep);
use IPC::Open3;
use Symbol qw(gensym);

chdir "$FindBin::Bin/.." or die $!;
my $dir=tempdir(CLEANUP=>1);
my $apt=File::Spec->catfile($dir,'apt-get');
my $dpkg=File::Spec->catfile($dir,'dpkg-query');
my $unavailable=File::Spec->catdir($dir,'missing-bin');
mkdir $unavailable or die $!;
for my $pair ([$apt, "#!/bin/sh\necho 'FAKE_APT_OK' \"\$@\"\nprintf 'NEEDRESTART_MODE=%s\\n' \"\$NEEDRESTART_MODE\"\nexit 0\n"],
              [$dpkg,"#!/bin/sh\nexit 1\n"]) {
    open(my $file,'>',$pair->[0]) or die $!;
    print {$file} $pair->[1];
    close($file);
    chmod(0755,$pair->[0]) or die $!;
}
sub enc {
    my ($t)=@_;$t='' if !defined($t);
    $t=~s/([^A-Za-z0-9_.~-])/sprintf("%%%02X",ord($1))/ge;
    return $t;
}
sub form_body {
    my ($fields)=@_;
    return join('&',map {enc($_).'='.enc($fields->{$_})} sort keys %$fields);
}
sub request {
    my ($method,$query,$body,$session,$origin)=@_;
    $body||='';
    local %ENV=(%ENV,
        REQUEST_METHOD=>$method,
        QUERY_STRING=>$query,
        CONTENT_TYPE=>'application/x-www-form-urlencoded',
        CONTENT_LENGTH=>length($body),
        HTTP_COOKIE=>'sid='.$session,
        HTTP_HOST=>'vpn.example.test:10000',
        HTTP_ORIGIN=>($method eq 'POST'?$origin:''),
        HTTP_REFERER=>($method eq 'POST'?'https://vpn.example.test:10000/wireguard/install_dependency.cgi':''),
        REMOTE_USER=>'integration-test',
        REMOTE_ADDR=>'192.0.2.10',
        WEBMIN_TEST_STATE_DIR=>File::Spec->catdir($dir,'state'),
        WEBMIN_TEST_ACL=>'view=1,manage=1,install_dependencies=1',
        TEST_APT=>$apt,TEST_DPKG=>$dpkg,TEST_NOT_INSTALLED=>$unavailable,
        PERL5LIB=>'tests/stub',
    );
    my $err=gensym;
    my $pid=open3(my $in,my $out,$err,$^X,'tests/install-dependency-csrf-fixture.pl');
    binmode $in;print {$in} $body;close $in;
    local $/;
    my $html=<$out>//'';
    my $errors=<$err>//'';
    close $out;close $err;
    waitpid($pid,0);
    return ($?,$html,$errors);
}

for my $dependency (qw(qrencode geoip)) {
    my ($status,$html,$err)=request(
        'GET','dependency='.$dependency.'&name=wg0&peer=0','','test-session',''
    );
    die "$dependency confirmation GET failed: $err\n" if $status!=0;
    my ($form)=$html=~m{(<form\b[^>]*>.*?</form>)}s;
    die "$dependency confirmation form missing\n" unless $form;
    die "$dependency confirmation POST action is not module-absolute\n"
        unless $form =~ m{action="/wireguard/install_dependency\.cgi\?};
    die "$dependency form method is not POST\n" unless $form =~ /method="post"/;
    my %hidden;
    while ($form=~m{<input type="hidden" name="([^"]+)" value="([^"]*)">}g) {
        $hidden{$1}=$2;
    }
    die "$dependency GET did not render a same-form CSRF token\n"
        unless ($hidden{'_wg_csrf'}||'')=~/^[a-f0-9]{64}$/;
    die "$dependency missing confirmation/peer identity fields\n"
        unless $hidden{'confirm'} eq '1' && $hidden{'dependency'} eq $dependency &&
               $hidden{'name'} eq 'wg0' && $hidden{'peer'} eq '0';
    ($status,$html,$err)=request('POST','',form_body(\%hidden),
        'test-session','https://vpn.example.test:10000');
    die "$dependency POST rejected valid token: $err\n"
        unless $status==0 && $html=~/data-status-url=/;
    my ($job_id)=$html=~/\bjob=([a-f0-9]{64})/;
    die "$dependency install job ID missing\n" unless $job_id;
    my $job_dir=File::Spec->catdir($dir,'state','dependency-jobs',$job_id);
    my $result;
    for (1..120) {
        my $file=File::Spec->catfile($job_dir,'status.json');
        if (-r $file) {
            open(my $fh,'<',$file) or die $!;
            local $/; my $raw=<$fh>; close($fh);
            $result=eval { JSON::PP::decode_json($raw) };
            last if $result && ($result->{'state'}||'') =~ /^(?:done|failed)$/;
        }
        sleep(0.1);
    }
    die "$dependency asynchronous installation did not finish\n"
        unless $result && ($result->{'state'}||'') eq 'done';
    my $log=File::Spec->catfile($job_dir,'output.log');
    open(my $fh,'<',$log) or die "$log: $!";
    local $/; my $output=<$fh>; close($fh);
    die "$dependency fake apt output missing\n"
        unless $output=~/FAKE_APT_OK/;
    die "$dependency installer must prevent automatic service restarts\n"
        unless $output =~ /NEEDRESTART_MODE=l\b/;
    die "$dependency allowed unexpected package injection\n"
        if $output =~ /FAKE_APT_OK.*(?:curl|sudo|sh -c)/;
    if($dependency eq 'geoip'){
        die "GeoIP fixed apt package set missing\n"
            unless $output=~/FAKE_APT_OK.*geoipupdate.*mmdb-bin.*geoip-bin.*geoip-database.*whois/s;
    }
    else{
        die "QR fixed apt package missing\n"
            unless $output=~/FAKE_APT_OK.*qrencode/;
    }
    ($status,$html,$err)=request('GET',
        'dependency='.$dependency.'&job='.$job_id.'&format=json',
        '', 'test-session','');
    die "$dependency owner cannot read install result: $err\n"
        unless $status==0 && $html=~/FAKE_APT_OK/;
    ($status,$html,$err)=request('GET',
        'dependency='.$dependency.'&job='.$job_id.'&format=json',
        '', 'different-session','');
    die "$dependency foreign session read installation output\n" if $status==0;

    my %tampered=%hidden;
    $tampered{'_wg_csrf'}='0'x64;
    ($status,$html,$err)=request('POST','',form_body(\%tampered),
        'test-session','https://vpn.example.test:10000');
    die "$dependency tampered CSRF unexpectedly executed\n"
        if $status==0 || $html=~/FAKE_APT_OK/;
    ($status,$html,$err)=request('POST','',form_body(\%hidden),
        'different-session','https://vpn.example.test:10000');
    die "$dependency foreign-session CSRF unexpectedly executed\n"
        if $status==0 || $html=~/FAKE_APT_OK/;
    ($status,$html,$err)=request('POST','',form_body(\%hidden),
        'test-session','https://another.example.test');
    die "$dependency cross-origin POST unexpectedly executed\n"
        if $status==0 || $html=~/FAKE_APT_OK/;
}
print "dependency confirmation GET/POST CSRF and package whitelist tests passed\n";
