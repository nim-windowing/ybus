import std/[options, tables]
import pkg/ybus/client/unix_sync
import pkg/ybus/client/interfaces/[define, introspection]
import pretty

let client = newBusClient()
client.connect()

type MockInterface = object

var mockIface = newInterfaceDef(MockInterface, "xyz.xtrayambak.ybus.MockService")

proc helloWorld(iface: MockInterface, args: seq[Variant]): seq[Variant] =
  echo "e"

mockIface.addMethod(
  "helloWorld",
  helloWorld,
  inputs = @[],
  outputs = @[arg("greeting", VariantKind.String)],
)

echo introspect(mockiface)
echo client.register(mockIface)

while true:
  if client.signals.len > 0:
    let sig = client.signals[0]
    print sig
    client.signals.delete(0)
    continue

  let message = client.receive().get()
  print message

  var sender, member: string
  var serial: uint32

  for hdr in message.headers:
    if hdr.kind == HeaderKind.Member:
      member = hdr.member
    elif hdr.kind == HeaderKind.Sender:
      sender = hdr.sender

  if member == "Introspect":
    discard client.send(
      Message(
        endian: 'l',
        kind: MessageKind.MethodReturn,
        flags: {},
        version: 1,
        headers:
          @[
            Header(kind: HeaderKind.Destination, destination: move(sender)),
            Header(kind: HeaderKind.ReplySerial, serial: message.serial),
            Header(kind: HeaderKind.Signature, signature: "s"),
          ],
        body: @[Variant(kind: VariantKind.String, str: introspect(mockIface))],
      )
    )
