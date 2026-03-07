## Helpful templates used to make `bindgen`'s life easier.
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import std/tables
import pkg/ybus/wire/types

template wrap*[T](value: T): Variant =
  when T is string:
    Variant(kind: VariantKind.String, str: value)
  elif T is uint32:
    Variant(kind: VariantKind.Uint32, u32: value)
  elif T is int32:
    Variant(kind: VariantKind.Int32, i32: value)
  elif T is seq:
    var arr: seq[Variant]
    for elem in value:
      arr.add(wrap(elem))

    Variant(kind: VariantKind.Array, elements: ensureMove(arr))
  elif T is Table:
    var arr: seq[Variant]
    #for key, value in value:
    #  arr &= Variant(kind: VariantKind.DictEntry, key: wrap(key), value: wrap(value))

    Variant(kind: VariantKind.Array, elements: ensureMove(arr))
  elif T is Variant:
    return value
  else:
    {.error: "Cannot wrap " & $T.}
