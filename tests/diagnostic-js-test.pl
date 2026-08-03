#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

open(my $fh, '<', "$FindBin::Bin/../edit_peer.cgi") or die $!;
my $source;
{ local $/; $source = <$fh>; }
close($fh);
my ($script) = $source =~ /print <<SCRIPT;\n(<script>.*?async function poll\(\).*?<\/script>)\nSCRIPT/s;
die "diagnostic JavaScript block not found\n" if !defined($script);
$script =~ s/^<script>\n?//;
$script =~ s/\n?<\/script>$//;
$script =~ s/\$js_(?:diagnostic_url|status_url|stop_url)/"\/wireguard\/diagnostic.cgi"/g;
$script =~ s/\$js_diag_dom_id/"wg-diag-test"/g;
$script =~ s/\$js_(?:name|peer|starting|stopping|stopped)/"test"/g;
my $node = `command -v node 2>/dev/null`;
chomp($node);
if ($node) {
    # First validate the source template after placeholder substitution.
    my $path = "$FindBin::Bin/diagnostic-script-$$.js";
    open(my $out, '>', $path) or die $!;
    print {$out} $script;
    close($out);
    system($node, '--check', $path) == 0 or die "diagnostic JavaScript template syntax check failed\n";
    unlink($path);

    # Then execute the same interpolating Perl heredoc used by edit_peer.cgi.
    # This catches escapes such as \n and \s being consumed by Perl before the
    # JavaScript reaches Authentic Theme.
    my ($render_block) = $source =~ /print <<SCRIPT;\n(<script>.*?async function poll\(\).*?<\/script>)\nSCRIPT/s;
    die "diagnostic JavaScript render block not found\n" if !defined($render_block);
    my $renderer = "$FindBin::Bin/diagnostic-render-$$.pl";
    my $rendered_html = "$FindBin::Bin/diagnostic-render-$$.html";
    my $rendered_js = "$FindBin::Bin/diagnostic-render-$$.js";
    open(my $render, '>', $renderer) or die $!;
    print {$render} <<'PRELUDE';
use strict;
use warnings;
my $js_diag_dom_id = '"wg-diag-test"';
my $js_diagnostic_url = '"/wireguard/diagnostic.cgi"';
my $js_status_url = '"/wireguard/diagnostic_status.cgi"';
my $js_stop_url = '"/wireguard/diagnostic_stop.cgi"';
my $js_name = '"wg0"';
my $js_peer = '"0"';
my $js_starting = '"Starting"';
my $js_stopping = '"Stopping"';
my $csrf = 'testcsrf';
print <<SCRIPT;
PRELUDE
    print {$render} $render_block, "\nSCRIPT\n";
    close($render);
    system("$^X $renderer > $rendered_html") == 0 or die "cannot render diagnostic JavaScript heredoc\n";
    open(my $html_fh, '<', $rendered_html) or die $!;
    my $rendered;
    { local $/; $rendered = <$html_fh>; }
    close($html_fh);
    $rendered =~ s/^<script>\n?//;
    $rendered =~ s/\n?<\/script>\n?$//;
    die "rendered whitespace regular expression was corrupted\n" if $rendered !~ m{replace\(/\\s\+/g};
    die "rendered newline escape was corrupted\n" if $rendered !~ /append\('\\n'/;
    open(my $rendered_out, '>', $rendered_js) or die $!;
    print {$rendered_out} $rendered;
    close($rendered_out);
    system($node, '--check', $rendered_js) == 0 or die "rendered diagnostic JavaScript syntax check failed\n";
    unlink($renderer, $rendered_html, $rendered_js);
}
die "diagnostic UI still depends on streaming fetch reader\n" if $script =~ /response\.body\.getReader/;
die "diagnostic UI does not poll status endpoint\n" if $script !~ /diagnostic_status/ && $source !~ /diagnostic_status\.cgi/;
die "diagnostic UI has no stop endpoint\n" if $source !~ /diagnostic_stop\.cgi/;
die "diagnostic UI has no request-specific root\n" if $source !~ /my \$diag_dom_id =/;
die "diagnostic UI still uses global diagnostic element IDs\n" if $source =~ /id="wg-diag-(?:target|count|port|infinite|stop|output)"/;
die "diagnostic UI still queries diagnostic controls globally\n" if $script =~ /document\.querySelectorAll\([^\n]*data-diag/ || $script =~ /document\.getElementById\([^\n]*wg-diag-(?:target|count|port|infinite|stop|output)/;
die "diagnostic UI does not scope controls to its root\n" if $script !~ /root\.querySelector/ || $script !~ /root\.addEventListener/;
die "diagnostic Stop still uses a direct button listener\n" if $source =~ /stopButton\.addEventListener\s*\(\s*['"]click/;
die "diagnostic Stop is not delegated from the stable root\n" if $script !~ /button\[data-role=[\"']stop[\"']\]/ || $script !~ /root\.addEventListener\s*\(\s*['"]click/;
print "diagnostic JavaScript polling tests passed\n";
