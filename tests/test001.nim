import std/[nativesockets, net]
import pkg/ybus/[auth, socket]
import pkg/ybus/wire/[emitter, reader, types]
import pkg/[pretty, shakar], pkg/flatty/hexprint

let path = &getSessionBusPath()
echo path

var machine: AuthMachine
let sock = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
sock.connectUnix(path)

let cookie = performAuth(machine, 1000'u64, sock)
assert *cookie, "DBus auth failed"

echo &cookie

let x = emit(
  Message(
    endian: 'l',
    kind: MessageKind.MethodCall,
    flags: {MessageFlags.None},
    version: 1,
    size: 0,
    serial: 1,
    headers:
      @[
        Header(kind: HeaderKind.Path, path: "/org/freedesktop/DBus"),
        Header(kind: HeaderKind.Interface, iface: "org.freedesktop.DBus.Properties"),
        Header(kind: HeaderKind.Member, member: "Get"),
        Header(kind: HeaderKind.Destination, destination: "org.freedesktop.DBus"),
        Header(kind: HeaderKind.Signature, signature: "ss"),
      ],
    body:
      @[
        Variant(kind: VariantKind.String, str: "org.freedesktop.systemd1.Manager"),
        Variant(kind: VariantKind.String, str: "Version"),
      ],
  )
)

echo hexprint(x)
sock.send(x)

let hdr = sock.recv(16)
let fixedheader = &parseFixedHeader(hdr)
print fixedheader

let msgHeaders = parseHeaders(sock.recv(fixedheader.headerFieldsSize.int))
print msgHeaders

let bytesRead = 16 + fixedheader.headerFieldsSize
let bodyPadding = (8 - (bytesRead mod 8)) mod 8

if bodyPadding > 0:
  discard sock.recv(bodyPadding.int)

var pos: int
let resp = parseVariant(sock.recv(fixedheader.msg.size.int), pos, "s")
print resp
