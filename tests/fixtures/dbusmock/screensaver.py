#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 v3DJG6GL <72495210+v3DJG6GL@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Spawn an isolated session DBus + a mock `org.freedesktop.ScreenSaver`
service on it, so tests/cpp/tst_screenlockmonitor.cpp can drive
ScreenLockMonitor's actual subscribe / GetActive / ActiveChanged path
without colliding with the real kscreenlocker on the dev box's session
bus (or needing one at all on CI).

Protocol (one line per side):

  stdout (one line at startup, one per command):
      BUS <dbus-session-address>      — printed once
      OK                              — after each successful command
      ERR <msg>                       — on bad input

  stdin (one command per line, terminated by newline):
      active true       — set GetActive to return true + emit ActiveChanged(true)
      active false      — same, false
      quit              — tear down the bus and exit

  stderr: free-text logs; tests don't parse this.
"""
from __future__ import annotations

import os
import sys

import dbus
from dbus import Boolean
from dbusmock import DBusTestCase


SERVICE = "org.freedesktop.ScreenSaver"
PATH = "/org/freedesktop/ScreenSaver"
IFACE = "org.freedesktop.ScreenSaver"
MOCK_IFACE = "org.freedesktop.DBus.Mock"


def main() -> int:
    # Spin up a private session bus; this exports DBUS_SESSION_BUS_ADDRESS
    # into our env, which spawn_server() and get_dbus() then pick up.
    DBusTestCase.start_session_bus()
    addr = os.environ["DBUS_SESSION_BUS_ADDRESS"]

    # Spawn the mock service on our private bus. Returns a Popen which
    # we keep alive until "quit".
    proc = DBusTestCase.spawn_server(SERVICE, PATH, IFACE, system_bus=False,
                                     stdout=sys.stderr)

    bus = dbus.SessionBus()
    DBusTestCase.wait_for_bus_object(SERVICE, PATH, system_bus=False)
    mock = bus.get_object(SERVICE, PATH)

    def set_active(value: bool) -> None:
        # AddMethod(interface, name, in_sig, out_sig, code-string) wires
        # GetActive to return our desired bool. Then EmitSignal pushes
        # ActiveChanged so any subscriber gets the wake-up.
        ret_str = "True" if value else "False"
        mock.AddMethod(IFACE, "GetActive", "", "b", f"ret = {ret_str}",
                       dbus_interface=MOCK_IFACE)
        mock.EmitSignal(IFACE, "ActiveChanged", "b", [Boolean(value)],
                        dbus_interface=MOCK_IFACE)

    set_active(False)
    print(f"BUS {addr}", flush=True)

    exit_code = 0
    try:
        for line in sys.stdin:
            cmd = line.strip().split()
            if not cmd:
                continue
            if cmd[0] == "quit":
                break
            if cmd[0] == "active" and len(cmd) == 2:
                set_active(cmd[1].lower() == "true")
                print("OK", flush=True)
                continue
            print(f"ERR unknown: {line.strip()!r}", flush=True)
    except Exception as e:  # noqa: BLE001
        print(f"ERR exception: {e}", flush=True, file=sys.stderr)
        exit_code = 1
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=3)
        except Exception:
            pass
        try:
            DBusTestCase.tearDownClass()
        except Exception:
            pass

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
