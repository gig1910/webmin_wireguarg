# Webmin access control

| ACL | Capability |
|---|---|
| `view` | View interfaces, peers, status and graphs |
| `manage` | Modify WireGuard configuration and runtime state; control collector |
| `export_clients` | View/download client configurations, private keys and QR codes |
| `diagnostics` | Run controlled ping, traceroute and TCP-port checks |
| `logs` | Read WireGuard and system journal entries |
| `install_dependencies` | Install a fixed set of optional QR/WHOIS/GeoIP packages using privileged APT |

`manage` is **root-equivalent**: a user with this permission can edit
`PreUp`, `PostUp`, `PreDown` and `PostDown`, executed as root by
`wg-quick`. `install_dependencies` is similarly privileged, since APT
runs system package maintenance scripts. Export privileges expose client key
material. These rights must be limited to trusted administrators.

## Recommended read-only role

```ini
view=1
manage=0
export_clients=0
diagnostics=0
logs=0
install_dependencies=0
```

The current package's `defaultacl` grants all six rights for historical
compatibility. **This is not a least-privilege baseline.** Configure explicit
ACLs for nonadministrator Webmin users before granting module access.
Changing `defaultacl` in an upgrade may also change effective permissions
for existing Webmin users who rely on inherited defaults, so the package must
not silently rewrite those permissions without a dedicated migration and
administrator confirmation.

Every mutation is independently authorized by the relevant CGI endpoint.
Read-only menu visibility is not an authorization check.
