#!/usr/local/bin/perl
require './wireguard-lib.pl';
use IO::Select;
use IPC::Open3;
use Symbol qw(gensym);

ReadParse();
assert_view_access();
assert_install_dependencies_access();

my $dependency = $in{'dependency'} || 'qrencode';
my $spec = optional_dependency_spec($dependency);
error($text{'dependency_invalid'}) if (!$spec);

my $name = $in{'name'} || '';
$name = '' if (length($name) && !valid_interface_name($name));
my $peer = defined($in{'peer'}) && $in{'peer'} =~ /^\d+$/ ? int($in{'peer'}) : '';
my $back_url = length($name)
    ? 'edit_peer.cgi?name='.urlize($name).(length("$peer") ? '&peer='.urlize($peer) : '')
    : 'index.cgi';
my $back_label = length($name) ? text('interface_title', $name) : $text{'index_title'};

my $status = optional_dependency_status($dependency);
my $title = text('dependency_install_title', $spec->{'package'});

if (($ENV{'REQUEST_METHOD'} || 'GET') ne 'POST') {
    ui_print_header(undef, $title, '', undef, 1, 1);

    if ($status->{'command_available'}) {
        print '<div class="alert alert-success">'.html_escape(
            text('dependency_command_available', $status->{'command'})
        ).'</div>';
        if ($status->{'package_installed'}) {
            print '<p>'.html_escape(text('dependency_package_version', $status->{'package_version'})).'</p>';
        }
    }
    elsif ($status->{'package_installed'}) {
        print '<div class="alert alert-warning">'.html_escape(
            text('dependency_package_installed_path_missing', $status->{'package_version'}, $status->{'command'})
        ).'</div>';
        print '<p>'.ui_link_button('config.cgi', $text{'dependency_open_settings'}).'</p>';
    }
    elsif (!$status->{'package_manager_available'}) {
        print '<div class="alert alert-danger">'.html_escape($text{'dependency_package_manager_missing'}).'</div>';
    }
    else {
        print '<div class="alert alert-warning"><b>'.html_escape($text{'dependency_confirm_heading'}).'</b><br>'.
            html_escape(text('dependency_confirm_text', $spec->{'package'})).'</div>';
        print '<p><b>'.html_escape($text{'dependency_package'}).':</b> '.html_escape($spec->{'package'}).'<br>'.
            '<b>'.html_escape($text{'dependency_command_path'}).':</b> '.html_escape($status->{'command'}).'</p>';

        print ui_form_start('install_dependency.cgi', 'post'); print csrf_hidden();
        print ui_hidden('dependency', $dependency);
        print ui_hidden('name', $name) if (length($name));
        print ui_hidden('peer', $peer) if (length("$peer"));
        print ui_hidden('confirm', 1);
        print '<button type="submit" class="btn btn-warning">'.html_escape(
            text('dependency_install_button', $spec->{'package'})
        ).'</button></form>';
    }

    ui_print_footer($back_url, $back_label);
    exit;
}

assert_post_and_csrf();
request_rate_limit('install_dependency', 3, 300);
error($text{'dependency_post_required'}) if (!$in{'confirm'});
error($text{'dependency_already_available'}) if ($status->{'command_available'});
error($text{'dependency_package_manager_missing'}) if (!$status->{'package_manager_available'});

my $apt = $status->{'apt_command'};
require_command($apt);
my @argv = (
    $apt,
    '-o', 'Dpkg::Use-Pty=0',
    '--yes',
    '--no-install-recommends',
    'install',
    $spec->{'package'},
);

ui_print_header(undef, $title, '', undef, 1, 1);
print '<div class="alert alert-info">'.html_escape(
    text('dependency_install_running', $spec->{'package'})
).'</div>';
print '<pre style="min-height:180px;max-height:520px;overflow:auto;white-space:pre-wrap" id="dependency-output">';
$| = 1;

my ($writer, $reader);
my $stderr = gensym();
my $pid;
my $spawn_error = '';
my $exit_status = 255;
{
    local $ENV{'DEBIAN_FRONTEND'} = 'noninteractive';
    local $ENV{'APT_LISTCHANGES_FRONTEND'} = 'none';
    local $ENV{'NEEDRESTART_MODE'} = 'a';
    local $ENV{'TERM'} = 'dumb';
    local $ENV{'LC_ALL'} = 'C';

    eval {
        $pid = open3($writer, $reader, $stderr, @argv);
        close($writer) if ($writer);
        my $select = IO::Select->new($reader, $stderr);
        while ($select->count()) {
            foreach my $fh ($select->can_read(1)) {
                my $line = <$fh>;
                if (!defined($line)) {
                    $select->remove($fh);
                    close($fh);
                    next;
                }
                $line =~ s/\e\[[0-9;?]*[ -\/]*[@-~]//g;
                $line =~ s/\r/\n/g;
                print html_escape($line);
            }
        }
        waitpid($pid, 0);
        $exit_status = $?;
    };
    $spawn_error = $@ || '' if ($@);
}

if (length($spawn_error)) {
    print "\n".html_escape($spawn_error);
}
print '</pre>';

my $exit_code = $exit_status == -1 ? 255 : ($exit_status >> 8);
my $after = optional_dependency_status($dependency);
my $success = !$spawn_error && $exit_status == 0 && $after->{'command_available'};

webmin_log(
    'install', 'dependency', $dependency,
    {
        'package' => $spec->{'package'},
        'exit_code' => $exit_code,
        'command_available' => $after->{'command_available'} ? 1 : 0,
    }
);

if ($success) {
    print '<div class="alert alert-success">'.html_escape(
        text('dependency_install_success', $spec->{'package'}, $after->{'command'})
    ).'</div>';
}
elsif (!$spawn_error && $exit_status == 0 && !$after->{'command_available'}) {
    print '<div class="alert alert-warning">'.html_escape(
        text('dependency_install_path_failed', $spec->{'package'}, $after->{'command'})
    ).'</div>';
    print '<p>'.ui_link_button('config.cgi', $text{'dependency_open_settings'}).'</p>';
}
else {
    print '<div class="alert alert-danger">'.html_escape(
        text('dependency_install_failed', $spec->{'package'}, $exit_code)
    ).'</div>';
}

print '<p>'.ui_link_button($back_url, $text{'dependency_return'}).'</p>';
ui_print_footer($back_url, $back_label);
