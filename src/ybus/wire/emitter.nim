## D-Bus wire protocol emitter
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import pkg/ybus/wire/types, pkg/flatty/binny, pkg/shakar

func alloc(buffer: var string, count: int): int {.inline, discardable.} =
  let size = buffer.len + count # New size
  buffer.setLen(size)

  size

func align*(buffer: var string, boundary: int) {.inline.} =
  let rem = buffer.len mod boundary
  if rem != 0:
    for i in 0 ..< boundary - rem:
      buffer &= '\0'

func emitFixedHeader(msg: types.Message, buffer: var string) {.inline.} =
  buffer.alloc(12)

  buffer.writeUint8(0, cast[uint8](msg.endian))
  buffer.writeUint8(1, cast[uint8](msg.kind))
  buffer.writeUint8(2, cast[uint8](msg.flags))
  buffer.writeUint8(3, cast[uint8](msg.version))

  buffer.writeUint32(4, msg.size)
  buffer.writeUint32(8, msg.serial)

func emitHeader(header: types.Header, buffer: var string) =
  buffer.align(8)
  buffer &= cast[char](header.kind)

  case header.kind
  of HeaderKind.Path:
    buffer &= "\x01o\0"

    buffer.align(4)

    let pos = buffer.alloc(4)
    buffer.writeUint32(pos - 4, uint32(header.path.len))

    buffer &= header.path
    buffer &= '\0'
  of HeaderKind.Interface, HeaderKind.Member, HeaderKind.Destination:
    buffer &= "\x01s\0"

    buffer.align(4)

    let strVal =
      case header.kind
      of HeaderKind.Interface:
        header.iface
      of HeaderKind.Member:
        header.member
      of HeaderKind.Destination:
        header.destination
      else:
        unreachable
        newString(0)

    let pos = buffer.alloc(4)
    buffer.writeUint32(pos - 4, uint32(strVal.len))

    buffer &= strVal
    buffer &= '\0'
  of HeaderKind.Signature:
    assert(header.signature.len < int(uint8.high))

    buffer &= "\x01g\0"
    buffer.align(4)
    buffer &= cast[char](header.signature.len)
    buffer &= header.signature
    buffer &= '\0'
  else:
    assert off, $header.kind

func emitHeaders(headers: seq[types.Header], buffer: var string) {.inline.} =
  for header in headers:
    buffer.align(8) # Every header needs to start at an 8-byte boundary
    emitHeader(header, buffer)

func emitBody(body: seq[Variant], buffer: var string) {.inline.} =
  for variant in body:
    case variant.kind
    of VariantKind.String, VariantKind.ObjectPath:
      buffer.align(4)

      let currentPos = buffer.len

      let length = uint32(variant.str.len)
      buffer.alloc(4)
      buffer.writeUint32(currentPos, length)

      buffer &= variant.str
      buffer &= '\0'
    else:
      assert off, $variant.kind

func emit*(msg: types.Message, capacity: uint = 256'u): string =
  var buffer = newStringOfCap(capacity)

  emitFixedHeader(msg, buffer)

  let headersSizeOffset = buffer.len
  buffer.alloc(4)
  buffer.writeUint32(headersSizeOffset, 0)

  emitHeaders(msg.headers, buffer)

  let headersSize = uint32(buffer.len - headersSizeOffset) - 4
  buffer.writeUint32(headersSizeOffset, headersSize)

  buffer.align(8)
  let bodyStart = buffer.len
  emitBody(msg.body, buffer)

  let bodySize = uint32(buffer.len - bodyStart)
  buffer.writeUint32(4, bodySize)

  ensureMove(buffer)
