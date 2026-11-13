//! Windows only: embed the app icon, VERSIONINFO, and compatibility manifest into the executable.
//!
//! The manifest advertises the Windows versions the application is intended to support. It does
//! not make newer Windows APIs or graphics drivers available on Windows 7. A missing resource
//! compiler is a warning unless CRAFT_ANYTHING_REQUIRE_WINRES=1 turns it into an error.

const MANIFEST: &str = r#"<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{35138b9a-5d96-4fbd-8e2d-a2440225f93a}"/>
      <supportedOS Id="{4a2f28e3-53b9-4441-ba9c-d69d4a4a6e38}"/>
      <supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}"/>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
</assembly>"#;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=../../assets/app-icon/craft-anything.ico");
    println!("cargo:rerun-if-env-changed=CRAFT_ANYTHING_REQUIRE_WINRES");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }

    let mut res = winresource::WindowsResource::new();
    res.set_icon("../../assets/app-icon/craft-anything.ico")
        .set_manifest(MANIFEST)
        .set("ProductName", "Craft Anything")
        .set("FileDescription", "Craft Anything: find out how any software works")
        .set("LegalCopyright", "Copyright (c) the ArtCraft Team and the Craft Anything contributors. MIT OR Apache-2.0.")
        .set("OriginalFilename", "craft-anything.exe")
        .set("InternalName", "craft-anything");

    if let Err(e) = res.compile() {
        if std::env::var_os("CRAFT_ANYTHING_REQUIRE_WINRES").is_some() {
            println!("cargo::error=embedding Windows resources failed: {e}");
            return;
        }
        println!("cargo:warning=craft-anything.exe built without icon/version/manifest resources: {e}");
    }
}
