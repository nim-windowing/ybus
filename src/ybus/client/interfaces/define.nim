## Utilities to define interfaces
## Largely inspired by nim-dbus' implementation.
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import std/[macros, strutils, tables]
import pkg/ybus/wire/types

type
  Argument* = object
    name*: string
    kind*: VariantKind

  MethodSignature* = object
    inputs*, outputs*: seq[Argument]

  RawMethod*[T] = proc(iface: T, args: seq[Variant]): seq[Variant]

  BusMethod*[T: object] = object
    signature*: MethodSignature
    native*: RawMethod[T]

  InterfaceNameFlag* {.pure, size: sizeof(uint32).} = enum
    AllowReplacement = 0x1 ## Allow other processes to displace your claim to a name
    ReplaceExisting = 0x2
      ## Replace any pre-existing client that might be holding onto the name, if they wished to allow so at their registration.
    DoNotQueue = 0x4
      ## If we cannot immediately become the primary owner, do not place us in the waiting queue.

  RequestNameResponse* {.pure, size: sizeof(uint32).} = enum
    PrimaryOwner = 1 ## Service has become the primary owner of the requested name. 
    InQueue = 2
      ## Service could not become the primary owner and has been placed in the queue.
    ExistsInQueue = 3 ## Service is already in the queue.
    AlreadyOwner = 4 ## Service is already the primary owner.

  InterfaceDef*[T: object] = object
    name*: string
    meths*: Table[string, BusMethod[T]]

func confirmedOwner*(response: RequestNameResponse): bool {.inline.} =
  response == RequestNameResponse.PrimaryOwner or
    response == RequestNameResponse.AlreadyOwner

func newInterfaceDef*[T: object](
    typ: typedesc[T], name: string
): InterfaceDef[T] {.inline.} =
  InterfaceDef[T](name: name, meths: initTable[string, BusMethod[T]]())

func ensurePascalCase(name: string): string {.inline.} =
  # Just make the first character uppercase.
  if name.len > 0:
    var buff = $name[0].toUpperAscii()

    if name.len > 1:
      buff &= name[1 ..< name.len]

    return ensureMove(buff)

  name

func arg*(name: string, kind: VariantKind): Argument {.inline.} =
  Argument(kind: kind, name: name)

func addMethod*[T: object](
    iface: var InterfaceDef[T],
    name: string,
    native: RawMethod[T],
    inputs: seq[Argument] = @[],
    outputs: seq[Argument] = @[],
) =
  # TODO: Rewrite this as a macro!
  let methodName = ensurePascalCase(name)
  iface.meths[methodName] = BusMethod[T](
    signature: MethodSignature(inputs: inputs, outputs: outputs), native: native
  )
