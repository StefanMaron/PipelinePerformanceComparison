#!/usr/bin/env python3
"""
Download dotnetpackages from BC platform artifact using HTTP Range requests.

Usage: python3 download-dotnetpackages.py <artifact_url> <total_size> <output_dir>

Downloads only the 'dotnetpackages/' folder from the BC platform artifact
using HTTP Range requests, without downloading the full multi-GB archive.

The artifact_url and total_size should be obtained beforehand (e.g. via
Get-BCArtifactUrl + a HEAD request in PowerShell) so this script works
without any dependency on BcContainerHelper.

The dotnetpackages/*.dotnetpackage XML files are the DotNet type definitions
the AL compiler needs when building apps that use DotNet interop (AL0185).
Pass the output_dir path to the compiler via /assemblyProbingPaths.

Exits 0 on success, 1 on failure.
"""

import struct
import sys
import os
import subprocess
import zlib
import tempfile
import shutil


def download(url, output_path, byte_range=None):
    """Download a URL (or byte range) to a file using curl. Returns True on success."""
    cmd = ['curl', '-s', '-f', '-o', output_path]
    if byte_range:
        cmd.extend(['-r', byte_range])
    cmd.append(url)
    result = subprocess.run(cmd, capture_output=True)
    if result.returncode != 0:
        print(f"ERROR: curl failed (exit {result.returncode}): {result.stderr.decode()}")
        return False
    return True


def parse_central_directory(data, cd_start, entry_count):
    """Parse ZIP central directory entries. Returns list of entry dicts."""
    entries = []
    pos = cd_start
    for _ in range(entry_count):
        if pos + 46 > len(data):
            print("WARNING: Truncated central directory")
            break
        if data[pos:pos+4] != b'\x50\x4b\x01\x02':
            print(f"WARNING: Invalid CD entry signature at pos {pos}")
            break

        comp_method  = struct.unpack_from('<H', data, pos + 10)[0]
        comp_size    = struct.unpack_from('<I', data, pos + 20)[0]
        uncomp_size  = struct.unpack_from('<I', data, pos + 24)[0]
        name_len     = struct.unpack_from('<H', data, pos + 28)[0]
        extra_len    = struct.unpack_from('<H', data, pos + 30)[0]
        comment_len  = struct.unpack_from('<H', data, pos + 32)[0]
        local_offset = struct.unpack_from('<I', data, pos + 42)[0]
        name = data[pos+46:pos+46+name_len].decode('utf-8', errors='replace')

        entries.append({
            'name':        name,
            'comp_method': comp_method,
            'comp_size':   comp_size,
            'uncomp_size': uncomp_size,
            'offset':      local_offset,
        })
        pos += 46 + name_len + extra_len + comment_len

    return entries


def main():
    if len(sys.argv) != 4:
        print("Usage: download-dotnetpackages.py <artifact_url> <total_size> <output_dir>")
        sys.exit(1)

    url        = sys.argv[1]
    total_size = int(sys.argv[2])
    output_dir = sys.argv[3]
    prefix     = 'dotnetpackages/'

    print(f"Artifact  : {url}")
    print(f"Size      : {total_size:,} bytes ({total_size / 1024 / 1024:.0f} MB)")
    print(f"Output    : {output_dir}")
    print(f"Prefix    : {prefix}")
    print()

    os.makedirs(output_dir, exist_ok=True)
    tmp_dir = tempfile.mkdtemp(prefix='dotnetpkg-dl-')

    try:
        # Step 1: Download last 64 KB to locate the EOCD record
        tail_size  = 65536
        tail_start = total_size - tail_size
        tail_file  = os.path.join(tmp_dir, 'tail.bin')
        print(f"Downloading last {tail_size // 1024} KB to find EOCD...")
        if not download(url, tail_file, f'{tail_start}-{total_size - 1}'):
            sys.exit(1)

        with open(tail_file, 'rb') as f:
            tail = f.read()

        eocd_pos = tail.rfind(b'\x50\x4b\x05\x06')
        if eocd_pos == -1:
            print("ERROR: EOCD not found - archive may be ZIP64 or corrupted")
            sys.exit(1)

        entry_count = struct.unpack_from('<H', tail, eocd_pos + 10)[0]
        cd_size     = struct.unpack_from('<I', tail, eocd_pos + 12)[0]
        cd_offset   = struct.unpack_from('<I', tail, eocd_pos + 16)[0]
        print(f"Central directory: {entry_count} entries, {cd_size // 1024} KB at offset {cd_offset}")

        # Step 2: Download central directory if it wasn't included in the tail
        cd_start_in_tail = len(tail) - (total_size - cd_offset)
        if cd_start_in_tail < 0:
            print(f"Central directory not in tail, downloading from offset {cd_offset}...")
            cd_file = os.path.join(tmp_dir, 'cd.bin')
            if not download(url, cd_file, f'{cd_offset}-{total_size - 1}'):
                sys.exit(1)
            with open(cd_file, 'rb') as f:
                tail = f.read()
            cd_start_in_tail = 0

        entries = parse_central_directory(tail, cd_start_in_tail, entry_count)
        print(f"Parsed {len(entries)} entries")

        tops = sorted({e['name'].split('/')[0] for e in entries if '/' in e['name']})
        print(f"Top-level folders: {tops[:20]}")
        print()

        # Step 3: Filter to dotnetpackages/ entries with actual data
        matching = [e for e in entries if e['name'].startswith(prefix) and e['comp_size'] > 0]
        print(f"Matching '{prefix}': {len(matching)} files")

        if not matching:
            print(f"ERROR: No dotnetpackages entries found.")
            print("Check top-level folders above for the correct prefix.")
            sys.exit(1)

        # Step 4: Calculate the byte range that covers all matching entries
        first_offset = min(e['offset'] for e in matching)
        max_offset   = max(e['offset'] for e in matching)

        # Include non-matching entries that fall within the range (may be interleaved)
        all_in_range = sorted(
            [e for e in entries if first_offset <= e['offset'] <= max_offset],
            key=lambda e: e['offset']
        )

        range_end = 0
        for e in all_in_range:
            # local header (30) + name + extra (256 safety margin) + compressed data
            entry_end = e['offset'] + 30 + len(e['name'].encode('utf-8')) + 256 + e['comp_size']
            range_end = max(range_end, entry_end)

        download_size = range_end - first_offset
        if download_size > total_size * 0.5:
            print(f"ERROR: Range ({download_size // 1048576} MB) exceeds 50% of total ({total_size // 1048576} MB), aborting")
            sys.exit(1)

        savings = round((1 - download_size / total_size) * 100)
        print(f"Downloading range {first_offset}-{range_end} ({download_size // 1048576} MB, {savings}% savings vs full download)")

        # Step 5: Download the range as one bulk request
        range_file = os.path.join(tmp_dir, 'range.bin')
        if not download(url, range_file, f'{first_offset}-{range_end}'):
            sys.exit(1)

        with open(range_file, 'rb') as f:
            data = f.read()
        print(f"Downloaded {len(data):,} bytes")
        print()

        # Step 6: Extract all files from dotnetpackages/ out of the range buffer
        extracted   = 0
        total_bytes = 0
        for entry in matching:
            name     = entry['name']
            basename = os.path.basename(name)
            if not basename:
                continue  # directory entry

            pos = entry['offset'] - first_offset
            if pos < 0 or pos + 30 > len(data):
                print(f"  WARNING: {basename} outside range, skipping")
                continue

            if data[pos:pos+4] != b'\x50\x4b\x03\x04':
                print(f"  WARNING: Invalid local header for {basename}, skipping")
                continue

            name_len   = struct.unpack_from('<H', data, pos + 26)[0]
            extra_len  = struct.unpack_from('<H', data, pos + 28)[0]
            data_start = pos + 30 + name_len + extra_len

            if data_start + entry['comp_size'] > len(data):
                print(f"  WARNING: {basename} extends beyond range, skipping")
                continue

            comp_data = data[data_start:data_start + entry['comp_size']]

            if entry['comp_method'] == 0:    # stored
                file_data = comp_data
            elif entry['comp_method'] == 8:  # deflated
                try:
                    file_data = zlib.decompress(comp_data, -15)
                except zlib.error as e:
                    print(f"  WARNING: Decompression failed for {basename}: {e}")
                    continue
            else:
                print(f"  WARNING: Unsupported compression {entry['comp_method']} for {basename}, skipping")
                continue

            out_path = os.path.join(output_dir, basename)
            with open(out_path, 'wb') as f:
                f.write(file_data)
            extracted   += 1
            total_bytes += len(file_data)
            print(f"  {basename}  ({len(file_data):,} B)")

        print()
        print(f"Extracted : {extracted} files  ({total_bytes // 1024} KB)")

        if extracted == 0:
            print("ERROR: No files were extracted")
            sys.exit(1)

    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == '__main__':
    main()
