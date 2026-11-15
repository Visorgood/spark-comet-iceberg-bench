#!/usr/bin/env python3
"""Verify a downloaded file against a published checksum file.

usage: verify_checksum.py FILE CHECKSUM_FILE sha512|sha1
Accepts both "HEX  file" and "file: HE X ..." layouts (Apache archives use either).
"""
import hashlib
import os
import re
import sys

path, sumfile, algo = sys.argv[1:4]
h = hashlib.new(algo)
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
text = open(sumfile).read().replace(os.path.basename(path), "")
text = re.sub(r"(?i)sha-?(512|1)", "", text)  # drop "SHA512 (...) =" style labels
expected = re.sub(r"[^0-9a-fA-F]", "", text).lower()
if expected != h.hexdigest():
    sys.exit(f"checksum mismatch for {path}: expected {expected}, got {h.hexdigest()}")
print(f"{algo} ok: {os.path.basename(path)}")
