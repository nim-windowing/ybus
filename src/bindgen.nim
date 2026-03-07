## `bindgen` is a tool to generate Nim bindings from D-Bus API protocol XML files.
##
## It can also generate bindings by just connecting to an interface and introspecting it,
## if the interface supports it.
##
## It's a fairly quick-and-dirty hack, but I aim to replace it with something more maintainable eventually.
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import std/[options, os, parseopt, parsexml, streams, strutils]
import pkg/ybus/client/unix_sync,
       pkg/[pretty, shakar]

type
  Mode = enum
    mNone
    mIntrospect
    mParseLocal

proc showHelp(code: int) {.noReturn.} =
  echo """
bindgen is a tool to generate Nim bindings from D-Bus API protocol XML files.

Usage: bindgen --<introspect/parse-local> <interface/file>
  """
  quit(code)

func toPrimitiveType(typ: string): string =
  if typ == "s": return "string"
  elif typ == "u": return "uint32"
  elif typ == "i": return "int32"
  elif typ == "v": return "Variant"
  elif typ == "as": return "seq[" & toPrimitiveType(typ[1 ..< typ.len]) & ']'
  else:
    if not typ.contains('{'):
      # array
      var buff = "seq["
      buff &= toPrimitiveType($typ[1])
      buff &= ']'
      return ensureMove(buff)
    else:
      if typ.startsWith("a{"):
        # Table
        return "Table[" & toPrimitiveType($typ[2]) & ", " & toPrimitiveType($typ[3]) & ']'
    
    assert off, typ

proc generateArgument(parser: var XmlParser, buffer: var string): tuple[argName, argTyp: string, ret: Option[string]] =  
  var
    typ, name: string
    isReturnValue: bool
    returnValue: Option[string]

  while true:
    next(parser)
    if parser.kind == xmlElementEnd:
      break

    if parser.kind != xmlAttribute:
      continue

    if parser.attrKey == "name":
      name = parser.attrValue
    elif parser.attrKey == "type":
      typ = parser.attrValue
    elif parser.attrKey == "direction":
      isReturnValue = parser.attrValue == "out"
  
  if not isReturnValue:
    buffer &= ", "
    buffer &= name & ": " & toPrimitiveType(typ)
    (argName: name, argTyp: typ, ret: none(string))
  else:
    (argName: name, argTyp: typ, ret: some(typ))

func getPath(iface: string): string =
  '/' & iface.replace('.', '/')

proc generateMethod(parser: var XmlParser, iface: string, buffer: var string) =
  var methName: string
  while true:
    parser.next()
    if parser.kind != xmlAttribute or parser.attrKey != "name":
      continue

    methName = parser.attrValue
    break
  
  let normalizedMethName =
    if methName.len > 1:
      methName[0].toLowerAscii & methName[1 ..< methName.len]
    else:
      methName

  buffer &= "\nproc " & normalizedMethName & "*(client: unix_sync.BusClient"
  
  var retval: Option[string]
  var arguments: seq[tuple[name: string, typ: string]]
  # parse parameters
  while true:
    parser.next()
    case parser.kind
    of xmlEof: break
    of xmlElementOpen:
      if parser.elementName == "arg":
        let arg = generateArgument(parser, buffer)
        if *arg.ret:
          retval.applyThis:
            this &= &arg.ret
        else:
          arguments &= (name: arg.argName, typ: arg.argTyp)
    of xmlElementEnd:
      if parser.elementName == "method":
        break
    else: discard

  buffer &= ')'
  if *retval:
    buffer &= ": Option[" & toPrimitiveType(&retval) & ']'

  # Implementation
  buffer &= " =\n  "
  if !retval:
    buffer &= "discard "
  else:
    buffer &= "let r: Option[Message] = "
  buffer &= "client.call(path = \"" & getPath(iface) & "\", iface = \"" & iface & "\", destination = \"" & iface & "\", member = \"" & methName & "\""

  if arguments.len > 0:
    var signature = newStringOfCap(arguments.len) # Best case: Every argument's signature is 1 byte
    buffer &= ", arguments = @["
    for i, ident in arguments:
      if i > 0: buffer &= ", "
      buffer &= "wrap(" & ident.name & ')'
      signature &= ident.typ
    buffer &= "]"

    buffer &= ", signature = \"" & ensureMove(signature) & "\""

  buffer &= ')'

  # Retval handling
  if *retval:
    buffer &= "\n  if r.isSome:\n    let rv = r.get()\n    "
    buffer &= "\n    "
    let rtyp = &retval
    if rtyp == "s":
      buffer &= "return some(rv.body[0].str)"
    elif rtyp == "u":
      buffer &= "return some(rv.body[0].u32)"
    elif rtyp == "i":
      buffer &= "return some(rv.body[0].i32)"
    else:
      if not rtyp.contains('{'):
        # array
        let innerType = toPrimitiveType(rtyp[1 ..< rtyp.len])
        buffer &= "var retvals = newSeqOfCap[" & innerType.multiReplace({"seq[": "", "]": ""}) & "](rv.body.len)\n    "
        buffer &= "for elem in rv.body:\n      "
        buffer &= "retvals &= elem"
        
        if rtyp[1] == 's':
          buffer &= ".str"
        else: discard # TODO: Implement more types

        buffer &= "\n    return some(ensureMove(retvals))"
      else:
        discard
        # TODO: Table decoding

  buffer &= '\n'

proc parseInterface(parser: var XmlParser, buffer: var string, target: string) =
  parser.next()
  let interfaceName = parser.attrValue
  if interfaceName != target:
    return

  buffer &= "\n\n## Bindings for interface `" & interfaceName & '`'

  while true:
    next(parser)
    case parser.kind
    of xmlEof: break
    of xmlElementOpen:
      if parser.elementName == "method":
        generateMethod(parser, interfaceName, buffer)
    else: discard

proc parseNode(parser: var XmlParser, buffer: var string, target: string) =
  while true:
    next(parser)
    case parser.kind
    of xmlEof: break
    of xmlElementOpen:
      if parser.elementName == "interface":
        parseInterface(parser, buffer, target)
    else: discard

proc generateBindings(data: string, target: string): string =
  var buffer = newStringOfCap(2048)
  buffer &= """
## Generated by bindgen (ybus from the nim-windowing project)
## **DO NOT MODIFY THIS MANUALLY!**
import std/[options, tables]
import pkg/ybus/client/unix_sync,
       pkg/ybus/utils/wrapping"""

  var parser: XmlParser
  open(parser, newStringStream(data), "bindgen.xml")
  
  while true:
    next(parser)

    case parser.kind
    of xmlElementStart:
      if parser.elementName == "node":
        parseNode(parser, buffer, target)
    of xmlEof: break
    else: discard
  
  ensureMove(buffer)

proc introspectAndGenerate(path, target: string) =
  let client = newBusClient()
  client.connect()

  let resp = &client.call(path = path, iface = "org.freedesktop.DBus.Introspectable", destination = target, member = "Introspect")
  stdout.write(generateBindings(resp.body[0].str, target))

proc main() {.inline.} =
  var mode: Mode
  var path, target: string

  for kind, key, value in getopt(commandLineParams()):
    case kind
    of cmdEnd: break
    of cmdShortOption:
      if key == "h":
        showHelp(QuitSuccess)
      elif key == "I" and mode == mNone:
        mode = mIntrospect
      elif key == "L" and mode == mNone:
        mode = mParseLocal
    of cmdLongOption:
      if key == "introspect" and mode == mNone:
        mode = mIntrospect
      elif key == "parse-local" and mode == mNone:
        mode = mParseLocal
    of cmdArgument:
      if path.len > 0: target = key
      else: path = key

  case mode
  of mNone: showHelp(QuitFailure)
  of mIntrospect:
    introspectAndGenerate(path, target)
  else: discard

when isMainModule: main()
