# ybus
ybus is an implementation of the D-Bus protocol in pure Nim. It is currently not suitable for real-world usage, but it's slowly getting there.

As expected, it relies on no external non-Nim dependencies.

# roadmap
- [X] System bus socket resolution
- [X] Authentication machine
- [X] Basic sync client with handshake
- [X] Call methods on the bus
- [ ] Programmer-friendly API to create interfaces and services on the bus
- [ ] **Writer**: Support for emitting all remaining header types
- [ ] **Writer**: Support for emitting variants besides strings and object paths
- [ ] **Reader**: Support for parsing some remaining header types
- [ ] **Reader**: Support for parsing all remaining variant types
- [ ] Tool to convert protocol XML files to Nim wrappers
- [ ] `asyncdispatch` and `chronos` based asynchronous clients
- [ ] Benchmarking ybus against implementations in other languages (`zbus` for Rust, `godbus` for Go, etc.)
- [ ] More error-proofing (Possibly fuzzing the reader and variant parser? They don't use any pointer math so this will only catch logic bugs and OOB reads that'd cause defects)

# distant / low-priority goals
- [ ] Proper, tested big endian support
- [ ] Abstract keys in system bus socket resolution. Most systems do not use this.

# basic example
ybus' core (wire protocol reader and writer) is mostly written as pure, side-effect-free functions. The `unix_sync` client, as the name suggests, is a synchronous D-Bus client that uses UNIX sockets.

Here is a basic example which connects to the system bus and queries the version of systemd running on the machine.
```nim
import std/options
import pkg/ybus/client/unix_sync

let client = newBusClient()
client.connect()

debugEcho "serial: " & $client.serial
debugEcho "unique name: " & client.uniqueName

let resp = client.call(
  path = "/org/freedesktop/systemd1",
  iface = "org.freedesktop.DBus.Properties",
  destination = "org.freedesktop.systemd1",
  member = "Get",
  arguments =
    @[
      Variant(kind: VariantKind.String, str: "org.freedesktop.systemd1.Manager"),
      Variant(kind: VariantKind.String, str: "Version"),
    ],
  signature = "ss",
)
echo "systemd version " & resp.get().body[0].str
```
