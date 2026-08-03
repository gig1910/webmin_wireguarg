#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

sub slurp {
    my ($path)=@_;
    open(my $fh,'<',$path) or die "$path: $!\n";
    local $/; my $s=<$fh>; close($fh); return $s;
}
my $root = "$FindBin::Bin/..";
my %mutators = (
    'action_all.cgi' => 'manage',
    'action_interface.cgi' => 'manage',
    'save_interface.cgi' => 'manage',
    'save_peer.cgi' => 'manage',
    'delete_interface.cgi' => 'manage',
    'delete_peer.cgi' => 'manage',
    'toggle_peer.cgi' => 'manage',
    'diagnostic.cgi' => 'diagnostics',
    'diagnostic_stop.cgi' => 'diagnostics',
    'install_dependency.cgi' => 'install_dependencies',
    'collector_status.cgi' => 'manage',
);
for my $file (sort keys %mutators) {
    my $src = slurp("$root/$file");
    die "$file has no POST+CSRF enforcement\n" if $src !~ /assert_post_and_csrf\s*\(/;
    my $acl = $mutators{$file};
    if ($acl eq 'manage') {
        die "$file has no manage ACL check\n" if $src !~ /assert_manage_access\s*\(/ && $src !~ /\$access\{'manage'\}/;
    }
    elsif ($acl eq 'diagnostics') {
        die "$file has no diagnostics ACL check\n" if $src !~ /assert_diagnostics_access\s*\(/;
    }
    elsif ($acl eq 'install_dependencies') {
        die "$file has no dependency-install ACL check\n" if $src !~ /assert_install_dependencies_access\s*\(/;
    }
}
for my $file (qw(client_config.cgi download_client.cgi peer_qr.cgi qr_image.cgi)) {
    my $src = slurp("$root/$file");
    die "$file exports private material without export ACL\n" if $src !~ /assert_export_access\s*\(/;
}
for my $file (qw(runtime.cgi history.cgi stats.cgi index.cgi edit_interface.cgi edit_peer.cgi)) {
    my $src = slurp("$root/$file");
    die "$file lacks view ACL\n" if $src !~ /assert_view_access\s*\(/;
}
my $all = join("\n", map { slurp("$root/$_") } keys %mutators);
die "private key appears in action logs\n" if $all =~ /webmin_log\([^\n]*private_key/i;
my $api = slurp("$root/lib/security-lib.pl");
die "CSRF token is not random\n" if $api !~ m{/dev/urandom};
die "CSRF comparison is not constant-time style\n" if $api !~ /\$diff\s*\|=/;
die "request limiter missing file locking\n" if $api !~ /flock\(\$fh,\s*LOCK_EX\)/;
my $default_acl = slurp("$root/defaultacl");
for my $key (qw(view manage export_clients diagnostics logs install_dependencies)) {
    die "defaultacl missing $key\n" if $default_acl !~ /^\Q$key\E=/m;
}
my $cmd = "WEBMIN_TEST_ACL='view=1,manage=0,export_clients=0,diagnostics=0,logs=0,install_dependencies=0' PERL5LIB='$FindBin::Bin/stub' $^X -I'$root' -e 'require q{$root/wireguard-lib.pl}; assert_view_access(); eval { assert_manage_access() }; exit(\$@ ? 0 : 1)'";
system($cmd) == 0 or die "read-only ACL did not deny manage access\n";
print "security and ACL regression tests passed\n";
