#!/usr/local/bin/perl
require './wireguard-lib.pl';
require './lib/analytics-page-ui-lib.pl';
ReadParse();
assert_view_access();

ui_print_header(undef,$text{'analytics_title'},'',undef,1,1);
print wg_build_banner();
print '<ul class="nav nav-tabs" style="margin-bottom:15px"><li><a href="index.cgi">'.
    html_escape($text{'analytics_interfaces_tab'}).'</a></li><li class="active"><a href="analytics.cgi">'.
    html_escape($text{'analytics_title'}).'</a></li></ul>';
my $settings = collector_effective_settings(\%config);
print ui_alert_box(html_escape($text{'analytics_error_disabled'}),'warning')
    if (!$settings->{'analytics_enabled'});
my $url = html_escape(module_script_url('analytics_data.cgi'));
my $selected = $in{'peer_id'} || '';
$selected = '' if ($selected !~ /^[a-f0-9]{64}$/);
my $selected_json = json_encode_utf8($selected);
my $initial_interface = $in{'interface'} || '';
$initial_interface = '' if $initial_interface && !valid_interface_name($initial_interface);
my $initial_interface_json = json_encode_utf8($initial_interface);
my %labels = map { $_ => $text{$_} || $_ } qw(
    analytics_all_peers analytics_empty analytics_loading analytics_rx analytics_tx
    analytics_truncated analytics_partial analytics_warning analytics_first_seen
    analytics_last_seen analytics_peer_active analytics_peer_inactive
    analytics_events_limited analytics_db_size analytics_bucket_note
    analytics_resets analytics_gaps
    analytics_event_first_seen analytics_event_endpoint_observed
    analytics_event_endpoint_changed analytics_event_handshake_observed
    analytics_event_active analytics_event_inactive analytics_event_interface_changed
    analytics_event_counter_reset analytics_event_sample_gap
    analytics_event_legacy_history_imported
    analytics_last_handshake analytics_handshake_ip analytics_no_handshake
    analytics_event_endpoint_ip_observed analytics_event_endpoint_ip_changed
    analytics_graph_rx analytics_graph_tx analytics_graph_empty analytics_graph_scale
    analytics_filters_heading analytics_summary_heading analytics_interface
    analytics_all_interfaces analytics_peer_open analytics_maintenance_warning
    analytics_6h analytics_month analytics_quarter analytics_halfyear analytics_year
    analytics_auto_refresh analytics_auto_off analytics_auto_10m analytics_auto_30m
    analytics_auto_custom_note analytics_graph_zero analytics_error_time
    analytics_tab_graph analytics_tab_events
);
my $strings = json_encode_utf8(\%labels);
print wg_table_sort_script();
print wg_chart_ui_script();
print wg_ui_transport_script();
print <<HTML;
<div id="wg-analytics" data-url="$url">
 <section class="panel panel-default wg-analytics-section">
  <div class="panel-heading"><strong>$text{'analytics_filters_heading'}</strong></div>
  <div class="panel-body">
 <div class="wg-analytics-filters">
  <label>$text{'analytics_interface'} <select class="form-control" data-interface><option value="">$text{'analytics_all_interfaces'}</option></select></label>
  <label>$text{'analytics_peer'} <select class="form-control" data-peer></select></label>
  <label>$text{'analytics_period'} <select class="form-control" data-period>
   <option value="21600">$text{'analytics_6h'}</option>
   <option value="86400" selected>$text{'analytics_24h'}</option>
   <option value="604800">$text{'analytics_7d'}</option>
   <option value="month">$text{'analytics_month'}</option>
   <option value="quarter">$text{'analytics_quarter'}</option>
   <option value="halfyear">$text{'analytics_halfyear'}</option>
   <option value="year">$text{'analytics_year'}</option>
   <option value="custom">$text{'analytics_custom'}</option>
  </select></label>
  <span data-custom hidden>
   <label>$text{'analytics_from'} <input type="datetime-local" class="form-control" data-from></label>
   <label>$text{'analytics_to'} <input type="datetime-local" class="form-control" data-to></label>
  </span>
  <label>$text{'analytics_auto_refresh'} <select class="form-control" data-auto-refresh>
    <option value="0" selected>$text{'analytics_auto_off'}</option>
    <option value="600">$text{'analytics_auto_10m'}</option>
    <option value="1800">$text{'analytics_auto_30m'}</option>
  </select></label>
  <button class="btn btn-default" data-apply type="button">$text{'analytics_apply'}</button>
 </div>
 <p class="help-block" data-auto-custom-note hidden>$text{'analytics_auto_custom_note'}</p>
 <div data-error class="alert alert-warning" hidden></div>
  </div>
 </section>
 <section class="panel panel-default wg-analytics-section">
  <div class="panel-heading"><strong>$text{'analytics_summary_heading'}</strong></div>
  <div class="panel-body">
   <div class="wg-analytics-summary">
    <div class="wg-analytics-summary-item" data-rx></div>
    <div class="wg-analytics-summary-item" data-tx></div>
    <div class="wg-analytics-summary-item" data-last-handshake></div>
    <div class="wg-analytics-summary-item" data-handshake-ip></div>
   </div>
   <p class="help-block" data-db-size></p>
  </div>
 </section>
 <ul class="nav nav-tabs wg-analytics-subtabs" role="tablist" aria-label="$text{'analytics_title'}">
  <li class="active" role="presentation"><a href="#wg-analytics-chart-pane" role="tab" aria-controls="wg-analytics-chart-pane" aria-selected="true" data-wg-analytics-tab="graph">$text{'analytics_tab_graph'}</a></li>
  <li role="presentation"><a href="#wg-analytics-events-pane" role="tab" aria-controls="wg-analytics-events-pane" aria-selected="false" data-wg-analytics-tab="events">$text{'analytics_tab_events'}</a></li>
 </ul>
 <div id="wg-analytics-chart-pane" data-wg-analytics-pane="graph" role="tabpanel">
 <section class="panel panel-default wg-analytics-section">
  <div class="panel-heading"><strong>$text{'analytics_chart'}</strong></div>
  <div class="panel-body">
 <div class="wg-analytics-chart-legend">
   <span class="wg-analytics-dot wg-analytics-tx-dot"></span> $text{'analytics_graph_tx'}
   <span class="wg-analytics-dot wg-analytics-rx-dot"></span> $text{'analytics_graph_rx'}
   <small data-chart-scale></small>
 </div>
 <div class="wg-analytics-chart" data-chart role="img" aria-label="$text{'analytics_chart'}">
   <svg class="wg-traffic-canvas wg-analytics-svg" data-chart-svg width="100%" height="300" role="presentation"></svg>
 </div>
 <div data-notes class="wg-analytics-notes help-block"></div>
 <p class="help-block">$text{'analytics_bucket_note'}</p>
  </div>
 </section>
 </div>
 <div id="wg-analytics-events-pane" data-wg-analytics-pane="events" role="tabpanel" hidden>
 <section class="panel panel-default wg-analytics-section">
  <div class="panel-heading"><strong>$text{'analytics_events'}</strong></div>
  <div class="panel-body">
 <div class="table-responsive wg-analytics-table" data-wg-event-sort-table><table class="table table-striped table-hover">
 <thead><tr><th>$text{'analytics_event_time'}</th><th>$text{'analytics_peer'}</th><th>$text{'analytics_event_type'}</th><th>$text{'analytics_event_endpoint'}</th><th>$text{'analytics_event_previous'}</th></tr></thead>
 <tbody data-events></tbody></table></div>
 <p class="help-block">$text{'analytics_warning'}</p>
  </div>
 </section>
 </div>
</div>
<style>
/* Theme-native panels, form controls and responsive tables; only layout
   dimensions are local. No independent analytics color palette. */
.wg-analytics-subtabs{margin:14px 0 0}
.wg-analytics-subtabs>li>a{cursor:pointer}
.wg-analytics-section{margin:12px 0}
.wg-analytics-section>.panel-heading{padding:8px 10px}
.wg-analytics-section>.panel-body{padding:12px}
.wg-analytics-filters{display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end}
.wg-analytics-filters label{display:flex;flex-direction:column;gap:4px;margin:0}
.wg-analytics-filters select,.wg-analytics-filters input{min-width:150px;max-width:100%}
.wg-analytics-filters [data-peer]{min-width:260px}
.wg-analytics-filters [data-custom]{display:flex;flex-wrap:wrap;gap:10px}
.wg-analytics-filters [hidden],#wg-analytics [hidden]{display:none!important}
.wg-analytics-summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px}
.wg-analytics-summary-item{padding:9px 12px;border:1px solid rgba(127,127,127,.25);border-radius:3px}
.wg-analytics-summary-item:empty::after{content:'—'}
.wg-analytics-notes{margin-top:8px}
.wg-analytics-table{overflow:auto;max-height:420px}
.wg-analytics-table table{width:100%;margin:0}
.wg-analytics-table td,.wg-analytics-table th{vertical-align:middle}
.wg-analytics-peer-link{color:inherit;text-decoration:underline}
.wg-analytics-steps{display:flex;flex-wrap:wrap;gap:10px;align-items:flex-end}
.wg-analytics-steps form{display:flex;flex-wrap:wrap;align-items:flex-end;gap:8px;margin:4px 0}
.wg-analytics-steps label{display:flex;flex-direction:column;gap:4px;margin:0}
.wg-analytics-steps input,.wg-analytics-steps select{max-width:260px}
.wg-analytics-danger{border-color:rgba(190,50,40,.45)}
\@media(max-width:700px){.wg-analytics-filters label,.wg-analytics-filters [data-peer],
.wg-analytics-steps label{width:100%;min-width:0}}
.wg-analytics-chart{display:block;width:100%;min-height:300px}
.wg-analytics-svg{display:block;width:100%;height:300px;border:1px solid rgba(127,127,127,.25);
  border-radius:4px;overflow:hidden}
.wg-analytics-chart-legend,.wg-analytics-chart-axis{display:flex;align-items:center;gap:8px;margin:8px 0}
.wg-analytics-chart-legend small{margin-left:auto;opacity:.85}
.wg-analytics-chart-axis{justify-content:space-between;font-size:12px;opacity:.85}
.wg-analytics-dot{display:inline-block;width:10px;height:10px;border-radius:2px}
.wg-analytics-rx-dot{background-color:var(--success-color,#42a878)}
.wg-analytics-tx-dot{background-color:var(--primary-color,#4f8dd6)}
</style>
HTML
print wg_analytics_controller_script($strings, $selected_json, $initial_interface_json);

if ($access{'manage'}) {
    print '<section class="panel panel-default wg-analytics-section wg-analytics-danger wg-danger-zone">'.
          '<div class="panel-heading"><strong>'.html_escape($text{'danger_zone'}).
          ' — '.html_escape($text{'analytics_maintenance'}).'</strong></div>'.
          '<div class="panel-body"><p class="help-block">'.html_escape($text{'analytics_maintenance_help'}).
          '</p><div class="wg-analytics-steps">';
    for my $item (
        [ 'delete_before', 'analytics_delete_before' ],
        [ 'delete_peer', 'analytics_delete_peer' ],
        [ 'purge', 'analytics_purge' ],
        [ 'vacuum', 'analytics_vacuum' ]
    ) {
        my ($action, $key) = @$item;
        print ui_form_start('analytics_maintenance.cgi','post'), csrf_hidden();
        print ui_hidden('action',$action);
        if ($action eq 'delete_before') {
            print '<label>'.html_escape($text{'analytics_to'}).
                ' <input type="datetime-local" class="form-control" data-maintenance-before></label> ';
            print '<input type="hidden" name="before" data-maintenance-epoch>';
        }
        if ($action eq 'delete_peer') {
            print '<label>'.html_escape($text{'analytics_peer'}).
                ' <select name="peer_id" class="form-control" data-maintenance-peer></select></label> ';
        }
        if ($action ne 'vacuum') {
            print '<label>'.html_escape($text{'analytics_confirm'}).
                ' <input name="confirm" class="form-control" autocomplete="off" placeholder="DELETE" required></label> ';
        }
        my $button_class = $action eq 'vacuum' ? 'btn btn-default' : 'btn btn-danger';
        print '<button type="submit" class="'.$button_class.'">'.html_escape($text{$key}).'</button>';
        print '</form>';
    }
    print '</div></div></section>';
    print <<'SCRIPT';
<script>
(function(){
 const root=document.getElementById('wg-analytics');
 const peer=root.querySelector('[data-peer]');
 const chooser=document.querySelector('[data-maintenance-peer]');
 if(chooser){
  const sync=()=>{
   const chosen=chooser.value;
   chooser.replaceChildren();
   for(const src of peer.options)if(src.value){
    const opt=document.createElement('option');opt.value=src.value;
    opt.textContent=src.textContent;chooser.append(opt);
   }
   if(chosen)chooser.value=chosen;
  };
  new MutationObserver(sync).observe(peer,{childList:true});sync();
 }
 for(const form of document.querySelectorAll('form[action="analytics_maintenance.cgi"]')){
  form.addEventListener('submit',e=>{
   const date=form.querySelector('[data-maintenance-before]');
   if(date){
    const stamp=Math.floor(new Date(date.value).getTime()/1000);
    if(!Number.isFinite(stamp)||stamp<=0||stamp>Date.now()/1000){e.preventDefault();return;}
    form.querySelector('[data-maintenance-epoch]').value=String(stamp);
   }
   const action=form.querySelector('[name="action"]').value;
   if(action==='delete_peer' && !form.querySelector('[name="peer_id"]').value){e.preventDefault();return;}
   if(action!=='vacuum' && form.querySelector('[name="confirm"]').value!=='DELETE'){e.preventDefault();return;}
   if(!window.confirm('Proceed with analytics storage maintenance?'))e.preventDefault();
  });
 }
})();
</script>
SCRIPT
}

print ui_config_link('index_config');
ui_print_footer('index.cgi',$text{'index_title'});
