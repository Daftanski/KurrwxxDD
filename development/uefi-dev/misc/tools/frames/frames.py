#!/usr/bin/env python3
# Usage: frames.py <tap> echo  <src ip> <dst ip> <dst mac> [--size N] [--count N] [--bad-csum] [--wait S] [--vlan ID]
#        frames.py <tap> bcast <src ip> <count> [--size N]
#        frames.py <tap> raw   <hex bytes>
# Raw frames to a tap. echo: ICMP echo request, prints "sent=N replies=M" (replies seen on the tap).
# --size = ICMP payload bytes (frame = 14 + 20 + 8 + size, not padded). bcast: UDP to 255.255.255.255:9.
import argparse
import os
import socket
import struct
import time


def csum(data):
    if len(data) % 2:
        data += b"\0"
    s = sum(struct.unpack("!%dH" % (len(data) // 2), data))
    s = (s >> 16) + (s & 0xFFFF)
    s += s >> 16
    return ~s & 0xFFFF


def ip_hdr(src, dst, proto, payload_len, bad=False, ident=0):
    h = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + payload_len, ident, 0, 64, proto, 0,
                    socket.inet_aton(src), socket.inet_aton(dst))
    c = csum(h)
    if bad:
        c ^= 0xFFFF
    return h[:10] + struct.pack("!H", c) + h[12:]


def mac_bytes(m):
    return bytes(int(x, 16) for x in m.split(":"))


def eth(dst, src, etype, vlan=None):
    if vlan is None:
        return mac_bytes(dst) + mac_bytes(src) + struct.pack("!H", etype)
    return mac_bytes(dst) + mac_bytes(src) + struct.pack("!HHH", 0x8100, vlan, etype)


def open_tap(tap):
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3))
    s.bind((tap, 0))
    return s


def tap_mac(tap):
    with open("/sys/class/net/%s/address" % tap) as f:
        return f.read().strip()


def echo(a):
    s = open_tap(a.tap)
    src_mac = tap_mac(a.tap)
    ident = os.getpid() & 0xFFFF
    payload = bytes(i & 0xFF for i in range(a.size))
    sent = 0
    for seq in range(a.count):
        icmp = struct.pack("!BBHHH", 8, 0, 0, ident, seq) + payload
        icmp = icmp[:2] + struct.pack("!H", csum(icmp)) + icmp[4:]
        frame = eth(a.dmac, src_mac, 0x0800, a.vlan) + ip_hdr(a.src, a.dst, 1, len(icmp), a.bad_csum, seq) + icmp
        try:
            s.send(frame)
        except OSError:
            continue
        sent += 1
    replies = 0
    end = time.time() + a.wait
    s.settimeout(0.2)
    want = socket.inet_aton(a.dst)
    while time.time() < end:
        try:
            data, addr = s.recvfrom(65535)
        except socket.timeout:
            continue
        if addr[2] == socket.PACKET_OUTGOING:
            continue
        off = 14 + (4 if a.vlan is not None else 0)
        if len(data) < off + 28 or data[off - 2:off] != b"\x08\x00":
            continue
        if data[off + 9] != 1 or data[off + 12:off + 16] != want:
            continue
        ihl = (data[off] & 0xF) * 4
        t, _, _, rid, _ = struct.unpack("!BBHHH", data[off + ihl:off + ihl + 8])
        if t == 0 and rid == ident:
            replies += 1
            if replies >= sent:
                break
    print("sent=%d replies=%d" % (sent, replies))


def bcast(a):
    s = open_tap(a.tap)
    src_mac = tap_mac(a.tap)
    payload = bytes(a.size)
    udp = struct.pack("!HHHH", 9, 9, 8 + len(payload), 0) + payload
    frame = eth("ff:ff:ff:ff:ff:ff", src_mac, 0x0800) + ip_hdr(a.src, "255.255.255.255", 17, len(udp)) + udp
    for _ in range(a.count):
        s.send(frame)
    print("sent=%d" % a.count)


def raw(a):
    s = open_tap(a.tap)
    s.send(bytes.fromhex(a.hexbytes))
    print("sent=1")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("tap")
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("echo")
    e.add_argument("src")
    e.add_argument("dst")
    e.add_argument("dmac")
    e.add_argument("--size", type=int, default=0)
    e.add_argument("--count", type=int, default=1)
    e.add_argument("--bad-csum", action="store_true")
    e.add_argument("--wait", type=float, default=2.0)
    e.add_argument("--vlan", type=int, default=None)
    e.set_defaults(fn=echo)
    b = sub.add_parser("bcast")
    b.add_argument("src")
    b.add_argument("count", type=int)
    b.add_argument("--size", type=int, default=18)
    b.set_defaults(fn=bcast)
    r = sub.add_parser("raw")
    r.add_argument("hexbytes")
    r.set_defaults(fn=raw)
    a = p.parse_args()
    a.fn(a)


main()
