#!/data/data/com.termux/files/usr/bin/python
# keystore-agent — ssh-agent for Termux backed by the Android Keystore (termux-keystore), for Play-store Termux, where tergent cannot reach the API.
import json
import os
import socket
import socketserver
import struct
import subprocess
import sys

SOCK = os.path.expanduser("~/.ssh/keystore-agent.sock")

FAILURE = 5
REQUEST_IDENTITIES = 11
IDENTITIES_ANSWER = 12
SIGN_REQUEST = 13
SIGN_RESPONSE = 14


def string(b):
    return struct.pack(">I", len(b)) + b


def read_string(buf, off):
    (n,) = struct.unpack_from(">I", buf, off)
    return buf[off + 4 : off + 4 + n], off + 4 + n


def keystore(*args, data=None):
    return subprocess.run(
        ["termux-keystore", *args], input=data, capture_output=True, timeout=60
    ).stdout


def identities():
    """(blob, alias) for every P-256 key: the only curve this agent signs for."""
    out = []
    for k in json.loads(keystore("list", "-d") or b"[]"):
        if k.get("algorithm") != "EC" or k.get("size") != 256:
            continue
        point = b"\x04" + bytes.fromhex(k["x"]) + bytes.fromhex(k["y"])
        blob = string(b"ecdsa-sha2-nistp256") + string(b"nistp256") + string(point)
        out.append((blob, k["alias"]))
    return out


def der_to_ssh(der):
    # SEQUENCE { INTEGER r, INTEGER s }, short-form lengths only (P-256 fits).
    # A DER INTEGER is already a minimal two's-complement mpint.
    if der[0] != 0x30 or der[2] != 0x02:
        raise ValueError("not an ECDSA DER signature")
    rlen = der[3]
    r = der[4 : 4 + rlen]
    if der[4 + rlen] != 0x02:
        raise ValueError("not an ECDSA DER signature")
    slen = der[5 + rlen]
    s = der[6 + rlen : 6 + rlen + slen]
    return string(b"ecdsa-sha2-nistp256") + string(string(r) + string(s))


def handle(msg):
    if msg[0] == REQUEST_IDENTITIES:
        ids = identities()
        body = struct.pack(">BI", IDENTITIES_ANSWER, len(ids))
        for blob, alias in ids:
            body += string(blob) + string(alias.encode())
        return body
    if msg[0] == SIGN_REQUEST:
        blob, off = read_string(msg, 1)
        data, _ = read_string(msg, off)
        alias = next((a for b, a in identities() if b == blob), None)
        if alias is None:
            return bytes([FAILURE])
        # Empty when the key's user-auth window has lapsed: lock and unlock.
        der = keystore("sign", alias, "SHA256withECDSA", data=data)
        if not der:
            return bytes([FAILURE])
        return bytes([SIGN_RESPONSE]) + string(der_to_ssh(der))
    return bytes([FAILURE])


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        f = self.request.makefile("rb")
        while header := f.read(4):
            (n,) = struct.unpack(">I", header)
            try:
                reply = handle(f.read(n))
            except Exception as e:
                print(f"keystore-agent: {e}", file=sys.stderr)
                reply = bytes([FAILURE])
            self.request.sendall(string(reply))


def main():
    probe = socket.socket(socket.AF_UNIX)
    try:
        probe.connect(SOCK)
        return  # already serving
    except OSError:
        pass
    finally:
        probe.close()
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    os.umask(0o077)
    with socketserver.ThreadingUnixStreamServer(SOCK, Handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
