## D-Bus wire protocol reader
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import std/net
import pkg/ybus/wire/types, pkg/flatty/binny, pkg/[shakar, results]

func align*(pos: var int, cap, boundary: int) {.inline.} =
  let rem = cap mod boundary
  if rem != 0:
    pos += boundary - rem

func parseFixedHeader*(
    buffer: string
): Result[tuple[msg: types.Message, headerFieldsSize: uint32], string] =
  if buffer.len != 16:
    return
      err("Message header must be exactly 16 bytes! (got " & $buffer.len & " bytes!)")

  let
    endianness = buffer.readUint8(0)
    kind = buffer.readUint8(1)
    flags = buffer.readUint8(2)
    version = buffer.readUint8(3)
    bodyLength = buffer.readUint32(4)
    serial = buffer.readUint32(8)
    headerFieldsSize = buffer.readUint32(12)

  # TODO: Might want to validate some of the fields (like endianness)
  var msg: Message
  msg.endian = cast[char](endianness)
  msg.kind = cast[MessageKind](kind)
  msg.flags = cast[set[MessageFlags]](flags)
  msg.version = version
  msg.size = bodyLength
  msg.serial = serial

  ok((msg: ensureMove(msg), headerFieldsSize: headerFieldsSize))

func parseHeader*(
    buffer: string, pos: int
): Result[tuple[hdr: types.Header, consumed: int], string] =
  var i = pos

  if buffer.len < 1:
    return err("Header buffer is too small, cannot read `kind` byte!")

  let kind = cast[HeaderKind](buffer.readUint8(i))
  case kind
  of HeaderKind.Destination:
    i += 3 # skip \x01s\0 (TODO: we might want to record this in the header later?)

    align(pos = i, cap = i, boundary = 4)

    let size = cast[int](buffer.readUint32(i))
    i += 4

    let dest = buffer[i ..< i + size]
    i += size + 1

    return
      ok((hdr: Header(kind: HeaderKind.Destination, destination: dest), consumed: i))
  of HeaderKind.ReplySerial:
    i += 3 # skip \x01u\0 (TODO: we might want to record this in the heade later?)

    align(pos = i, cap = i, boundary = 4)

    let serial = buffer.readUint32(i)
    i += 4

    return ok((hdr: Header(kind: HeaderKind.ReplySerial, serial: serial), consumed: i))
  of HeaderKind.Signature:
    i += 3 # skip (TODO: same as above)

    align(pos = i, cap = i, boundary = 4)

    let sigSize = cast[int](buffer.readUint8(i))
    inc i

    let signature = buffer[i ..< i + sigSize]
    i += sigSize + 1

    return
      ok((hdr: Header(kind: HeaderKind.Signature, signature: signature), consumed: i))
  of HeaderKind.Sender:
    i += 3 # skip (TODO: same as above)

    align(pos = i, cap = i, boundary = 4)

    let size = cast[int](buffer.readUint32(i))
    i += 4

    let sender = buffer[i ..< i + size]
    i += size + 1

    return ok((hdr: Header(kind: HeaderKind.Sender, sender: sender), consumed: i))
  of HeaderKind.ErrorName:
    i += 3

    align(pos = i, cap = i, boundary = 4)

    let size = cast[int64](buffer.readUint32(i))
    i += 4

    let error = buffer[i ..< i + size]
    i += size + 1

    return ok((hdr: Header(kind: HeaderKind.ErrorName, errorName: error), consumed: i))
  of HeaderKind.Path:
    i += 3

    align(pos = i, cap = i, boundary = 4)

    let size = cast[int64](buffer.readUint32(i))
    i += 4

    let path = buffer[i ..< i + size]
    i += size + 1

    return ok((hdr: Header(kind: HeaderKind.Path, path: path), consumed: i))
  of HeaderKind.Interface:
    i += 3

    align(pos = i, cap = i, boundary = 4)

    let size = cast[int64](buffer.readUint32(i))
    i += 4

    let iface = buffer[i ..< i + size]
    i += size + 1

    return ok((hdr: Header(kind: HeaderKind.Interface, iface: iface), consumed: i))
  of HeaderKind.Member:
    i += 3

    align(pos = i, cap = i, boundary = 4)

    let size = cast[int64](buffer.readUint32(i))
    i += 4

    let member = buffer[i ..< i + size]
    i += size + 1

    return ok((hdr: Header(kind: HeaderKind.Member, member: member), consumed: i))
  else:
    assert off, $kind

func parseHeaders*(buffer: string): Result[seq[types.Header], string] =
  var i = 0
  let size = buffer.len

  # debugecho "full headers buffer:\n" & hexprint(buffer)

  var headers: seq[types.Header] # FIXME: Prealloc
  while i < size:
    align(pos = i, cap = i, boundary = 8)

    let resOpt = parseHeader(buffer, i)
    if !resOpt:
      return err(resOpt.error())

    let res = &resOpt
    headers &= res.hdr

    i = res.consumed

  ok(ensureMove(headers))

func parseStringVariant(
    buffer: string, pos: int
): Result[tuple[variant: Variant, at: int], string] =
  var pos = pos
  let size = cast[int64](buffer.readUint32(pos))
  pos += 4

  # debugEcho "parseStringVariant(size=" & $size & ", pos=" & $pos & ')'

  let str = buffer[pos ..< pos + size]
  pos += size + 1

  return ok((variant: Variant(kind: VariantKind.String, str: str), at: pos))

func parse32BitsVariant*(
    buffer: string, pos: int
): Result[tuple[data: uint32, at: int], string] =
  var pos = pos
  align(pos = pos, cap = pos, boundary = 4)

  let data = buffer.readUint32(pos)
  pos += 4

  return ok((data: data, at: pos))

func parseVariant*(
    buffer: string, pos: var int, signature: string
): Result[Variant, string] =
  if buffer.len < 1:
    return err("Cannot parse Variant from empty buffer!")

  if signature.len < 1:
    return err("Cannot parse Variant with empty signature!")

  var signature = signature
  let sigFirstByte = signature[0]
  signature = signature[1 ..< signature.len]

  case sigFirstByte
  of 's', 'o':
    # String/Object Path
    let variantOpt = parseStringVariant(buffer, pos)
    if !variantOpt:
      return err(variantOpt.error())

    let variant = &variantOpt
    pos += variant.at

    return ok(variant.variant)
  of 'u', 'i':
    # 32-bit integer (signed or unsigned)
    let variantOpt = parse32BitsVariant(buffer, pos)
    if !variantOpt:
      return err(variantOpt.error())

    let variant = &variantOpt
    pos += variant.at

    case sigFirstByte
    of 'u':
      return ok(Variant(kind: VariantKind.Uint32, u32: variant.data))
    of 'i':
      return ok(Variant(kind: VariantKind.Int32, i32: cast[int32](variant.data)))
    else:
      discard
  of 'v':
    let sigSize = cast[int64](buffer.readUint8(pos))
    inc pos

    let innerSignature = buffer[pos ..< pos + sigSize]
    pos += sigSize + 1

    align(pos = pos, cap = pos, boundary = 4)

    let variant = parseVariant(buffer, pos, innerSignature)
    if !variant:
      return err("Failed to parse inner variant: " & variant.error())

    return ok(Variant(kind: VariantKind.Variant, variant: &variant))
  else:
    assert off, $sigFirstByte
