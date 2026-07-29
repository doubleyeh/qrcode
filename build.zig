const std = @import("std");
const native_sdk = @import("native_sdk");

pub fn build(b: *std.Build) void {
    const artifacts = native_sdk.addAppArtifacts(b, b.dependency("native_sdk", .{}), .{ .name = "qrcode", .app_root = "." });
    artifacts.exe.subsystem = .windows;
    artifacts.exe.root_module.addCSourceFile(.{ .file = b.path("src/hideconsole.c"), .flags = &.{} });
    b.installFile("assets/icon.ico", "bin/icon.ico");
}
