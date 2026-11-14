#!/usr/bin/env python3
"""Read and enforce `com.oculus.supportedDevices` in a binary AndroidManifest.xml.

Why this matters: Horizon OS puts an app into compatibility mode when its manifest does
not list the physical headset, and then device APIs report an older model (see
docs/measurements/device-identity.md). A Quest 3S would silently look like a Quest 3.

The overlay packaging already appends a `com.oculus.supportedDevices` meta-data element.
If the base manifest already has one, that produces two elements with the same name, and
Android keeps whichever it encounters last. So the value has to be *merged* into the
existing element, and the result has to be *read back* instead of assumed.

Binary XML is read directly (no aapt2, no Android SDK) so this works wherever the build
runs. Only what is needed is parsed: the string pool and start elements with attributes.

Usage:
    python3 Gquest-Hybrid/tools/overlay_manifest.py --test
"""
import struct
import sys

NAMESPACE_ANDROID = "http://schemas.android.com/apk/res/android"
DEVICES_NAME = "com.oculus.supportedDevices"
# Canonical identifiers from Meta's manifest documentation.
REQUIRED_DEVICES = "quest3|quest3s|questpro|quest2"
SUPPORTED = ("quest", "quest2", "quest3", "quest3s", "questpro", "cambria")

TYPE_STRING = 0x03
CHUNK_STRING_POOL = 0x0001
CHUNK_START_ELEMENT = 0x0102


class ManifestError(ValueError):
    """The file is not the binary XML layout this project produces."""


def _u16(data, offset):
    return struct.unpack_from("<H", data, offset)[0]


def _u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def string_pool(xml):
    """Return the string pool of a binary XML document."""
    if len(xml) < 8 or _u16(xml, 0) != 0x0003:
        raise ManifestError("not an Android binary XML document")
    kind, header, _ = struct.unpack_from("<HHI", xml, 8)
    if kind != CHUNK_STRING_POOL or header != 28:
        raise ManifestError(f"unexpected resource chunk {kind:#x}")
    count, styles, flags, string_start, _style_start = struct.unpack_from("<IIIII", xml, 16)
    if styles != 0 or flags & 0x100:
        raise ManifestError("styled or UTF-8 string pools are not supported")
    strings = []
    for index in range(count):
        position = 8 + string_start + _u32(xml, 8 + header + 4 * index)
        length = _u16(xml, position)
        if length >= 0x8000:
            raise ManifestError("string too long for this pool layout")
        strings.append(xml[position + 2:position + 2 + length * 2].decode("utf-16le"))
    return strings


def declared_devices(xml):
    """Every `com.oculus.supportedDevices` value in the manifest, in document order."""
    strings = string_pool(xml)
    pool_at = 8
    _, _, pool_size = struct.unpack_from("<HHI", xml, pool_at)
    found = []
    position = pool_at + pool_size
    while position + 8 <= len(xml):
        kind, _header, size = struct.unpack_from("<HHI", xml, position)
        if size < 8:
            raise ManifestError(f"invalid chunk size at {position}")
        if kind == CHUNK_START_ELEMENT:
            name = strings[_u32(xml, position + 20)]
            attributes_start, attribute_size, count = struct.unpack_from("<HHH", xml, position + 24)
            attributes = {}
            for index in range(count):
                base = position + 16 + attributes_start + index * attribute_size
                attribute = strings[_u32(xml, base + 4)]
                if xml[base + 15] == TYPE_STRING:
                    attributes[attribute] = strings[_u32(xml, base + 16)]
            if name == "meta-data" and attributes.get("name") == DEVICES_NAME:
                if "value" in attributes:
                    found.append(attributes["value"])
        position += size
    return found


def ensure_devices(value, required=REQUIRED_DEVICES):
    """Merge the required identifiers into an existing value, keeping its order.

    Existing entries are kept: dropping a device the base app declared would take it out
    of support, which is not this tool's decision. Duplicates and empty parts are removed.
    """
    def clean(text):
        return [part.strip().lower() for part in text.split("|") if part.strip()]

    merged = []
    for part in clean(value or "") + clean(required):
        if part not in merged:
            merged.append(part)
    unknown = [part for part in merged if part not in SUPPORTED]
    if unknown:
        raise ManifestError(f"unknown device identifier(s): {', '.join(unknown)}")
    return "|".join(merged)


def missing_devices(values, required=REQUIRED_DEVICES):
    """Required identifiers that no value provides, and how many elements exist."""
    present = set()
    for value in values:
        present.update(part.strip() for part in value.split("|") if part.strip())
    needed = [part for part in required.split("|") if part not in present]
    return needed, len(values)


def _encode(strings, chunks):
    data, offsets = bytearray(), []
    for text in strings:
        encoded = text.encode("utf-16le")
        if len(encoded) // 2 >= 0x8000:
            raise ManifestError("string too long for this pool layout")
        offsets.append(len(data))
        data += struct.pack("<H", len(encoded) // 2) + encoded + b"\0\0"
    data += bytes((-len(data)) % 4)
    string_start = 28 + 4 * len(strings)
    payload = (struct.pack("<HHIIIIII", CHUNK_STRING_POOL, 28, string_start + len(data),
                           len(strings), 0, 0, string_start, 0)
               + b"".join(struct.pack("<I", offset) for offset in offsets) + bytes(data))
    body = payload + b"".join(chunks)
    return struct.pack("<HHI", 0x0003, 8, 8 + len(body)) + body


def _synthetic(*document_devices):
    """Build a minimal manifest with one supportedDevices element per value."""
    strings = ["manifest", "application", "meta-data", "name", "value",
               NAMESPACE_ANDROID, DEVICES_NAME, *document_devices]

    def index(text):
        return strings.index(text)

    def attribute(name, value):
        return struct.pack("<IIIHBBI", index(NAMESPACE_ANDROID), index(name), index(value),
                           8, 0, TYPE_STRING, index(value))

    def start(name, attributes=()):
        return (struct.pack("<HHIII", CHUNK_START_ELEMENT, 16, 36 + 20 * len(attributes), 0,
                            0xFFFFFFFF)
                + struct.pack("<IIHHHHHH", 0xFFFFFFFF, index(name), 20, 20, len(attributes),
                              0, 0, 0)
                + b"".join(attributes))

    def end(name):
        return struct.pack("<HHIIIII", 0x0103, 16, 24, 0, 0xFFFFFFFF, 0xFFFFFFFF, index(name))

    def leaf(name, attributes):
        return start(name, attributes) + end(name)

    metas = [leaf("meta-data", [attribute("name", DEVICES_NAME), attribute("value", value)])
             for value in document_devices]
    return _encode(strings, [start("manifest"), start("application"), *metas,
                            end("application"), end("manifest")])


def run_self_test():
    """Synthetic manifests only: proves the reader and the merge rule."""
    failures = []

    def check(condition, message):
        if not condition:
            failures.append(message)

    outdated = _synthetic("quest2|questpro")
    values = declared_devices(outdated)
    check(values == ["quest2|questpro"], f"value not read back: {values}")

    merged = ensure_devices(values[0])
    check(merged == "quest2|questpro|quest3|quest3s", f"merge order wrong: {merged}")
    check(ensure_devices(merged) == merged, "merge is not idempotent")
    check(ensure_devices("") == REQUIRED_DEVICES, "empty value must become the requirement")
    # required="" isolates the deduplication from the enforced device set.
    check(ensure_devices("quest3|quest3|quest3s", required="") == "quest3|quest3s",
          "duplicates not removed")

    complete = _synthetic("quest3|quest3s|questpro|quest2")
    needed, count = missing_devices(declared_devices(complete))
    check(needed == [] and count == 1, f"complete manifest misjudged: {needed}/{count}")

    needed, count = missing_devices(declared_devices(outdated))
    check(needed == ["quest3", "quest3s"], f"missing devices wrong: {needed}")

    # Two elements in one manifest are a packaging bug, not a valid state: Android keeps
    # whichever it encounters last, so the declared set is undefined.
    duplicated = _synthetic("quest3|quest3s", "quest2|questpro")
    check(declared_devices(duplicated) == ["quest3|quest3s", "quest2|questpro"],
          f"two elements not both reported: {declared_devices(duplicated)}")
    check(missing_devices(declared_devices(duplicated))[1] == 2,
          "duplicate element count not detected")

    try:
        ensure_devices("quest9")
    except ManifestError:
        pass
    else:
        failures.append("unknown identifier was accepted")

    try:
        string_pool(b"not xml at all")
    except ManifestError:
        pass
    else:
        failures.append("garbage was accepted as binary XML")

    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        return 3
    print("PASS overlay manifest: value read back, merge keeps order and drops duplicates, "
          "missing identifiers detected, unknown identifiers and garbage rejected")
    return 0


def main():
    if "--test" in sys.argv[1:]:
        return run_self_test()
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main())
