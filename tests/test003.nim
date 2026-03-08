## testcase to start supporting more complex variant encodings
import std/options
import pkg/ybus/client/unix_sync
import pkg/pretty

let client = newBusClient()
client.connect()

debugEcho "serial: " & $client.serial
debugEcho "unique name: " & client.uniqueName

let r0 = get client.call(
  path = "/org/freedesktop/Notifications",
  iface = "org.freedesktop.DBus.Introspectable",
  destination = "org.freedesktop.Notifications",
  member = "Introspect"
)
writeFile("notifications.xml", r0.body[0].str)

let r = client.call(
  path = "/org/freedesktop/Notifications",
  iface = "org.freedesktop.Notifications",
  destination = "org.freedesktop.Notifications",
  member = "Notify",
  arguments =
    @[
      Variant(kind: VariantKind.String, str: "ybus"),
      Variant(kind: VariantKind.Uint32, u32: 0),
      Variant(kind: VariantKind.String, str: "org.gnome.Nautilus"),
      Variant(kind: VariantKind.String, str: "hello, ybus!"),
      Variant(kind: VariantKind.String, str: "this is sent from the ybus sync client"),
      Variant(kind: VariantKind.Array, elements: @[]),
      Variant(kind: VariantKind.Array, elements: @[]),
      Variant(kind: VariantKind.Int32, i32: 5000),
    ],
  signature = "susssasa{sv}i",
)
print r
