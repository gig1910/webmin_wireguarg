/* Run the actual Perl-rendered shared UI script against a minimal DOM model.
   This is a behavior gate; it does not replace Authentic Theme screenshots. */
'use strict';
const fs = require('fs');
const vm = require('vm');
const assert = require('assert').strict;

const listeners = new Map();
global.window = global;
// Node 22 exposes a read-only navigator; clipboard is not used in these tests.
global.document = {
  addEventListener(type, fn) {
    if (!listeners.has(type)) listeners.set(type, []);
    listeners.get(type).push(fn);
  },
};
vm.runInThisContext(fs.readFileSync(process.argv[2], 'utf8'), {
  filename: 'generated-webmin-ui.js'
});
const ui = window.WireGuardUI;
assert.equal(ui.version, 1);
assert.equal(ui.flag('RU'), '🇷🇺');
assert.equal(ui.flag('rs'), '🇷🇸');
assert.equal(ui.flag('invalid'), '');

const badge={dataset:{},hidden:false,textContent:'',title:''};
const country={hidden:true,textContent:'',title:''};
ui.renderNetwork(badge,country,null,'');
assert.equal(badge.hidden,true,'no endpoint must not have a network badge');
assert.equal(country.hidden,true,'no endpoint must not have a country');
ui.renderNetwork(badge,country,{icon:'T2',cidr:'92.36.0.0/18',label:'Tele2',
  country:'RU',country_source:'whois'},'92.36.0.19');
assert.equal(badge.hidden,false);
assert.equal(badge.textContent,'T2');
assert.equal(country.textContent,'🇷🇺 RU');
assert.equal(country.hidden,false);
ui.renderNetwork(badge,country,{},'92.36.0.19');
assert.equal(badge.textContent,'?');
assert.equal(country.textContent,'');
assert.equal(country.hidden,true);


function validate(kind, value) {
  const field = {
    value,
    dataset: { wgValidate: kind, wgInvalidMessage: 'Invalid field' },
    setCustomValidity(message) { this.validationMessage = message; },
    reportValidity() { this.reported = true; }
  };
  const form = {
    dataset: {},
    closest(query) {
      return query === '.wg-ui' ? { role: 'page' } : this;
    },
    querySelectorAll(query) {
      return query === '[data-wg-validate]' ? [field] : [];
    }
  };
  let prevented = 0;
  for (const fn of listeners.get('submit') || []) {
    fn({
      target: { closest(query) { return query === 'form' ? form : null; } },
      preventDefault() { prevented++; },
    });
  }
  return { valid: !prevented && !field.validationMessage, field };
}

const validCases = [
  ['cidr-list', '192.168.1.0/24'],
  ['cidr-list', '2001:db8::/64'],
  ['cidr-list', '0.0.0.0/0,::/0'],
  ['cidr-list', '10.0.0.0/8\n\n192.168.0.0/16\n'],
  ['endpoint', 'example.com'],
  ['endpoint', 'vpn.example.com:51820'],
  ['endpoint', 'vpn.example.com:65535'],
  ['endpoint', '[2001:db8::1]:51820'],
  ['endpoint', ''],
];
const invalidCases = [
  ['cidr-list', '10.0.0.0/33'],
  ['cidr-list', '999.10.0.1/24'],
  ['cidr-list', '2001:db8::/129'],
  ['cidr-list', '10.0.0.0/24,not-an-ip'],
  ['cidr-list', ',,,'],
  ['endpoint', 'vpn.example.com:'],
  ['endpoint', '[2001:db8::1]:'],
  ['endpoint', 'vpn.example.com:0'],
  ['endpoint', 'vpn.example.com:65536'],
  ['endpoint', 'vpn.example.com:abc'],
  ['endpoint', 'invalid host name:51820'],
];
for (const [kind, value] of validCases) {
  const test = validate(kind, value);
  assert.equal(test.valid, true, kind + ' should accept: ' + value);
}
for (const [kind, value] of invalidCases) {
  const test = validate(kind, value);
  assert.equal(test.valid, false, kind + ' should reject: ' + value);
  assert.equal(test.field.reported, true);
}
console.log('Browser validation and shared flag behavior tests passed');
