#!/usr/bin/env python3
"""Merge a Windows Avro autodict.dct into autodict.plist.

Windows .dct values are Roman phonetic that Windows Avro transliterates at
runtime. iAvro shows autodict.plist values verbatim, so every value must be
converted to Bangla before it is stored (merging them raw is what broke
autocorrect in 4311559). Conversion uses the real AvroParser via
tools/avro_transliterate.m so output matches what the keyboard produces.

Usage: python3 update_autodict.py path/to/autodict.dct [--override]

Existing entries are kept unless --override is given.
"""
import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
PLIST = os.path.join(ROOT, "autodict.plist")
CASESENSITIVE = "oiudgjnrstyz"
BANGLA = re.compile("[ঀ-৿]")


def fix(s):
    """Mirror -[AvroParser fix:]: lowercase everything except case-sensitive letters."""
    return "".join(c if c.lower() in CASESENSITIVE else c.lower() for c in s)


def is_emoticon(key, value):
    if "^" in key or re.fullmatch("[A-Za-z]{2,}:", key):
        return False  # phonetic words such as ta^tI, mo:
    runs = re.findall("[A-Za-z]+", key)
    return (value.lower() == key.lower() and re.search("[^A-Za-z]", key)
            and max(map(len, runs), default=0) <= 2)


def needs_transliteration(key, value):
    if BANGLA.search(value) or not re.search("[A-Za-z]", value):
        return False
    return not is_emoticon(key, value)


def transliterate(values):
    if not values:
        return []
    with tempfile.TemporaryDirectory() as tmp:
        binary = os.path.join(tmp, "avro_transliterate")
        shutil.copy(os.path.join(ROOT, "data.json"), tmp)
        subprocess.run(
            ["clang", "-fno-objc-arc", "-w", "-I", ROOT,
             "-include", os.path.join(ROOT, "AvroKeyboard_Prefix.pch"),
             os.path.join(ROOT, "tools", "avro_transliterate.m"),
             os.path.join(ROOT, "AvroParser.m"),
             "-framework", "Foundation", "-framework", "Cocoa", "-o", binary],
            check=True)
        result = subprocess.run([binary], input=json.dumps(values).encode(),
                                capture_output=True, check=True)
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("dct", help="Windows Avro autodict.dct")
    parser.add_argument("--override", action="store_true",
                        help="replace values of keys that already exist")
    args = parser.parse_args()

    with open(PLIST, "rb") as f:
        autodict = plistlib.load(f)
    print(f"Existing entries: {len(autodict)}")

    # Strict decode: a lossy decode is what produced the "????" entries.
    with open(args.dct, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    incoming = {}
    for line in lines:
        line = line.strip()
        if not line or line.startswith("/"):
            continue
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            incoming[fix(parts[0])] = parts[1]

    pending = {k: v for k, v in incoming.items() if args.override or k not in autodict}
    to_convert = [k for k, v in pending.items() if needs_transliteration(k, v)]
    converted = dict(zip(to_convert, transliterate([pending[k] for k in to_convert])))

    added = updated = 0
    for key, value in pending.items():
        value = converted.get(key, value)
        if key in autodict:
            updated += 1
        else:
            added += 1
        autodict[key] = value

    # Only entries written by this run: some existing emoticons (XD, OwO)
    # legitimately look like Roman words.
    leaked = [k for k in pending
              if not BANGLA.search(autodict[k]) and needs_transliteration(k, autodict[k])]
    if leaked:
        sys.exit(f"Refusing to write: {len(leaked)} Roman values, e.g. {leaked[:5]}")

    with open(PLIST, "wb") as f:
        plistlib.dump(dict(sorted(autodict.items())), f)
    print(f"Added {added}, updated {updated}, skipped {len(incoming) - len(pending)} "
          f"existing. Total: {len(autodict)}")


if __name__ == "__main__":
    main()
