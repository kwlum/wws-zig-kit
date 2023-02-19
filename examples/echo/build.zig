const std = @import("std");

pub fn build(b: *std.build.Builder) void {    
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("echo", "src/main.zig");
    exe.setTarget(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });
    exe.setBuildMode(mode);
    exe.addPackagePath("wws-zig-kit", "../../src/main.zig");    
    exe.linkLibC();    
    exe.install();

    b.getInstallStep().dependOn(&b.addInstallFileWithDir(.{ .path = "./zig-out/bin/echo.wasm" }, .prefix, "../www/echo.wasm").step);    
}
