//! # Organ Timbre — Additive Synthesis (Hammond-style)
//!
//! Characteristic of a tonewheel organ (Hammond B-3):
//!   - "Drawbar" model: each partial has a fixed, adjustable amplitude
//!   - No amplitude envelope — organ tone is sustained at constant level
//!     while the key is held (modelled here as a soft on/off ramp only)
//!   - Harmonics present up to the 8th, with a specific drawbar mix
//!
//! Classic "full organ" drawbar setting: 88 8000 000
//!   Drawbar 1 (sub-fundamental, ×0.5):  amp 1.0
//!   Drawbar 2 (fundamental,      ×1  ):  amp 1.0
//!   Drawbar 3 (octave+fifth,     ×3  ):  amp 0.0  (off in this preset)
//!   Drawbar 4 (2nd octave,       ×4  ):  amp 0.0
//!   (Classic "jazz" preset used instead — see ORGAN_DRAWBARS below)
//!
//! Produces a C major chord (C4 + E4 + G4) lasting 2 seconds.

const std = @import("std");
const lightmix = @import("lightmix");
const Wave = lightmix.Wave;

const SAMPLE_RATE: u32 = 44100;
const SR_F: f64 = 44100.0;
const DURATION_S: f64 = 2.0;
const N_SAMPLES: usize = @intFromFloat(SR_F * DURATION_S);

/// Drawbar partial definition.
/// Each drawbar corresponds to a specific harmonic (or sub-harmonic) of
/// the fundamental, with amplitude set by the drawbar position (0–8).
const Drawbar = struct {
    /// Frequency multiplier relative to the fundamental
    ratio: f64,
    /// Drawbar position 0–8, normalised to 0.0–1.0
    amp: f64,
};

/// Jazz / gospel drawbar preset: 888000000
/// Sub-fundamental (×0.5) gives the characteristic "fat" low end.
/// Fundamental (×1) and octave (×2) carry the main tone.
/// 2⅔' (×3) adds a characteristic nasal colour.
const ORGAN_DRAWBARS = [_]Drawbar{
    .{ .ratio = 0.5, .amp = 1.0 }, // 16' — sub-fundamental
    .{ .ratio = 1.0, .amp = 1.0 }, //  8' — fundamental
    .{ .ratio = 2.0, .amp = 1.0 }, //  4' — octave
    .{ .ratio = 3.0, .amp = 0.6 }, // 2⅔'— twelfth (adds nasal colour)
    .{ .ratio = 4.0, .amp = 0.8 }, //  2' — second octave
    .{ .ratio = 5.0, .amp = 0.0 }, // 1⅗'— tierce (off)
    .{ .ratio = 6.0, .amp = 0.0 }, // 1⅓'— larigot (off)
    .{ .ratio = 8.0, .amp = 0.0 }, //  1' — piccolo (off)
};

/// Sum of all drawbar amplitudes (used for normalisation)
const DRAWBAR_SUM: f64 = blk: {
    var s: f64 = 0.0;
    for (ORGAN_DRAWBARS) |d| s += d.amp;
    break :blk s;
};

/// Organ envelope: soft 5 ms ramp-in / ramp-out, sustained at 1.0 in between.
/// Real organs have a slight "click" transient on key-on; omitted here.
fn envelope(t: f64) f64 {
    const RAMP: f64 = 0.005;
    if (t < RAMP) return t / RAMP;
    if (t > DURATION_S - RAMP) return (DURATION_S - t) / RAMP;
    return 1.0;
}

/// Synthesise one organ note at the given fundamental frequency.
fn organNote(freq: f64, allocator: std.mem.Allocator) !Wave(f64) {
    var buf: [N_SAMPLES]f64 = undefined;

    for (0..N_SAMPLES) |i| {
        const t: f64 = @as(f64, @floatFromInt(i)) / SR_F;
        const env: f64 = envelope(t);

        var sample: f64 = 0.0;
        for (ORGAN_DRAWBARS) |d| {
            sample += d.amp * @sin(2.0 * std.math.pi * freq * d.ratio * t);
        }
        buf[i] = sample / DRAWBAR_SUM * env * 0.22;
    }

    return try Wave(f64).init(&buf, allocator, .{
        .sample_rate = SAMPLE_RATE,
        .channels = 1,
    });
}

/// Returns a 2-second C major chord (C4 + E4 + G4) with organ timbre.
pub fn gen(allocator: std.mem.Allocator) !Wave(f64) {
    const silence = [_]f64{0.0} ** N_SAMPLES;
    var result = try Wave(f64).init(&silence, allocator, .{
        .sample_rate = SAMPLE_RATE,
        .channels = 1,
    });

    const frequencies = [_]f64{ 261.63, 329.63, 392.00 };
    for (frequencies) |freq| {
        const note = try organNote(freq, allocator);
        defer note.deinit();
        const mixed = try result.mix(note, .{});
        result.deinit();
        result = mixed;
    }

    return result;
}
