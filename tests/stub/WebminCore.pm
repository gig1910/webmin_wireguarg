package WebminCore;
use Exporter 'import';
use JSON::PP ();
use Scalar::Util qw(blessed);
our @EXPORT = qw(init_config get_module_acl lock_file unlock_file read_file_contents backquote_with_timeout has_command text error ReadParse webmin_log urlize get_webprefix html_escape encode_json decode_json);

# Model the conflicting JSON helpers exported by current WebminCore versions.
# In particular, blessed JSON::PP booleans may be stringified by this helper.
sub _webmin_json_value {
    my ($value) = @_;
    return "$value" if blessed($value);
    return [ map { _webmin_json_value($_) } @$value ] if ref($value) eq 'ARRAY';
    if (ref($value) eq 'HASH') {
        return { map { $_ => _webmin_json_value($value->{$_}) } keys %$value };
    }
    return $value;
}
sub encode_json { return JSON::PP::encode_json(_webmin_json_value($_[0])); }
sub decode_json { return JSON::PP::decode_json($_[0]); }

sub init_config {
    no strict 'refs';
    ${"main::text"}{'diagnostics_completed_ok'} = 'Command completed successfully.';
    ${"main::text"}{'diagnostics_completed_error'} = 'Command exited with code $1.';
    ${"main::text"}{'diagnostics_completed_signal'} = 'Command was stopped by signal $1.';
    return 1;
}
sub ReadParse {
    no strict 'refs';
    my %parsed;
    foreach my $pair (split(/&/, $ENV{'QUERY_STRING'} || '')) {
        my ($key, $value) = split(/=/, $pair, 2);
        for ($key, $value) {
            $_ = '' if !defined($_);
            tr/+/ /;
            s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        }
        $parsed{$key} = $value;
    }
    %{"main::in"} = %parsed;
    return 1;
}
sub webmin_log { return 1; }
sub urlize { my ($v)=@_; $v='' if !defined($v); $v =~ s/([^A-Za-z0-9_.~-])/sprintf("%%%02X",ord($1))/eg; return $v; }
sub get_webprefix { return ''; }
sub html_escape { my ($v)=@_; $v='' if !defined($v); $v =~ s/&/&amp;/g; $v =~ s/</&lt;/g; $v =~ s/>/&gt;/g; $v =~ s/"/&quot;/g; $v =~ s/'/&#39;/g; return $v; }
sub get_module_acl {
    my %acl = (view=>1,manage=>1,export_clients=>1,diagnostics=>1,logs=>1,install_dependencies=>1);
    if (defined($ENV{'WEBMIN_TEST_ACL'})) {
        foreach my $pair (split(/,/, $ENV{'WEBMIN_TEST_ACL'})) {
            my ($k,$v)=split(/=/,$pair,2);
            $acl{$k}=0+($v||0) if defined($k) && exists($acl{$k});
        }
    }
    return %acl;
}
sub lock_file { 1 }
sub unlock_file { 1 }
sub read_file_contents { my($p)=@_; open(my$fh,'<',$p) or return undef; local$/; my$s=<$fh>;close$fh;$s }
sub backquote_with_timeout { my ($cmd) = @_; my $out = `$cmd`; return $out; }
sub has_command { -x $_[0] }
sub text { my($k,@a)=@_; join(' ',grep{defined}@a)?$k.' '.join(' ',@a):$k }
sub error { die $_[0] }
1;
