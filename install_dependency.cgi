#!/usr/local/bin/perl
require './wireguard-lib.pl';
use File::Path qw(make_path remove_tree);
use File::Spec;
use POSIX qw(setsid _exit);

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
my $title = text('dependency_install_title', $spec->{'package'});
my $jobs_base = File::Spec->catdir(_state_dir(), 'dependency-jobs');

sub install_job_dir
{
    my ($id)=@_;
    error('Invalid installation job ID') if !valid_diagnostic_job_id($id);
    return File::Spec->catdir($jobs_base, $id);
}

sub install_job_result
{
    my ($id)=@_;
    my $dir=install_job_dir($id);
    my $request=diagnostic_read_json(File::Spec->catfile($dir,'request.json'));
    error('Installation job not found') if !$request || !-d $dir ||
        ($request->{'owner_hash'}||'') ne _request_identity();
    my $status=diagnostic_read_json(File::Spec->catfile($dir,'status.json')) ||
        {state=>'starting',created=>$request->{'created'}};
    my $state=$status->{'state'} || 'starting';
    my $age=time()-($request->{'created'}||time());
    if ($state eq 'starting' && $age>120 ||
        $state eq 'running' && $age>2400) {
        $state='failed';
        $status->{'error'}='Installation worker stopped responding';
    }
    my $output='';
    my $path=File::Spec->catfile($dir,'output.log');
    if (-f $path && -s $path <= 5_242_880) {
        $output=read_file_contents($path) || '';
    }
    return {ok=>JSON::PP::true(),state=>$state,
        done=>($state eq 'done' || $state eq 'failed')?JSON::PP::true():JSON::PP::false(),
        output=>$output,exit_code=>$status->{'exit_code'},
        error=>$status->{'error'}||'',job=>$id};
}

my $show_job = sub {
    my ($id)=@_;
    my $url=module_script_url('install_dependency.cgi',
        job=>$id, dependency=>$dependency, format=>'json');
    ui_print_header(undef,$title,'',undef,1,1);
    print '<div id="wg-dependency-job" data-status-url="'.html_escape($url).'"'.
        ' data-running="'.html_escape($text{'dependency_install_running'}||'Installation running').'"'.
        ' data-success="'.html_escape($text{'dependency_install_success_short'}||'Installation completed').'"'.
        ' data-failed="'.html_escape($text{'dependency_install_failed_short'}||'Installation failed').'">';
    print '<p><strong data-role="status">'.html_escape(
        $text{'dependency_install_running'}||'Installation running').'</strong></p>';
    print '<pre data-role="output" style="max-height:520px;overflow:auto;white-space:pre-wrap"></pre>';
    print '<p><a class="btn btn-default" href="'.html_escape($back_url).'">'.
        html_escape($text{'dependency_return'}||'Return').'</a></p></div>';
    print <<'DEPENDENCY_JOB_SCRIPT';
<script>
(function(){
    'use strict';
    const root=document.getElementById('wg-dependency-job');
    if(!root)return;
    const status=root.querySelector('[data-role="status"]');
    const output=root.querySelector('[data-role="output"]');
    async function refresh(){
        if(!root.isConnected)return;
        try{
            const response=await fetch(root.dataset.statusUrl,{
                credentials:'same-origin',cache:'no-store',headers:{Accept:'application/json'}
            });
            const data=await response.json();
            if(!data.ok)throw new Error(data.error||'Status unavailable');
            output.textContent=data.output||'';
            if(data.done){
                status.textContent=data.state==='done'?root.dataset.success:root.dataset.failed;
                if(data.error)output.textContent+='\n'+data.error;
                return;
            }
            status.textContent=root.dataset.running;
        }catch(error){status.textContent=String(error);}
        if(root.isConnected)setTimeout(refresh,2000);
    }
    refresh();
})();
</script>
DEPENDENCY_JOB_SCRIPT
    ui_print_footer($back_url,$back_label);
};

# Job progress is readable only to the user/session who started installation.
if (defined($in{'job'}) && length($in{'job'})) {
    my $result=install_job_result($in{'job'});
    if (($in{'format'}||'') eq 'json') {
        json_response($result);
    }
    else {
        $show_job->($in{'job'});
    }
    exit;
}

my $status = optional_dependency_status($dependency);
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

        # Use Webmin's complete form lifecycle. Authentic Theme can replace
        # fragments during navigation; a raw </form> bypasses its form-end
        # processing and may drop the hidden CSRF field on submission.
        print ui_form_start(module_script_url('install_dependency.cgi'), 'post');
        print csrf_hidden();
        print ui_hidden('dependency', $dependency);
        print ui_hidden('name', $name) if (length($name));
        print ui_hidden('peer', $peer) if (length("$peer"));
        print ui_hidden('confirm', 1);
        print '<button type="submit" class="btn btn-warning">'.html_escape(
            text('dependency_install_button', $spec->{'package'})
        ).'</button>';
        print ui_form_end();
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
eval { make_path($jobs_base, {mode=>0700}) if !-d $jobs_base; };
error($@ || 'Cannot create installation jobs directory')
    if $@ || !-d $jobs_base || -l $jobs_base;
chmod(0700,$jobs_base);

# Retain completed installation logs for seven days, without ever clearing
# an active job or following a symlink in the job directory.
if (opendir(my $dh,$jobs_base)) {
    while (my $item=readdir($dh)) {
        next if !valid_diagnostic_job_id($item);
        my $dir=File::Spec->catdir($jobs_base,$item);
        next if !-d $dir || -l $dir;
        my $s=diagnostic_read_json(File::Spec->catfile($dir,'status.json'))||{};
        next if ($s->{'state'}||'') =~ /^(?:running|starting)$/;
        my $updated=$s->{'updated'} || (stat($dir))[9] || time();
        remove_tree($dir) if time()-$updated>7*86400;
    }
    closedir($dh);
}

my $job_id=_secure_random_hex(32);
my $job_dir=install_job_dir($job_id);
error('Unable to allocate installation job') if !mkdir($job_dir,0700);
my ($ok,$write_error)=diagnostic_write_json(File::Spec->catfile($job_dir,'request.json'),{
    dependency=>$dependency, apt=>$apt, created=>time(),
    owner_hash=>_request_identity(),
});
if (!$ok) {
    remove_tree($job_dir);
    error($write_error||'Cannot save installation job');
}
($ok,$write_error)=diagnostic_write_json(File::Spec->catfile($job_dir,'status.json'),{
    state=>'starting',created=>time(),updated=>time()
});
if (!$ok) {
    remove_tree($job_dir);
    error($write_error||'Cannot prepare installation status');
}
my $pid=fork();
if (!defined($pid)) {
    remove_tree($job_dir);
    error("Cannot start package installer: $!");
}
if ($pid==0) {
    setsid();
    open(STDIN,'<','/dev/null');
    open(STDOUT,'>>',File::Spec->catfile($job_dir,'launcher.log'));
    open(STDERR,'>&STDOUT');
    for my $fd (3..1024) { POSIX::close($fd); }
    my $worker=File::Spec->rel2abs('dependency-worker.pl');
    exec($^X,$worker,$job_dir);
    _exit(127);
}
webmin_log('install','dependency',$dependency,{job_id=>$job_id,package=>$spec->{'package'}});
$show_job->($job_id);
