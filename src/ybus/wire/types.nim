## D-Bus wire protocol types
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)

type
  MessageKind* {.pure, size: sizeof(uint8).} = enum
    Invalid = 0
    MethodCall = 1
    MethodReturn = 2
    Error = 3
    Signal = 4

  MessageFlags* {.pure, size: sizeof(uint8).} = enum
    None = 0x0
    NoReplyExpected = 0x1
    NoAutoStart = 0x2
    AllowInteractiveAuth = 0x4

  HeaderKind* {.pure, size: sizeof(uint8).} = enum
    Invalid = 0
    Path = 1
    Interface = 2
    Member = 3
    ErrorName = 4
    ReplySerial = 5
    Destination = 6
    Sender = 7
    Signature = 8
    UnixFds = 9

  Header* = object
    case kind*: HeaderKind
    of HeaderKind.Path: path*: string
    of HeaderKind.Interface: iface*: string
    of HeaderKind.Member: member*: string
    of HeaderKind.ErrorName: errorName*: string
    of HeaderKind.Destination: destination*: string
    of HeaderKind.Sender: sender*: string
    of HeaderKind.Signature: signature*: string
    of HeaderKind.ReplySerial: serial*: uint32
    of HeaderKind.UnixFds: fdsCount*: uint32
    of HeaderKind.Invalid: discard

  VariantKind* {.pure, size: sizeof(uint8).} = enum
    Invalid = 0
    Uint8
    Boolean
    Int16
    Uint16
    Int32
    Uint32
    Int64
    Uint64
    Double
    String
    ObjectPath
    TypeSignature
    Array
    Struct
    Variant
    DictEntry
    UnixFd
    ReservedM
    ReservedAsterisk
    ReservedQuestion
    ReservedAtAndCaret

  Variant* = ref object
    case kind*: VariantKind
    of VariantKind.Invalid: discard
    of VariantKind.Uint8: u8*: uint8
    of VariantKind.Boolean: boolean*: bool
    of VariantKind.Int16: i16*: int16
    of VariantKind.Uint16: u16*: uint16
    of VariantKind.Double: double*: float64
    of VariantKind.Int32: i32*: int32
    of VariantKind.Uint32: u32*: uint32
    of VariantKind.Int64: i64*: int64
    of VariantKind.Uint64: u64*: uint64
    of VariantKind.String: str*: string
    of VariantKind.ObjectPath: path*: string
    of VariantKind.TypeSignature: signature*: string
    of VariantKind.Array: elements*: seq[Variant]
    of VariantKind.DictEntry:
      key*, value*: Variant
    of VariantKind.UnixFd: fd*: int32
    of VariantKind.Struct: struct*: seq[Variant]
    of VariantKind.Variant: variant*: Variant
    of {
      VariantKind.ReservedM, VariantKind.ReservedAsterisk,
      VariantKind.ReservedAtAndCaret, VariantKind.ReservedQuestion,
    }: discard

  Message* = object
    endian*: char
    kind*: MessageKind
    flags*: set[MessageFlags]
    version*: uint8
    size*: uint32
    serial*: uint32
    headers*: seq[Header]
    body*: seq[Variant]
