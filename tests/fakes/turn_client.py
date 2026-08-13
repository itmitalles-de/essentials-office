#!/usr/bin/env python3
"""Perform one authenticated TURN allocation without exposing the shared secret in argv."""

from __future__ import annotations

import base64
import hashlib
import hmac
import os
import secrets
import socket
import struct
import sys
import time

MAGIC = 0x2112A442


def attribute(kind: int, value: bytes) -> bytes:
    padding = b"\0" * ((4 - len(value) % 4) % 4)
    return struct.pack("!HH", kind, len(value)) + value + padding


def parse(packet: bytes) -> tuple[int, dict[int, bytes]]:
    if len(packet) < 20:
        raise RuntimeError("short TURN response")
    message_type, length, magic = struct.unpack("!HHI", packet[:8])
    if magic != MAGIC or len(packet) < 20 + length:
        raise RuntimeError("invalid TURN response")
    attrs: dict[int, bytes] = {}
    offset = 20
    while offset + 4 <= 20 + length:
        kind, size = struct.unpack("!HH", packet[offset : offset + 4])
        attrs[kind] = packet[offset + 4 : offset + 4 + size]
        offset += 4 + ((size + 3) // 4) * 4
    return message_type, attrs


def request(sock: socket.socket, host: str, transaction: bytes, attrs: bytes, key: bytes | None = None) -> bytes:
    if key is None:
        message = struct.pack("!HHI", 0x0003, len(attrs), MAGIC) + transaction + attrs
    else:
        final_length = len(attrs) + 24
        header = struct.pack("!HHI", 0x0003, final_length, MAGIC) + transaction
        digest = hmac.new(key, header + attrs, hashlib.sha1).digest()
        message = header + attrs + attribute(0x0008, digest)
    sock.sendto(message, (host, 3478))
    return sock.recv(4096)


def main() -> int:
    secret_path = os.environ["TURN_SECRET_FILE"]
    host = os.environ.get("TURN_HOST", "turn")
    shared_secret = open(secret_path, "rb").read().strip()
    if len(shared_secret) < 32:
        raise RuntimeError("invalid protected TURN secret fixture")
    transaction = secrets.token_bytes(12)
    requested_transport = attribute(0x0019, bytes([17, 0, 0, 0]))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(5)
        first_type, first_attrs = parse(request(sock, host, transaction, requested_transport))
        if first_type != 0x0113 or 0x0014 not in first_attrs or 0x0015 not in first_attrs:
            raise RuntimeError("TURN server did not issue a long-term-auth challenge")
        realm = first_attrs[0x0014]
        nonce = first_attrs[0x0015]
        username = f"{int(time.time()) + 3600}:synthetic-office".encode()
        password = base64.b64encode(hmac.new(shared_secret, username, hashlib.sha1).digest())
        key = hashlib.md5(username + b":" + realm + b":" + password, usedforsecurity=False).digest()
        attrs = requested_transport + attribute(0x0006, username) + attribute(0x0014, realm) + attribute(0x0015, nonce)
        response_type, _ = parse(request(sock, host, transaction, attrs, key))
        if response_type != 0x0103:
            raise RuntimeError(f"authenticated TURN allocation failed with response 0x{response_type:04x}")
    print("turn-connectivity-test: authenticated synthetic allocation passed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exception:
        print(f"turn-connectivity-test: {exception}", file=sys.stderr)
        sys.exit(1)
