"""Run cargo with this workspace's private Rust/NDK installation, or a system rustup.

Falls back to a system cargo when work/toolchains/cargo is absent, so the Rust unit
tests can run outside the private workspace instead of failing on a missing path.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
WORK = PROJECT.parent / 'work'
CARGO_HOME = WORK / 'toolchains/cargo'
NDK = WORK / 'android-sdk/ndk/23.2.8568313/toolchains/llvm/prebuilt/linux-x86_64/bin'

private = CARGO_HOME / 'bin/cargo'
system = shutil.which('cargo')

if private.is_file():
    cargo = private
    env = os.environ.copy()
    env.update(
        CARGO_HOME=str(CARGO_HOME),
        RUSTUP_HOME=str(WORK / 'toolchains/rustup'),
        CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=str(NDK / 'aarch64-linux-android29-clang'),
    )
    env['PATH'] = str(CARGO_HOME / 'bin') + ':' + env['PATH']
elif system:
    cargo = Path(system)
    env = os.environ.copy()
    linker = NDK / 'aarch64-linux-android29-clang'
    if linker.is_file():
        env.setdefault('CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER', str(linker))
    print(f'cargo.py: using system toolchain {cargo}', file=sys.stderr)
else:
    raise SystemExit(
        'cargo not found.\n'
        f'  private path : {private}  (absent)\n'
        '  system PATH  : no cargo\n'
        'Install a Rust toolchain with `rustup` and add the aarch64-linux-android target, '
        'or place it under work/toolchains/cargo. Android cross-builds additionally need '
        f'the NDK linker at {NDK}/aarch64-linux-android29-clang.\n'
        'Only the Android APK step needs the NDK; `cargo test` and host builds do not.'
    )

raise SystemExit(subprocess.call([str(cargo), *sys.argv[1:]], cwd=PROJECT, env=env))
