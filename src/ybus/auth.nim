## D-Bus authentication implementation
##
## Copyright (C) 2026 Trayambak Rai (xtrayambak@disroot.org)
import std/[net, options, strutils]
import pkg/shakar

type
  AuthState* {.pure, size: sizeof(uint8).} = enum
    Start
    Completed
    Error

  AuthMachine* = object ## Authentication state machine
    state: AuthState

    pending: string
    cookie: Option[string]

func feed*(machine: var AuthMachine, data: string) =
  case machine.state
  of AuthState.Start:
    if data[0] == 'O' and data[1] == 'K':
      machine.cookie = some(data.split("OK")[1].strip())

      machine.state = AuthState.Completed
      machine.pending = "BEGIN\r\n"
    elif data == "ERROR":
      machine.state = AuthState.Error
      machine.pending.reset()
  of {AuthState.Completed, AuthState.Error}:
    return

proc performAuth*(
    machine: var AuthMachine, uid: uint64, sock: net.Socket
): Option[string] {.sideEffect, discardable.} =
  machine.pending = "\0AUTH EXTERNAL " & toHex($uid) & "\r\n"

  while machine.state notin {AuthState.Completed, AuthState.Error}:
    sock.send(machine.pending)
    machine.feed(sock.recvLine())

  if machine.state == AuthState.Completed:
    sock.send(machine.pending) # Send the BEGIN command

  machine.cookie
