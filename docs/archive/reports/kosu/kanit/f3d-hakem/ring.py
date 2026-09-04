import struct, sys
p = sys.argv[1]
b = open(p, 'rb').read()
magic, count, nextSeq = struct.unpack_from('<8sqq', b, 0)
print('magic', magic, 'count', count, 'nextSeq', nextSeq)
REC = 320
HDR = 4096
recs = []
n = (len(b) - HDR) // REC
for i in range(n):
    o = HDR + i * REC
    seq, ts, rc, suite, asserts, tool = struct.unpack_from('<qqiiii', b, o)
    sig = b[o+32:o+49].split(b'\x00')[0].decode()
    err = b[o+49:o+66].split(b'\x00')[0].decode()
    path = b[o+84:o+224].split(b'\x00')[0].decode(errors='replace')
    raw = b[o+224:o+320].split(b'\x00')[0].decode(errors='replace')
    if seq:
        recs.append((seq, ts, sig, err, path, raw))
recs.sort()
want = sys.argv[2:] if len(sys.argv) > 2 else []
print('seq range', recs[0][0], '..', recs[-1][0], 'n', len(recs))
for r in recs:
    if not want or str(r[0]) in want or r[2] in want:
        print(r[0], r[1], 'sig=' + r[2], 'err=' + r[3], repr(r[5][:70]))
