//! # Piano Timbre — Additive Synthesis
//!
//! Characteristic of a piano tone:
//!   - Harmonic amplitudes roll off roughly as 1/n (bright but diminishing)
//!   - Slight inharmonicity: upper partials are stretched slightly sharp
//!   - Fast linear attack (≈ 8 ms) followed by a long exponential decay
//!
//! Produces a C major chord (C4 + E4 + G4) lasting 2 seconds.

const std = @import("std");
const lightmix = @import("lightmix");
const Wave = lightmix.Wave;

const SAMPLE_RATE: u32 = 44100;
const SR_F: f64 = 44100.0;
const DURATION_S: f64 = 2.0;
const N_SAMPLES: usize = @intFromFloat(SR_F * DURATION_S);

// Harmonic partial definition
const Partial = struct {
    /// Frequency multiplier relative to the fundamental (1.0 = fundamental)
    ratio: f64,
    /// Relative amplitude of this partial
    amp: f64,
};

/// Harmonic series for a piano note.
/// Ratios are slightly stretched above 1 to mimic inharmonicity
/// (real piano strings are stiff; upper partials go slightly sharp).
const PIANO_PARTIALS = [_]Partial{
    .{ .ratio = 1.000, .amp = 1.000 },
    .{ .ratio = 2.001, .amp = 0.500 },
    .{ .ratio = 3.003, .amp = 0.260 },
    .{ .ratio = 4.007, .amp = 0.140 },
    .{ .ratio = 5.013, .amp = 0.075 },
    .{ .ratio = 6.021, .amp = 0.040 },
    .{ .ratio = 7.031, .amp = 0.020 },
};

/// Piano amplitude envelope:
///   - Linear attack over ATTACK_S seconds
///   - Exponential decay for the remainder
fn envelope(t: f64) f64 {
    const ATTACK_S: f64 = 0.008;
    if (t < ATTACK_S) return t / ATTACK_S;
    // Tuned so that the signal decays to ~10 % at the end of DURATION_S
    return @exp(-2.5 * (t - ATTACK_S) / (DURATION_S - ATTACK_S));
}

/// Synthesise one piano note at the given fundamental frequency.
fn pianoNote(freq: f64, allocator: std.mem.Allocator) !Wave(f64) {
    var buf: [N_SAMPLES]f64 = undefined;

    for (0..N_SAMPLES) |i| {
        const t: f64 = @as(f64, @floatFromInt(i)) / SR_F;
        const env: f64 = envelope(t);

        var sample: f64 = 0.0;
        for (PIANO_PARTIALS) |p| {
            sample += p.amp * @sin(2.0 * std.math.pi * freq * p.ratio * t);
        }
        // Normalise partial sum then apply envelope and per-note gain
        buf[i] = sample / 2.035 * env * 0.22;
    }

    return try Wave(f64).init(&buf, allocator, .{
        .sample_rate = SAMPLE_RATE,
        .channels = 1,
    });
}

/// Returns a 2-second C major chord (C4 + E4 + G4) with piano timbre.
pub fn gen(allocator: std.mem.Allocator) !Wave(f64) {
    // Silence baseline
    const silence = [_]f64{0.0} ** N_SAMPLES;
    var result = try Wave(f64).init(&silence, allocator, .{
        .sample_rate = SAMPLE_RATE,
        .channels = 1,
    });

    // C major chord: C4, E4, G4
    const frequencies = [_]f64{ 261.63, 329.63, 392.00 };
    for (frequencies) |freq| {
        const note = try pianoNote(freq, allocator);
        defer note.deinit();
        const mixed = try result.mix(note, .{});
        result.deinit();
        result = mixed;
    }

    return result;
}
