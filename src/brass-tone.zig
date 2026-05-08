//! # Brass Timbre — Additive Synthesis
//!
//! Characteristic of a brass instrument (trumpet / horn):
//!   - Rich spectrum: both odd AND even harmonics present at significant levels
//!   - Upper harmonics are *stronger* relative to the fundamental than in piano
//!     (spectrum "brightens" during the attack and settles on sustain)
//!   - Envelope: slow-ish linear attack (≈ 80 ms), full sustain, quick release
//!   - Slight brightness shift: harmonic amplitudes peak around H3–H4
//!
//! Produces a C major chord (C4 + E4 + G4) lasting 2 seconds.

const std = @import("std");
const lightmix = @import("lightmix");
const Wave = lightmix.Wave;

const SAMPLE_RATE: u32 = 44100;
const SR_F: f64 = 44100.0;
const DURATION_S: f64 = 2.0;
const N_SAMPLES: usize = @intFromFloat(SR_F * DURATION_S);

const Partial = struct {
    ratio: f64,
    /// Sustained amplitude (after attack settles)
    amp_sustain: f64,
    /// Extra amplitude boost present only during the attack transient.
    /// Higher harmonics flare up more at the start — characteristic of brass.
    amp_attack_boost: f64,
};

/// Brass harmonic series.
/// Amplitudes peak around H3/H4, giving the characteristic "brassy" brightness.
/// The attack boost for upper partials models the spectral brightening on onset.
const BRASS_PARTIALS = [_]Partial{
    .{ .ratio = 1.0, .amp_sustain = 0.60, .amp_attack_boost = 0.10 },
    .{ .ratio = 2.0, .amp_sustain = 0.90, .amp_attack_boost = 0.20 },
    .{ .ratio = 3.0, .amp_sustain = 1.00, .amp_attack_boost = 0.40 }, // peak
    .{ .ratio = 4.0, .amp_sustain = 0.85, .amp_attack_boost = 0.60 },
    .{ .ratio = 5.0, .amp_sustain = 0.65, .amp_attack_boost = 0.70 },
    .{ .ratio = 6.0, .amp_sustain = 0.45, .amp_attack_boost = 0.60 },
    .{ .ratio = 7.0, .amp_sustain = 0.28, .amp_attack_boost = 0.45 },
    .{ .ratio = 8.0, .amp_sustain = 0.14, .amp_attack_boost = 0.30 },
    .{ .ratio = 9.0, .amp_sustain = 0.06, .amp_attack_boost = 0.15 },
};

/// Sum of peak (sustain + boost) amplitudes used for normalisation.
const BRASS_PEAK_SUM: f64 = blk: {
    var s: f64 = 0.0;
    for (BRASS_PARTIALS) |p| s += p.amp_sustain + p.amp_attack_boost;
    break :blk s;
};

/// Brass amplitude envelope.
/// The attack shape (0→1) drives the spectral brightening factor below.
const ATTACK_S: f64 = 0.08;
const RELEASE_S: f64 = 0.04;

fn attackFactor(t: f64) f64 {
    if (t < ATTACK_S) return t / ATTACK_S; // 0.0 → 1.0 during attack
    return 1.0;
}

fn overallEnvelope(t: f64) f64 {
    if (t < ATTACK_S) return t / ATTACK_S;
    if (t > DURATION_S - RELEASE_S) return (DURATION_S - t) / RELEASE_S;
    return 1.0;
}

/// Synthesise one brass note at the given fundamental frequency.
fn brassNote(freq: f64, allocator: std.mem.Allocator) !Wave(f64) {
    var buf: [N_SAMPLES]f64 = undefined;

    for (0..N_SAMPLES) |i| {
        const t: f64 = @as(f64, @floatFromInt(i)) / SR_F;
        const env: f64 = overallEnvelope(t);
        const atk: f64 = 1.0 - attackFactor(t); // 1.0 at onset, fades to 0.0

        var sample: f64 = 0.0;
        for (BRASS_PARTIALS) |p| {
            // Upper harmonics are boosted during attack, then settle to sustain level
            const effective_amp = p.amp_sustain + p.amp_attack_boost * atk;
            sample += effective_amp * @sin(2.0 * std.math.pi * freq * p.ratio * t);
        }
        buf[i] = sample / BRASS_PEAK_SUM * env * 0.22;
    }

    return try Wave(f64).init(&buf, allocator, .{
        .sample_rate = SAMPLE_RATE,
        .channels = 1,
    });
}

/// Returns a 2-second C major chord (C4 + E4 + G4) with brass timbre.
pub fn gen(allocator: std.mem.Allocator) !Wave(f64) {
    const silence = [_]f64{0.0} ** N_SAMPLES;
    var result = try Wave(f64).init(&silence, allocator, .{
        .sample_rate = SAMPLE_RATE,
        .channels = 1,
    });

    const frequencies = [_]f64{ 261.63, 329.63, 392.00 };
    for (frequencies) |freq| {
        const note = try brassNote(freq, allocator);
        defer note.deinit();
        const mixed = try result.mix(note, .{});
        result.deinit();
        result = mixed;
    }

    return result;
}
