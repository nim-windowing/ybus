## A D-Bus client that uses synchronous UNIX domain sockets for communication.
## Every operation that requires communication with the daemon is blocking.
##
## **Note**: This only works on POSIX systems, as expected.
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import std/[net, nativesockets, options, posix]
import pkg/ybus/wire/[emitter, reader, types], pkg/ybus/[auth, socket]
import pkg/shakar

export types

type
  BusError* = object of OSError

  BusClientObj = object
    sock: Socket
    socketPath: Option[string]

    auth: auth.AuthMachine
    cookie: Option[string]
    uid: Uid

    serial: uint32

    uniqueName: string

    signals*: seq[Message]

  BusClient* = ref BusClientObj

proc `=destroy`*(obj: BusClientObj) =
  close(obj.sock)

# Begin getters

{.push inline, cdecl.}
func serial*(client: BusClient): uint32 =
  ## Get the current message serial index.
  client.serial

func uniqueName*(client: BusClient): lent string =
  ## Get the unique name assigned to this client on the system bus.
  ##
  ## **Note**: If `connect()` has not been called, then this
  ## will likely be an empty string.
  client.uniqueName

{.pop.}

# End getters

proc receive*(client: BusClient): Option[Message] =
  ## Receive a response `Message` from the D-Bus daemon.
  ##
  ## **Note**: If a response is attempted to be received in a scenario where either
  ## the client asked the daemon to not send one, or the daemon does not send one,
  ## this routine will block the calling thread.

  # First, get the 16-byte header. Its size is constant.
  let fixedHeaderOpt = parseFixedHeader(recv(client.sock, 16))
  if !fixedHeaderOpt:
    # If the fixed header cannot be parsed, abort message receiv-al (not sure what the appropriate term would be)
    return none(Message)

  let fixedHeader = &fixedHeaderOpt
  var msg: Message = fixedHeader.msg

  # Next, parse the variable headers.
  let headersOpt = parseHeaders(recv(client.sock, int(fixedHeader.headerFieldsSize)))
  if !headersOpt:
    # If the headers cannot be parsed, abort retrieval. (oh hey, retrieval sounds appropriate :P)
    return none(Message)

  msg.headers = &headersOpt

  var signature: Option[string]
  for hdr in msg.headers:
    if hdr.kind != HeaderKind.Signature:
      continue

    signature = some(hdr.signature)
    break

  # If no Signature header is attached, then we mustn't attempt to parse the body.
  if !signature:
    return some(ensureMove(msg))

  # Now, parse the bdoy, which is a vector of variants.
  # TODO: I have no clue how it works. I just tried playing around with these and it seems to work. Might want to see what other implementations do.
  let
    # FIXED HEADER + SIZE OF ALL HEADERS
    #           v          v
    bytesRead = 16 + fixedHeader.headerFieldsSize
    bodyPadding = (8 - (bytesRead mod 8)) mod 8

  if bodyPadding > 0:
    # If there's any unnecessary padding in the way, yank it out of the socket buffer.
    discard recv(client.sock, int(bodyPadding))

  var pos: int
  let v = parseVariants(recv(client.sock, int(msg.size)), pos, &signature)
  if !v:
    return none(Message)

  msg.body = &v
  # Finally, return the fully parsed response.
  some(ensureMove(msg))

proc eatAllNoise(client: BusClient, serial: uint32): Option[Message] =
  ## Handle all incoming messages like signals that we don't need,
  ## until we find our intended response.

  while true:
    let incomingOpt = receive(client)
    if !incomingOpt:
      return none(Message)

    let incoming = &incomingOpt
    for hdr in incoming.headers:
      if hdr.kind == HeaderKind.ReplySerial and hdr.serial == serial:
        return incomingOpt

    if incoming.kind == MessageKind.Signal:
      client.signals &= incoming

proc send*(
    client: BusClient, message: Message, serialOverride: bool = false
): Option[Message] =
  ## Serialize a `Message` and send it to the D-Bus daemon.
  ##
  ## This routine handles tracking the message serial for you. This behavior can be disabled by setting `serialOverride` to `true`.
  ##
  ## If the message's flags are set to not expect a reply, an empty `Option[Message]` will be returned.

  var message = message
  if not serialOverride:
    inc client.serial
    message.serial = client.serial

  let serialized = emitter.emit(message)
  # debugecho $client.serial & ": " & hexPrint(serialized)
  client.sock.send(serialized)

  if message.flags.contains(MessageFlags.NoReplyExpected):
    return none(Message)

  eatAllNoise(client, message.serial)

proc call*(
    client: BusClient, path, iface, destination, member: string
): Option[Message] =
  ## Call a method on the D-Bus with no arguments.
  client.send(
    Message(
      endian: 'l',
        # TODO: Big Endian support. Our parsers and emitters probably don't handle that properly. But this shouldn't matter much.
      kind: MessageKind.MethodCall,
      flags: {},
      version: 1,
      headers:
        @[
          Header(kind: HeaderKind.Path, path: path),
          Header(kind: HeaderKind.Interface, iface: iface),
          Header(kind: HeaderKind.Member, member: member),
          Header(kind: HeaderKind.Destination, destination: destination),
        ],
    )
  )

proc call*(
    client: BusClient,
    path, iface, destination, member: string,
    signature: string,
    arguments: seq[Variant],
): Option[Message] =
  ## Overload of _`proc call(BusClient, string, string, string, string)` that can provide arguments to the callee.
  client.send(
    Message(
      endian: 'l',
      kind: MessageKind.MethodCall,
      flags: {},
      version: 1,
      headers:
        @[
          Header(kind: HeaderKind.Path, path: path),
          Header(kind: HeaderKind.Interface, iface: iface),
          Header(kind: HeaderKind.Member, member: member),
          Header(kind: HeaderKind.Destination, destination: destination),
          Header(kind: HeaderKind.Signature, signature: signature),
        ],
      body: arguments,
    )
  )

proc callNoReply*(client: BusClient, path, iface, destination, member: string) =
  ## Call a D-Bus method and tell the daemon that you do not expect a reply in return.
  discard client.send(
    Message(
      endian: 'l',
      kind: MessageKind.MethodCall,
      flags: {MessageFlags.NoReplyExpected},
      version: 1,
      headers:
        @[
          Header(kind: HeaderKind.Path, path: path),
          Header(kind: HeaderKind.Interface, iface: iface),
          Header(kind: HeaderKind.Member, member: member),
          Header(kind: HeaderKind.Destination, destination: destination),
        ],
    )
  )

proc callNoReply*(
    client: BusClient,
    path, iface, destination, member: string,
    signature: string,
    arguments: seq[Variant],
) =
  ## Overload of _`proc callNoReply(BusClient, string, string, string, string)` that can provide arguments to the callee.
  discard client.send(
    Message(
      endian: 'l',
      kind: MessageKind.MethodCall,
      flags: {MessageFlags.NoReplyExpected},
      version: 1,
      headers:
        @[
          Header(kind: HeaderKind.Path, path: path),
          Header(kind: HeaderKind.Interface, iface: iface),
          Header(kind: HeaderKind.Member, member: member),
          Header(kind: HeaderKind.Destination, destination: destination),
          Header(kind: HeaderKind.Signature, signature: signature),
        ],
      body: arguments,
    )
  )

proc connect*(client: BusClient) {.sideEffect.} =
  if !client.socketPath:
    raise newException(
      BusError,
      "Cannot find a path to the environment's D-Bus daemon. Is a daemon even running?",
    )

  when defined(ybusConnectLogDebugInfo):
    debugEcho "Socket path: " & &client.socketPath
    debugEcho "UID: " & $client.uid

  # Connect to the daemon
  client.sock.connectUnix(&client.socketPath)

  # Let the auth FSM do its thing.
  client.cookie = performAuth(client.auth, client.uid, client.sock)
  if !client.cookie:
    raise newException(BusError, "Failed to authenticate into the D-Bus daemon.")

  # Now, let us register ourselves with the daemon so we can talk to services on the bus.
  # For that, we must use the `Hello` call.
  #
  # https://dbus.freedesktop.org/doc/dbus-java/api/org/freedesktop/DBus.html#Hello()
  let respOpt = client.call(
    path = "/org/freedesktop/DBus",
    iface = "org.freedesktop.DBus",
    destination = "org.freedesktop.DBus",
    member = "Hello",
  )
  if !respOpt:
    raise newException(
      BusError,
      "Failed to register with the D-Bus daemon (Hello), received invalid message?",
    )

  let resp = &respOpt
  if resp.kind == MessageKind.Error:
    raise newException(
      BusError,
      "Failed to register with the D-Bus daemon (Hello), received error response: " &
        resp.body[0].str,
    )

  client.uniqueName = resp.body[0].str

template createDbusSocket(): Socket =
  newSocket(net.AF_UNIX, net.SOCK_STREAM, net.IPPROTO_IP)

proc newBusClient*(): BusClient {.sideEffect.} =
  ## Create a new D-Bus client, which automatically sets its target to the execution environment's bus, granted that it exists.
  ##
  ## It abstracts away all the complexities of finding the socket path that the D-Bus specifications prescribe.
  ##
  ## **Note**: If no socket path to the bus is found, an error will be raised when a
  ## connection is attempted to be established.
  BusClient(
    sock: createDbusSocket(),
    uid: posix.getuid(),
    socketPath: socket.getSessionBusPath(),
  )

proc newBusClient*(path: string, uid: Uid = getuid()): BusClient {.sideEffect.} =
  ## Create a new D-Bus client with a predefined target socket path to the bus.
  ##
  ## **Note**: If the path specified is invalid or does not have a D-Bus daemon running on it, 
  ## an error will be raised when a connection is attempted to be established.
  BusClient(sock: createDbusSocket(), uid: uid, socketPath: some(path))
