# Windows 7 x64 compatibility status

## Purpose

This branch explores whether Craft Anything can be built and run on Windows 7 SP1 x64. The
Windows executable manifests declare Windows 7 and later compatibility identifiers, and the
GitHub Actions workflow produces an x64 build artifact for investigation.

## Important limitation

A Windows application manifest does **not** make newer Windows APIs, runtime components, or
graphics-driver features available on Windows 7. A successful build on a current Windows runner
only proves that the source compiled and linked there. It does not prove that the program starts
or works on Windows 7.

The current dependency stack includes a modern Rust toolchain and the eframe/winit/wgpu graphics
stack. Their Windows API and graphics-backend requirements must be checked against Windows 7
SP1. In particular, the GUI may fail to initialize if the required graphics backend or driver
is unavailable. The CLI and GUI must be tested separately.

## Build artifact

The `Windows 7 x64 compatibility build` workflow creates
`Craft-Anything-Windows7-x64.zip` containing:

- `craft-anything.exe`
- `craft-anything-cli.exe`
- `portable.txt`

The artifact is experimental and is not a declaration of confirmed Windows 7 support.

## Required runtime validation

Before calling this release Windows 7 compatible:

1. Test on a clean Windows 7 SP1 x64 installation with current applicable servicing updates.
2. Test the CLI startup and representative commands.
3. Test GUI startup, rendering, input, file dialogs, persistence, and shutdown.
4. Record missing DLLs, unsupported API entry points, and graphics initialization failures.
5. Repeat on more than one Windows 7 graphics-driver configuration where practical.

If runtime tests fail because of APIs or dependencies unavailable on Windows 7, the affected dependencies
or platform layer must be changed; changing the manifest alone is not a fix.
