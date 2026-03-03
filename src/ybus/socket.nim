## D-Bus socket-related routines
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import std/[os, options, strutils]
import pkg/[shakar]

type SessionBusAddress* = object
  transport*: string
  path*, abstract*, runtime*, tmpdir*: Option[string]

func parseSessionBusAddress*(source: string): Option[SessionBusAddress] =
  let transport = source.split(':')
  if transport.len < 2:
    return none(SessionBusAddress)

  let payload = transport[1]

  var busAddress: SessionBusAddress
  busAddress.transport = transport[0]

  let splitted = payload.split('=')
  if splitted.len < 2:
    return none(SessionBusAddress)

  let key = splitted[0]
  let value = splitted[1]

  case key
  of "path":
    busAddress.path = some(value)
  of "abstract":
    busAddress.abstract = some(value)
  of "runtime":
    busAddress.runtime = some(value)
  of "tmpdir":
    busAddress.tmpdir = some(value)
  else:
    return none(SessionBusAddress)

  some(ensureMove(busAddress))

proc resolveBusPath(address: SessionBusAddress): Option[string] {.sideEffect.} =
  if *address.path:
    # 1. If the `path` key is specified, simply return the
    # value component attached (fastest, best case scenario)
    return address.path

  if *address.runtime:
    # 2. If the `runtime` key is specified, we need to return $XDG_RUNTIME_DIR/bus
    return some(getEnv("XDG_RUNTIME_DIR") / "bus")

  # TODO: Support abstract keys.
  none(string)

proc getSessionBusPath*(): Option[string] {.sideEffect.} =
  ## This routine returns the session bus socket path,
  ## if there is a way to find it. It also automatically resolves
  ## non-straightforward paths like runtime-key paths.
  ##
  ## **NOTE**: It does not guarantee that a returned
  ## path really exists, or is a valid UNIX socket.

  let env = getEnv("DBUS_SESSION_BUS_ADDRESS")
  if env.len < 1:
    # If DBUS_SESSION_BUS_ADDRESS isn't set (unlikely),
    # we have no compliant way of finding the session bus.
    return none(string)

  let busAddr = parseSessionBusAddress(env)
  if !busAddr:
    # If we cannot parse DBUS_SESSION_BUS_ADDRESS,
    # we have no compliant way of finding the session bus.
    return none(string)

  resolveBusPath(&busAddr)
