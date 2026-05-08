const std = @import("std");
const l = @import("lightmix");

pub fn build(b: *std.Build) anyerror!void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const entries: []const struct { path: std.Build.LazyPath, name: []const u8 } = &.{
        .{ .path = b.path("src/piano-tone.zig"), .name = "piano-tone.wav" },
        .{ .path = b.path("src/organ-tone.zig"), .name = "organ-tone.wav" },
        .{ .path = b.path("src/brass-tone.zig"), .name = "brass-tone.wav" },
    };

    // Test step
    const test_step = b.step("test", "Run unit tests");
    for (entries) |entry| {
        const unit_tests = try install_modules(b, entry.path, entry.name, target, optimize);
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
}

fn install_modules(
    b: *std.Build,
    path: std.Build.LazyPath,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) anyerror!*std.Build.Step.Compile {
    // Resolve the lightmix dependency declared in build.zig.zon
    const lightmix = b.dependency("lightmix", .{});

    const mod = b.createModule(.{
        .root_source_file = path,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lightmix", .module = lightmix.module("lightmix") },
        },
    });

    // Link system audio libraries required by zaudio on Linux
    if (target.result.os.tag == .linux) {
        mod.linkSystemLibrary("alsa", .{});
        mod.linkSystemLibrary("libpulse", .{});
        mod.linkSystemLibrary("libpipewire-0.3", .{});
    }

    // Static library installation
    const lib = b.addLibrary(.{
        .name = name,
        .root_module = mod,
    });
    b.installArtifact(lib);

    // Wave installation
    const wave = try l.addWave(b, mod, .{
        .format = .{ .wav = .{
            .format_code = .pcm,
            .bits = 16,
            .name = name,
        } },
    });
    l.installWave(b, wave);

    // Unit tests
    const unit_tests = b.addTest(.{ .root_module = mod });

    return unit_tests;
}
