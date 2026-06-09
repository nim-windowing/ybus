import std/options
import pkg/ybus/client/unix_sync

let client = newBusClient()
client.connect()

debugEcho "serial: " & $client.serial
debugEcho "unique name: " & client.uniqueName

let r = client
  .call(
    path = "/org/freedesktop/systemd1",
    iface = "org.freedesktop.DBus.Properties",
    destination = "org.freedesktop.systemd1",
    member = "Get",
    arguments = @[
      Variant(kind: VariantKind.String, str: "org.freedesktop.systemd1.Manager"),
      Variant(kind: VariantKind.String, str: "Version"),
    ],
    signature = "ss",
  )
  .get()

echo "systemd version " & r.body[0].variant.str
