# keyring-ctl — lock, unlock or query the default Secret Service collection.
import sys

from jeepney import DBusAddress, new_method_call
from jeepney.io.blocking import open_dbus_connection
from jeepney.wrappers import DBusErrorResponse, unwrap_msg

USAGE = "usage: keyring-ctl lock | is-locked | unlock  (password on stdin)"

SERVICE = DBusAddress(
    "/org/freedesktop/secrets",
    bus_name="org.freedesktop.secrets",
    interface="org.freedesktop.Secret.Service",
)
# gnome-keyring only: the Secret Service API itself unlocks only via a prompt.
INTERNAL = SERVICE.with_interface(
    "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface"
)


def call(conn, address, method, signature=None, body=()):
    msg = new_method_call(address, method, signature, body)
    return unwrap_msg(conn.send_and_get_reply(msg))


def is_locked(conn, collection):
    props = DBusAddress(
        collection,
        bus_name=SERVICE.bus_name,
        interface="org.freedesktop.DBus.Properties",
    )
    body = ("org.freedesktop.Secret.Collection", "Locked")
    (value,) = call(conn, props, "Get", "ss", body)
    return value[1]


def unlock(conn, collection, password):
    algorithm = ("plain", ("s", ""))
    _, session = call(conn, SERVICE, "OpenSession", "sv", algorithm)
    body = (collection, (session, b"", password, "text/plain"))
    call(conn, INTERNAL, "UnlockWithMasterPassword", "o(oayays)", body)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in (
        "lock", "is-locked", "unlock"
    ):
        sys.exit(USAGE)
    action = sys.argv[1]
    with open_dbus_connection(bus="SESSION") as conn:
        (collection,) = call(conn, SERVICE, "ReadAlias", "s", ("default",))
        if collection == "/":
            sys.exit("keyring-ctl: no default collection")
        if action == "lock":
            call(conn, SERVICE, "Lock", "ao", ([collection],))
        elif action == "is-locked":
            sys.exit(0 if is_locked(conn, collection) else 1)
        else:
            password = sys.stdin.buffer.read()
            if not password:
                sys.exit("keyring-ctl: no password on stdin")
            unlock(conn, collection, password)
            if is_locked(conn, collection):
                sys.exit("keyring-ctl: password rejected")


try:
    main()
except DBusErrorResponse as e:
    sys.exit(f"keyring-ctl: {e}")
