# Webmin ACL model

| ACL | Capability |
|---|---|
| `view` | View interfaces, peers, status and graphs |
| `manage` | Modify files and runtime state; control collector |
| `export_clients` | View/download client configurations and QR codes |
| `diagnostics` | Run ping, traceroute and TCP-port checks |
| `logs` | View WireGuard/system journals |
| `install_dependencies` | Install the fixed optional `qrencode` package |

A read-only role should normally use:

```ini
view=1
manage=0
export_clients=0
diagnostics=0
logs=0
install_dependencies=0
```

`manage` must be assigned only to trusted administrators because hook commands
from the interface configuration execute as root.
