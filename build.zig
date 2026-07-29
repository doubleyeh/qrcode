const std = @import("std");
const native_sdk = @import("native_sdk");

pub fn build(b: *std.Build) void {
    const artifacts = native_sdk.addAppArtifacts(b, b.dependency("native_sdk", .{}), .{ .name = "qrcode", .app_root = "." });
    artifacts.exe.subsystem = .windows;
    artifacts.exe.root_module.addCSourceFile(.{ .file = b.path("src/hideconsole.c"), .flags = &.{} });
    b.installFile("assets/icon.ico", "bin/icon.ico");
    const loader = b.addInstallBinFile(b.path("_sdk/third_party/webview2/x64/WebView2Loader.dll"), "WebView2Loader.dll");
    b.getInstallStep().dependOn(&loader.step);
}
