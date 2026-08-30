#!/usr/bin/env python3
"""Small dependency-free reader for classic libpcap captures."""
import hashlib, struct
from pathlib import Path

def inspect(path):
    data = Path(path).read_bytes()
    if len(data) < 24: raise ValueError('file is shorter than a pcap global header')
    magic = data[:4]
    fmt = {b'\xd4\xc3\xb2\xa1':'<', b'\xa1\xb2\xc3\xd4':'>', b'M<\xb2\xa1':'<', b'\xa1\xb2<M':'>'}.get(magic)
    if not fmt: raise ValueError('unsupported capture format (expected classic pcap)')
    linktype = struct.unpack(fmt+'I', data[20:24])[0]
    off, count, first, last, esp, natt = 24, 0, None, None, 0, 0
    while off + 16 <= len(data):
        sec, frac, incl, orig = struct.unpack(fmt+'IIII', data[off:off+16]); off += 16
        if off + incl > len(data): raise ValueError('truncated packet record')
        pkt = data[off:off+incl]; off += incl; count += 1
        stamp = sec + frac / (1_000_000_000 if magic in (b'M<\xb2\xa1', b'\xa1\xb2<M') else 1_000_000)
        first = stamp if first is None else first; last = stamp
        # Ethernet/VLAN, outer IPv4/IPv6 protocol; enough for validator assertions.
        if linktype == 1 and len(pkt) >= 14:
            et, pos = struct.unpack('!H', pkt[12:14])[0], 14
            if et in (0x8100, 0x88a8) and len(pkt) >= 18: et, pos = struct.unpack('!H', pkt[16:18])[0], 18
            proto = None
            if et == 0x0800 and len(pkt) >= pos+20: proto = pkt[pos+9]
            elif et == 0x86dd and len(pkt) >= pos+40: proto = pkt[pos+6]
            if proto == 50: esp += 1
            elif proto == 17:
                hlen = (pkt[pos] & 15)*4 if et == 0x0800 else 40
                if len(pkt) >= pos+hlen+4 and 4500 in struct.unpack('!HH', pkt[pos+hlen:pos+hlen+4]): natt += 1
    if off != len(data): raise ValueError('trailing partial packet header')
    return {'packet_count':count, 'captured_bytes':len(data), 'observed_packet_span_s':round((last-first) if first is not None else 0, 6), 'link_type':linktype, 'esp_packets':esp, 'udp4500_packets':natt, 'sha256':hashlib.sha256(data).hexdigest()}
