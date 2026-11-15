# Windows 7 x64 compatibility status

## Test machine

The target machine reported:

- Dell Inspiron 3542
- Windows 7 Professional SP1, 64-bit
- Intel Celeron 2957U at 1.40 GHz
- 4 GB RAM

This branch is tailored to that OS and architecture. The CPU and memory profile also mean the
desktop app must avoid unnecessary renderer initialization and background overhead.

## Confirmed cause of the previous startup failure

The previous artifact was built on Windows Server 2022 using the ordinary
`x86_64-pc-windows-msvc` target and Rust 1.100.0. Building successfully on that runner did not
prove Windows 7 runtime compatibility.

The downloaded artifact's PE import tables were inspected directly. They contained:

- `api-ms-win-core-synch-l1-2-0.dll` and `WaitOnAddress`, `WakeByAddressSingle`,
  `WakeByAddressAll` imports. Microsoft documents these APIs as requiring Windows 8 or later.
- `bcryptprimitives.dll` and `ProcessPrng`. Microsoft documents `ProcessPrng` as requiring
  Windows 8 or later.
- `GetSystemTimePreciseAsFileTime`, another API newer than Windows 7.

These are executable import dependencies, not missing application data files. Copying arbitrary
DLLs beside the EXE is not a valid compatibility fix.

References:
- [Rust Windows target baseline change](https://blog.rust-lang.org/2024/02/26/Windows-7/)
- [Rust `*-win7-windows-msvc` target](https://doc.rust-lang.org/rustc/platform-support/win7-windows-msvc.html)
- [Microsoft `WaitOnAddress` requirements](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitonaddress)
- [Microsoft `ProcessPrng` requirements](https://learn.microsoft.com/en-us/windows/win32/seccng/processprng)
- [`getrandom` supported Windows targets](https://docs.rs/getrandom/latest/getrandom/)

## Build strategy on this branch

The Windows 7 workflow now targets `x86_64-win7-windows-msvc`, rather than the ordinary
Windows 10+ MSVC target. Rust currently classifies the Win7 target as Tier 3; it is not shipped as
a prebuilt rustup standard library. The workflow therefore installs `rust-src` and uses nightly
Cargo's `-Z build-std=std,panic_unwind` to compile the standard library for that target.

The `getrandom` documentation specifies `RtlGenRandom` for `*-win7-windows-*` targets, rather
than `ProcessPrng`. The import audit added to this branch checks that the old, known-incompatible
API-set and DLL imports do not return.

The application build script emits the private `craft_anything_win7` cfg only when the selected
target is exactly `x86_64-win7-windows-msvc`. This keeps the normal Windows renderer order
unchanged. The dedicated Win7 build starts with OpenGL and keeps Vulkan as a fallback; the normal
Windows build continues to use DX12 → WARP → Vulkan → OpenGL. On this legacy target, WARP is not
a useful fallback because this application's WARP path is a DX12 adapter.

## Static import gate

`scripts/audit-windows7-imports.ps1` checks both executables after linking. It fails the workflow
if either executable imports:

- `api-ms-win-core-synch-l1-2-0.dll`
- `bcryptprimitives.dll`
- `WaitOnAddress`, `WakeByAddressSingle`, or `WakeByAddressAll`
- `ProcessPrng`
- `GetSystemTimePreciseAsFileTime`

This is a targeted regression gate for the imports already found in the failing artifact. It is
not a complete proof that every function called dynamically by every dependency is supported by
Windows 7.

## What a successful CI run will and will not prove

A successful workflow will prove that the GUI and CLI compile for the dedicated Win7 target, and
that the listed incompatible imports are absent from both PE files. It will **not** by itself
prove that the GUI renders correctly with the Dell's installed Intel graphics driver.

Before declaring support, test on the actual Windows 7 SP1 x64 machine:

1. Start `craft-anything-cli.exe` and run `--version` and `doctor`.
2. Start `craft-anything.exe`; confirm that the window opens using OpenGL.
3. Check text rendering, resizing, mouse and keyboard input, file dialogs, settings persistence,
   and clean shutdown.
4. Attach `desktop.log` if GUI startup or rendering still fails.
5. Check the same portable ZIP on a clean Windows 7 SP1 x64 installation.

Until those tests pass, this remains an experimental Windows 7 build, not a verified Windows 7 release.
