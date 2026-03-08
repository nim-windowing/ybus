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

func computeAlignment(variant: Variant): int {.inline.} =
  case variant.kind
  of VariantKind.Uint8, VariantKind.Variant:
    return 1
  of VariantKind.Int16, VariantKind.Uint16:
    return 2
  of VariantKind.Int32, VariantKind.Uint32, VariantKind.Boolean, VariantKind.UnixFd,
      VariantKind.String, VariantKind.ObjectPath, VariantKind.TypeSignature:
    return 4
  of VariantKind.Int64, VariantKind.Uint64, VariantKind.Double, VariantKind.Struct,
      VariantKind.DictEntry:
    return 8
  of VariantKind.Array:
    if variant.elements.len < 1:
      # If the array is empty, we needn't add any padding.
      return 0

    return computeAlignment(variant.elements[0])
  else:
    discard

func emitVariant(variant: Variant, buffer: var string) =
  case variant.kind
  of VariantKind.String, VariantKind.ObjectPath:
    buffer.align(4)

    let currentPos = buffer.len

    let length = uint32(variant.str.len)
    buffer.alloc(4)
    buffer.writeUint32(currentPos, length)

    buffer &= variant.str
    buffer &= '\0'
  of VariantKind.Uint32:
    buffer.align(4)

    let vpos = buffer.len
    buffer.alloc(4)
    buffer.writeUint32(vpos, variant.u32)
  of VariantKind.Int32:
    buffer.align(4)

    let vpos = buffer.len
    buffer.alloc(4)
    buffer.writeInt32(vpos, variant.i32)
  of VariantKind.Array:
    buffer.align(4)

    let lengthPos = buffer.len
    buffer.alloc(4)

    let internalAlign = computeAlignment(variant)
    if internalAlign < 1:
      # We probably have nothing to store.
      buffer.writeUint32(lengthPos, 0)
      return
    
    buffer.align(internalAlign)
    let dataStart = buffer.len

    for elem in variant.elements:
      emitVariant(elem, buffer)

    let dataSize = uint32(buffer.len - dataStart)
    buffer.writeUint32(lengthPos, dataSize)
  else:
    assert off, $variant.kind

func emitBody(body: seq[Variant], buffer: var string) {.inline.} =
  for variant in body:
    emitVariant(variant, buffer)

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
