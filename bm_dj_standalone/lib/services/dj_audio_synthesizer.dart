import 'dart:math' as math;
import 'dart:typed_data';

/// Real-time pure-Dart synthesizer for classic DJ sound effects and sampler pads.
/// Generates zero-latency in-memory PCM 44.1kHz 16-bit WAV audio files.
class DJAudioSynthesizer {
  static final Map<String, Uint8List> _cache = {};

  /// Generate PCM 16-bit Mono WAV byte array from floating-point samples [-1.0, 1.0]
  static Uint8List createWav(List<double> samples, {int sampleRate = 44100}) {
    final int numSamples = samples.length;
    final int byteRate = sampleRate * 2; // 16-bit mono
    final ByteData byteData = ByteData(44 + numSamples * 2);

    // RIFF chunk descriptor
    byteData.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    byteData.setUint32(4, 36 + numSamples * 2, Endian.little);
    byteData.setUint32(8, 0x57415645, Endian.big); // "WAVE"

    // "fmt " sub-chunk
    byteData.setUint32(12, 0x666D7420, Endian.big); // "fmt "
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    byteData.setUint16(22, 1, Endian.little); // NumChannels (1 = Mono)
    byteData.setUint32(24, sampleRate, Endian.little); // SampleRate
    byteData.setUint32(28, byteRate, Endian.little); // ByteRate
    byteData.setUint16(32, 2, Endian.little); // BlockAlign
    byteData.setUint16(34, 16, Endian.little); // BitsPerSample

    // "data" sub-chunk
    byteData.setUint32(36, 0x64617461, Endian.big); // "data"
    byteData.setUint32(40, numSamples * 2, Endian.little);

    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      final double s = samples[i].clamp(-1.0, 1.0);
      final int intSample = (s * 32767).toInt();
      byteData.setInt16(offset, intSample, Endian.little);
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }

  /// Classic Reggae / Dancehall Airhorn blast (3-note fanfare with staccato blast pattern)
  static Uint8List getAirhorn() {
    if (_cache.containsKey('airhorn')) return _cache['airhorn']!;

    const int sampleRate = 44100;
    const double totalDuration = 1.25;
    final int totalSamples = (totalDuration * sampleRate).toInt();
    final List<double> samples = List.filled(totalSamples, 0.0);

    // Multi-tone chord frequencies: D5, F#5, A5
    const double f1 = 587.33;
    const double f2 = 739.99;
    const double f3 = 880.00;
    const double f4 = 1174.66; // Octave

    // 4 staccato bursts: [start, duration] in seconds
    final bursts = [
      [0.0, 0.12],
      [0.16, 0.12],
      [0.32, 0.12],
      [0.48, 0.70], // Long final sustain
    ];

    for (final burst in bursts) {
      final double bStart = burst[0];
      final double bDur = burst[1];
      final int startSample = (bStart * sampleRate).toInt();
      final int endSample = math.min(((bStart + bDur) * sampleRate).toInt(), totalSamples);

      for (int i = startSample; i < endSample; i++) {
        final double t = (i - startSample) / sampleRate;
        final double progress = t / bDur;

        // Envelope: fast attack, slight decay
        double env = 1.0;
        if (progress < 0.08) {
          env = progress / 0.08;
        } else if (progress > 0.85) {
          env = (1.0 - progress) / 0.15;
        }

        // Slight brass distortion via soft clipping of harmonic square/saw mix
        final double wave = 0.35 * math.sin(2 * math.pi * f1 * t) +
            0.30 * math.sin(2 * math.pi * f2 * t) +
            0.25 * math.sin(2 * math.pi * f3 * t) +
            0.20 * math.sin(2 * math.pi * f4 * t) +
            0.15 * (math.sin(2 * math.pi * f1 * 2 * t) > 0 ? 0.3 : -0.3);

        samples[i] = (wave * env).clamp(-1.0, 1.0);
      }
    }

    final result = createWav(samples);
    _cache['airhorn'] = result;
    return result;
  }

  /// Sweeping DJ Dub Alarm / Siren (two-tone pitch-modulated alarm)
  static Uint8List getSiren() {
    if (_cache.containsKey('siren')) return _cache['siren']!;

    const int sampleRate = 44100;
    const double totalDuration = 1.5;
    final int totalSamples = (totalDuration * sampleRate).toInt();
    final List<double> samples = List.filled(totalSamples, 0.0);

    double phase = 0.0;
    for (int i = 0; i < totalSamples; i++) {
      final double t = i / sampleRate;
      // 3.5 Hz LFO frequency sweep between 550Hz and 1100Hz
      final double lfo = 0.5 + 0.5 * math.sin(2 * math.pi * 3.5 * t);
      final double freq = 550.0 + lfo * 550.0;

      phase += 2 * math.pi * freq / sampleRate;
      final double wave = math.sin(phase);

      // Fade out at end
      double env = 1.0;
      if (t > 1.2) {
        env = (1.5 - t) / 0.3;
      }
      samples[i] = (wave * env * 0.75).clamp(-1.0, 1.0);
    }

    final result = createWav(samples);
    _cache['siren'] = result;
    return result;
  }

  /// DJ Vinyl Backspin / Scratch sound burst
  static Uint8List getScratch() {
    if (_cache.containsKey('scratch')) return _cache['scratch']!;

    const int sampleRate = 44100;
    const double totalDuration = 0.45;
    final int totalSamples = (totalDuration * sampleRate).toInt();
    final List<double> samples = List.filled(totalSamples, 0.0);

    final random = math.Random(42);
    double phase = 0.0;

    for (int i = 0; i < totalSamples; i++) {
      final double t = i / sampleRate;
      final double progress = t / totalDuration;

      // Frequency drops and oscillates like a turntable scratch gesture
      final double scratchFreq = 1200.0 * math.sin(progress * math.pi * 3.0).abs() + 200.0;
      phase += 2 * math.pi * scratchFreq / sampleRate;

      // Mix tone with vinyl surface friction noise
      final double noise = (random.nextDouble() * 2.0 - 1.0) * 0.45;
      final double tone = math.sin(phase) * 0.55;

      // Envelope
      final double env = math.sin(progress * math.pi);
      samples[i] = ((tone + noise) * env * 0.85).clamp(-1.0, 1.0);
    }

    final result = createWav(samples);
    _cache['scratch'] = result;
    return result;
  }

  /// Laser Zap / Bass Drop impact
  static Uint8List getLaserDrop() {
    if (_cache.containsKey('laser')) return _cache['laser']!;

    const int sampleRate = 44100;
    const double totalDuration = 0.85;
    final int totalSamples = (totalDuration * sampleRate).toInt();
    final List<double> samples = List.filled(totalSamples, 0.0);

    double phase = 0.0;
    for (int i = 0; i < totalSamples; i++) {
      final double t = i / sampleRate;
      final double progress = t / totalDuration;

      // Rapid exponential drop from 2400Hz down to 55Hz (sub-bass)
      final double freq = 2400.0 * math.exp(-6.5 * progress) + 55.0;
      phase += 2 * math.pi * freq / sampleRate;

      // Envelope: punchy front attack with sub-bass tail
      final double env = math.exp(-2.5 * progress);
      final double wave = math.sin(phase) * 0.85;

      samples[i] = (wave * env).clamp(-1.0, 1.0);
    }

    final result = createWav(samples);
    _cache['laser'] = result;
    return result;
  }
}
