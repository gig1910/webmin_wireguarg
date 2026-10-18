#!/usr/bin/env perl
# A self-contained preview of shared UI components. NOT a screenshot of
# production Webmin or Authentic Theme: server integration is verified separately.
use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../tests/stub";
require "$FindBin::Bin/../wireguard-lib.pl";
binmode STDOUT, ':encoding(UTF-8)';

my $table_actions =
    wg_ui_icon_action(icon=>'history',label=>'История',href=>'analytics.cgi?peer_id=demo',tone=>'info').
    wg_ui_icon_action(icon=>'globe',label=>'WHOIS / GeoIP',tone=>'info').
    wg_ui_icon_action(icon=>'edit',label=>'Редактировать',tone=>'info').
    wg_ui_icon_action(icon=>'stop',label=>'Деактивировать',tone=>'warning');

my $table = '<table class="preview-table wg-ui-compact-table">'.
    '<thead><tr><th>Пир</th><th>Статус</th><th>Endpoint</th><th>RX</th><th>Действия</th></tr></thead>'.
    '<tbody>'.
    '<tr><td><a>Microtik Home</a></td><td><span class="wg-ui-status wg-ui-status--success">Активен</span></td>'.
    '<td><span class="wg-endpoint-with-icon"><span class="wg-network-icon">S7</span><span class="wg-geoip-country">🇷🇸 RS</span>'.
    '<span class="wg-ui-mono">185.60.46.158:36431</span></span></td><td>7.2 GiB</td>'.
    '<td><span class="wg-ui-table-actions">'.$table_actions.'</span></td></tr>'.
    '<tr><td><a>Tablet</a></td><td><span class="wg-ui-status wg-ui-status--muted">Неактивен</span></td>'.
    '<td>—</td><td>0 B</td><td><span class="wg-ui-table-actions">'.
    wg_ui_icon_action(icon=>'history',label=>'История',tone=>'info').
    wg_ui_icon_action(icon=>'globe',label=>'WHOIS / GeoIP',tone=>'info').
    wg_ui_icon_action(icon=>'play',label=>'Активировать',tone=>'success').
    '</span></td></tr></tbody></table>';

my $toolbar = wg_ui_action_bar(
    wg_ui_button(icon=>'plus',tone=>'success',label=>'Добавить пир').
    wg_ui_button(icon=>'save',tone=>'success',label=>'Сохранить').
    wg_ui_button(icon=>'refresh',tone=>'warning',label=>'Перезапустить'),
    wg_ui_button(icon=>'log',label=>'Журнал').
    wg_ui_icon_action(icon=>'globe',tone=>'info',label=>'Сетевой справочник')
);

my $cards = '<div class="wg-ui-summary">'.
    '<div class="wg-ui-summary-card"><span>Получено</span><strong>944 MiB</strong></div>'.
    '<div class="wg-ui-summary-card"><span>Отправлено</span><strong>6.63 GiB</strong></div>'.
    '<div class="wg-ui-summary-card"><span>Последнее рукопожатие</span><strong>10 секунд назад</strong></div>'.
    '</div>';

my $panel = wg_ui_panel('Обслуживание сборщика',
    wg_ui_button(icon=>'refresh',tone=>'warning',label=>'Перезапустить сборщик').
    wg_ui_button(icon=>'stop',tone=>'warning',label=>'Остановить сборщик'));

my $danger = wg_ui_danger_zone(
    wg_ui_button(icon=>'trash',tone=>'danger',label=>'Удалить интерфейс'),
    'Опасные операции'
);

my $fields = '<div class="wg-ui-form-row"><label>PersistentKeepalive'.
    wg_ui_number_input('keepalive',90,0,65535).'</label>'.
    '<label>Endpoint'.wg_ui_validated_input('endpoint','vpn.example.org:51820',
       36,'endpoint','IP или доменное имя с портом').'</label>'.
    '</div>';

my $body = '<div class="preview-stack"><h2>Навигация и управление</h2>'.$toolbar.
   '<h2>Сводные показатели</h2>'.$cards.
   '<h2>Пиры — компактные иконки с подсказками</h2>'.$table.
   '<h2>Редактирование</h2>'.$fields.
   '<h2>Служебные действия</h2>'.$panel.$danger.'</div>';

print '<!doctype html><html lang="ru"><head><meta charset="UTF-8">'.
   '<meta name="viewport" content="width=device-width,initial-scale=1">'.
   '<title>WireGuard UI component preview</title>'.
   wg_ui_foundation().
   '<style>body{margin:0;font-family:system-ui,Arial,sans-serif;background:#17181b;color:#dadce0}'.
   '.preview{max-width:1220px;margin:24px auto;border:1px solid #444;padding:20px;border-radius:6px}'.
   '.preview h1{font-size:20px;font-weight:500;margin:0 0 6px}.preview h2{font-size:15px;margin:22px 0 12px}'.
   '.preview p{font-size:12px;opacity:.8}.preview-dark{background:#25262a;color:#dedfe2}'.
   '.preview-light{background:#f4f6f8;color:#26303b}'.
   '.preview-table{width:100%;border-collapse:collapse;font-size:13px}'.
   '.preview-table th,.preview-table td{border-bottom:1px solid rgba(127,127,127,.25);padding:4px 8px;text-align:left}'.
   '.preview-table th{font-size:12px}.preview a{color:#559ade}'.
   '.preview .wg-ui-btn{font-family:inherit;border-width:1px}.preview .wg-ui-btn svg{width:16px;height:16px}'.
   '</style></head><body><main>';

for my $theme (qw(dark light)) {
    print '<section class="wg-ui preview preview-'.$theme.'">'.
       '<h1>WireGuard UI — '.($theme eq 'dark'?'Dark':'Light').'</h1>'.
       '<p>Изолированная галерея общих компонентов; не установленный Webmin.</p>'.
       $body.'</section>';
}
print '</main></body></html>';
