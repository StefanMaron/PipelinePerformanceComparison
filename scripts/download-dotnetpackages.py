#!/usr/bin/env python3
"""
Partial ZIP download of dotnetpackages from BC platform artifact.

Downloads only the 'dotnetpackages/' folder from the BC platform artifact
using HTTP Range requests, without downloading the full multi-GB archive.

Usage:
    BC_VERSION=26.3.36158.36341 python3 download-dotnetpackages.py [output_dir]

    output_dir defaults to 'bc-dotnetpackages'

The dotnetpackages/*.dotnetpackage XML files are the DotNet type definitions
the AL compiler needs when building apps that use DotNet interop (AL0185).
Pass the output_dir path to the compiler via assemblyProbingPaths in app.json.
"""

import os
import sys
import struct
import zlib
import time
import urllib.request
import urllib.error


def range_get(url, start, end, retries=3, timeout=60):
    for attempt in range(retries):
        req = urllib.request.Request(url, headers={'Range': f'bytes={start}-{end}'})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except (urllib.error.URLError, OSError) as e:
            if attempt == retries - 1:
                raise
            print(f'  Retry {attempt + 1}/{retries} after: {e}')
            time.sleep(2 ** attempt)


def get_content_length(url, timeout=30):
    req = urllib.request.Request(url, method='HEAD')
    with urllib.request.urlopen(req, timeout=timeout) as r:
        cl = r.headers.get('Content-Length')
        if not cl:
            raise RuntimeError('Server did not return Content-Length')
        return int(cl)


def find_eocd(data):
    """Find the End of Central Directory record; return (cd_offset, cd_size)."""
    sig = b'\x50\x4b\x05\x06'
    pos = data.rfind(sig)
    if pos == -1:
        return None
    # EOCD: sig(4) disk(2) cd_disk(2) entries_disk(2) entries(2) cd_size(4) cd_offset(4) comment_len(2)
    _, _, _, _, _, cd_size, cd_offset, _ = struct.unpack_from('<4sHHHHIIH', data, pos)
    return cd_offset, cd_size


def parse_central_directory(cd_data):
    """Parse ZIP central directory; return list of (name, local_offset, csize, method, usize)."""
    entries = []
    pos = 0
    sig = b'\x50\x4b\x01\x02'
    while pos + 46 <= len(cd_data):
        if cd_data[pos:pos+4] != sig:
            break
        (_, _, _, _, method, _, _, _, csize, usize,
         fn_len, ex_len, cm_len, _, _, _, local_off) = struct.unpack_from('<4sHHHHHHIIIHHHHHII', cd_data, pos)
        name = cd_data[pos+46:pos+46+fn_len].decode('utf-8', errors='replace')
        entries.append((name, local_off, csize, method, usize))
        pos += 46 + fn_len + ex_len + cm_len
    return entries


def extract_entry(url, name, local_off, csize, method, usize, out_dir, strip_prefix):
    """Fetch one file from the remote ZIP and write it to out_dir."""
    lh = range_get(url, local_off, local_off + 29)
    if lh[:4] != b'\x50\x4b\x03\x04':
        print(f'  WARNING: bad local header magic for {name}')
        return False
    _, _, _, _, _, _, _, _, _, _, fn_len, ex_len = struct.unpack_from('<4sHHHHHIIIHH', lh)
    data_start = local_off + 30 + fn_len + ex_len

    rel = name[len(strip_prefix):]
    if not rel:
        return True  # directory entry for the prefix itself

    out_path = os.path.join(out_dir, rel.replace('/', os.sep))
    parent = os.path.dirname(out_path)
    if parent:
        os.makedirs(parent, exist_ok=True)

    if name.endswith('/'):
        os.makedirs(out_path, exist_ok=True)
        return True

    if csize == 0:
        open(out_path, 'wb').close()
        return True

    raw = range_get(url, data_start, data_start + csize - 1)
    if method == 8:    # DEFLATE
        data = zlib.decompress(raw, -15)
    elif method == 0:  # STORED
        data = raw
    else:
        print(f'  WARNING: unsupported compression {method} for {name}, skipping')
        return False

    with open(out_path, 'wb') as f:
        f.write(data)
    return True


def main():
    bc_version = os.environ.get('BC_VERSION', '26.3.36158.36341')
    out_dir    = sys.argv[1] if len(sys.argv) > 1 else 'bc-dotnetpackages'
    prefix     = 'dotnetpackages/'
    url        = f'https://bcartifacts.azureedge.net/sandbox/{bc_version}/platform'

    print(f'Artifact  : {url}')
    print(f'Output    : {out_dir}')
    print(f'Prefix    : {prefix}')
    print()

    # 1. Get archive size
    print('HEAD request for file size...')
    fsize = get_content_length(url)
    print(f'Archive   : {fsize:,} bytes ({fsize / 1024 / 1024:.0f} MB)')

    # 2. Read tail to locate EOCD
    tail_size  = min(65536, fsize)
    tail_start = fsize - tail_size
    print(f'Reading last {tail_size // 1024} KB to find EOCD...')
    tail = range_get(url, tail_start, fsize - 1)
    eocd = find_eocd(tail)
    if eocd is None:
        print('ERROR: EOCD not found — archive may be ZIP64 (not supported) or corrupted')
        sys.exit(1)
    cd_offset, cd_size = eocd
    print(f'Central dir offset={cd_offset:,}  size={cd_size:,}')

    # 3. Fetch central directory
    print('Fetching central directory...')
    cd_data  = range_get(url, cd_offset, cd_offset + cd_size - 1)
    entries  = parse_central_directory(cd_data)
    print(f'Total entries: {len(entries)}')

    # Print top-level names to help debug wrong prefix
    tops = sorted({e[0].split('/')[0] + ('/' if '/' in e[0] else '') for e in entries})
    print(f'Top-level : {tops[:20]}')
    print()

    # 4. Filter and download
    targets = [e for e in entries if e[0].startswith(prefix)]
    print(f'Entries matching "{prefix}": {len(targets)}')
    if not targets:
        print()
        print('WARNING: no dotnetpackages entries found.')
        print('The prefix may be different — check "Top-level" above.')
        print('Continuing without dotnet packages (compilation may fail with AL0185).')
        sys.exit(0)  # non-fatal: let the compile step surface the real error

    os.makedirs(out_dir, exist_ok=True)
    ok = fail = 0
    total_bytes = 0
    for name, local_off, csize, method, usize in targets:
        rel = name[len(prefix):]
        if not rel or name.endswith('/'):
            continue
        print(f'  {rel}  ({usize:,} B)')
        if extract_entry(url, name, local_off, csize, method, usize, out_dir, prefix):
            ok += 1
            total_bytes += usize
        else:
            fail += 1

    print()
    print(f'Extracted : {ok} files  ({total_bytes / 1024:.0f} KB)  failures: {fail}')
    abs_out = os.path.abspath(out_dir)
    print(f'Path      : {abs_out}')

    # Write path to a file so the workflow step can read it easily
    with open('dotnetpackages_path.txt', 'w') as f:
        f.write(abs_out)


if __name__ == '__main__':
    main()
