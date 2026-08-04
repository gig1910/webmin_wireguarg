=head1 wireguard-lib.pl

Shared functions for the WireGuard Webmin module.

=cut

BEGIN { push(@INC, '..'); }
use WebminCore qw(:DEFAULT !encode_json !decode_json);
use File::Basename qw(basename dirname);
use File::Spec;
use File::Path qw(make_path);
use Fcntl qw(:DEFAULT :flock SEEK_SET SEEK_END);
use IPC::Open3;
use Symbol qw(gensym);
use MIME::Base64 ();
use Digest::SHA qw(sha256_hex);
use JSON::PP ();
use Encode qw(decode FB_CROAK);
use Scalar::Util qw(blessed);
use POSIX qw(strftime);
use Socket qw(AF_INET AF_INET6 inet_pton inet_ntop);

# Keep compatibility for shared module code that uses these names, while
# preventing WebminCore's JSON helpers from taking precedence. Typeglob aliases
# preserve JSON::PP's own prototypes and avoid prototype-mismatch warnings.
BEGIN {
    no warnings 'redefine';
    *encode_json = \&JSON::PP::encode_json;
    *decode_json = \&JSON::PP::decode_json;
}


init_config();
our %access = get_module_acl();
$access{'export_clients'} = $access{'reveal_keys'} if (!exists($access{'export_clients'}) && exists($access{'reveal_keys'}));
$access{'install_dependencies'} = $access{'manage'} if (!exists($access{'install_dependencies'}));


# Split by responsibility.  These files intentionally share the Webmin module
# package and globals for backwards compatibility with existing CGI programs.
require './lib/security-lib.pl';
require './lib/ip-lib.pl';
require './lib/command-lib.pl';
require './lib/config-lib.pl';
require './lib/runtime-lib.pl';
require './lib/api-ui-lib.pl';
require './lib/collector-config-lib.pl';
require './lib/metrics-lib.pl';
require './lib/preshared-key-lib.pl';
require './lib/version-lib.pl';

1;
