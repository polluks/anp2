#!/usr/bin/env python3
"""Assemble the game music asset from the per-channel pt2gt output streams.

pt2gt emits one file per AY channel, each starting with its own comment header
and a "music_level_chN:" label. The game asset needs a single file with an
.export directive and the channels renamed to music_level_0/1/2, each stream
closed by the $00 end marker that sound.s expects.
"""

import argparse
import re
import sys

LABEL_RE = re.compile(r'^\s*[A-Za-z_][A-Za-z0-9_]*:\s*$')
BYTE_RE = re.compile(r'^\s*\.byte\b', re.IGNORECASE)


def read_channel(path):
    """Return the .byte lines of a pt2gt channel stream, comments stripped."""
    body = []
    with open(path, 'r', encoding='ascii', errors='replace') as f:
        for line in f:
            if LABEL_RE.match(line):
                body = []
                continue
            if BYTE_RE.match(line):
                code = line.split(';', 1)[0].rstrip()
                body.append(code)
    return body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--prefix', default='music_level')
    ap.add_argument('--source', default='')
    ap.add_argument('--speed', default='')
    ap.add_argument('channels', nargs='+', help='channel .s files in order')
    args = ap.parse_args()

    streams = [read_channel(p) for p in args.channels]
    for path, body in zip(args.channels, streams):
        if not body:
            print("error: no .byte data in %s" % path, file=sys.stderr)
            return 1

    names = ['%s_%d' % (args.prefix, i) for i in range(len(streams))]

    out = []
    out.append('; ANP2 - %s music data (converted from PT3)' % args.prefix)
    out.append('; Original music by Oleg Nikitin (n1k-o)')
    if args.source:
        out.append('; Source: %s' % args.source)
    if args.speed:
        out.append('; Speed: %s' % args.speed)
    out.append(';')
    out.append('; Format: delta_time, note, waveform, duty_lo, duty_hi, AD, SR')
    out.append('')
    out.append('.export %s' % ', '.join(names))
    out.append('')
    out.append('.segment "RODATA"')
    out.append('')

    for name, body in zip(names, streams):
        out.append('%s:' % name)
        out.extend(body)
        out.append('    .byte $00')
        out.append('')

    with open(args.out, 'w', encoding='ascii') as f:
        f.write('\n'.join(out).rstrip('\n') + '\n')

    print("wrote %s (%d channels, %d bytes total)"
          % (args.out, len(streams), sum(len(s) for s in streams)))
    return 0


if __name__ == '__main__':
    sys.exit(main())