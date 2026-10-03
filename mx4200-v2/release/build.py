#!/usr/bin/env python3
"""Prepare and sign the MX4200 first-boot release. Never commit the private key."""
import argparse
import hashlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULES = ["auto", "samba", "led/rev3", "provision"]
RELEASE_FILES = ["uci-defaults.sh"] + [f"modules/{m}/install.sh" for m in MODULES if m != "provision"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_shell(path):
    subprocess.run(["sh", "-n", str(path)], check=True)
    source = path.read_text()
    for match in re.finditer(r"(?m)^cat > [^\n]* <<'([^']+)'\n(.*?)^\1$", source, re.S | re.M):
        if match.group(2).startswith("#!/bin/sh"):
            subprocess.run(["sh", "-n"], input=match.group(2), text=True, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key", type=Path, required=True, help="local Ed25519 private PEM; never publish it")
    args = parser.parse_args()
    if not args.key.is_file():
        parser.error("signing key not found")

    provision = ROOT / "modules/provision/install.sh"
    public = subprocess.check_output(["openssl", "pkey", "-in", str(args.key), "-pubout"], text=True)
    if public.strip() not in provision.read_text():
        parser.error("signing key does not match the public key in the provisioner")

    for name in MODULES:
        path = ROOT / f"modules/{name}/install.sh"
        check_shell(path)
        (path.parent / "install.sh.sha256").write_text(f"{digest(path)}  install.sh\n")

    core = ROOT / "uci-defaults.sh"
    source = core.read_text()
    updated, count = re.subn(r"(?m)^HASH='(?:[0-9a-f]{64}|PROVISION_HASH_PLACEHOLDER)'$",
                             f"HASH='{digest(provision)}'", source)
    if count != 1:
        parser.error("expected one provisioner hash in uci-defaults.sh")
    core.write_text(updated)
    check_shell(core)
    if core.stat().st_size >= 40960:
        parser.error("uci-defaults.sh exceeds the 40960-byte firmware selector limit")

    manifest = ROOT / "release/manifest.txt"
    manifest.write_text("MX4200V2P2 1\n" + "".join(f"{digest(ROOT / name)} {name}\n" for name in RELEASE_FILES))
    signature = ROOT / "release/manifest.sig"
    subprocess.run(["openssl", "pkeyutl", "-sign", "-inkey", str(args.key), "-rawin",
                    "-in", str(manifest), "-out", str(signature)], check=True)
    with_public = ROOT / "release/.verify-public.pem"
    try:
        with_public.write_text(public)
        subprocess.run(["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", str(with_public),
                        "-rawin", "-in", str(manifest), "-sigfile", str(signature)],
                       check=True, stdout=subprocess.DEVNULL)
    finally:
        with_public.unlink(missing_ok=True)
    print(f"Signed release; core is {core.stat().st_size} bytes")


if __name__ == "__main__":
    main()
