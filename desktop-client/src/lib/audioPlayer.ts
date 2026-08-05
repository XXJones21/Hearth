/*
 * Streaming PCM playback for Valar TTS. The gateway sends tts_chunk_start
 * {seg_idx, sample_rate, text}, then raw binary frames of FLOAT32 LE mono
 * samples in [-1, 1] (see Valar/valar/voice/tts.py: "<f4" -- it was int16
 * once, changed long ago; decoding as int16 produces loud static at half
 * speed), then tts_chunk_end -- multiple segments per turn,
 * speaking_complete at the end. Frames are scheduled gaplessly on one
 * AudioContext timeline.
 */

class PcmStreamPlayer {
  private ctx: AudioContext | null = null;
  private gain: GainNode | null = null;
  private nextTime = 0;
  private sampleRate = 24000;
  private smoothedRms = 0;
  private lastPushAt = 0;
  /** Settings > Voice. Muting stops the sound, not the stream: the speaking
      waveform still tracks the reply because level() reads the PCM, not the
      output. */
  private volume = 1;
  private muted = false;
  framesPlayed = 0;

  setOutput(enabled: boolean, volume: number): void {
    this.muted = !enabled;
    this.volume = Math.max(0, Math.min(1, volume));
    if (this.gain) this.gain.gain.value = this.muted ? 0 : this.volume;
  }

  private ensureContext(): AudioContext | null {
    if (typeof AudioContext === 'undefined') return null;
    if (!this.ctx) {
      this.ctx = new AudioContext();
      this.gain = this.ctx.createGain();
      this.gain.gain.value = this.muted ? 0 : this.volume;
      this.gain.connect(this.ctx.destination);
    }
    if (this.ctx.state === 'suspended') {
      // Autoplay policy: resume needs a gesture; typing the message counts,
      // so this succeeds in practice. A later gesture retries via push().
      void this.ctx.resume();
    }
    return this.ctx;
  }

  /** Called on tts_chunk_start. */
  begin(sampleRate: number): void {
    if (Number.isFinite(sampleRate) && sampleRate > 0) this.sampleRate = sampleRate;
    const ctx = this.ensureContext();
    if (ctx) this.nextTime = Math.max(ctx.currentTime, this.nextTime);
  }

  /** Called for each binary float32 PCM frame. */
  push(buf: ArrayBuffer): void {
    const ctx = this.ensureContext();
    if (!ctx) return;
    const aligned = buf.byteLength - (buf.byteLength % 4);
    if (aligned <= 0) return;
    const f32 = new Float32Array(buf, 0, aligned / 4);
    let sum = 0;
    for (let i = 0; i < f32.length; i++) sum += f32[i] * f32[i];
    const rms = Math.sqrt(sum / Math.max(1, f32.length));
    this.smoothedRms = 0.7 * this.smoothedRms + 0.3 * Math.min(1, rms * 4);
    this.lastPushAt = performance.now();
    const audio = ctx.createBuffer(1, f32.length, this.sampleRate);
    audio.getChannelData(0).set(f32);
    const src = ctx.createBufferSource();
    src.buffer = audio;
    src.connect(this.gain ?? ctx.destination);
    const t = Math.max(ctx.currentTime + 0.02, this.nextTime);
    src.start(t);
    this.nextTime = t + audio.duration;
    this.framesPlayed += 1;
  }

  /** Play one complete wav and resolve when it finishes (Personas > Hear it).
   *
   * Goes through the SAME AudioContext as the streaming path rather than an
   * <audio> element: the element's play() is gated by the autoplay policy and
   * an await between the click and the call loses the gesture, which is why
   * the first version made no sound at all. Reusing the context also means
   * Settings > Voice governs the preview like everything else.
   *
   * The level meter is driven off the decoded samples so the orb moves with
   * the preview -- the streaming path gets that for free from push(). */
  async playClip(data: ArrayBuffer): Promise<void> {
    const ctx = this.ensureContext();
    if (!ctx) throw new Error('this client has no audio output');
    const buffer = await ctx.decodeAudioData(data);
    const src = ctx.createBufferSource();
    src.buffer = buffer;
    src.connect(this.gain ?? ctx.destination);
    const pcm = buffer.getChannelData(0);
    const startedAt = ctx.currentTime;
    const meter = setInterval(() => {
      const at = Math.floor((ctx.currentTime - startedAt) * buffer.sampleRate);
      const end = Math.min(pcm.length, at + 1024);
      let sum = 0;
      for (let i = Math.max(0, at); i < end; i++) sum += pcm[i] * pcm[i];
      const rms = Math.sqrt(sum / Math.max(1, end - Math.max(0, at)));
      this.smoothedRms = 0.7 * this.smoothedRms + 0.3 * Math.min(1, rms * 4);
      this.lastPushAt = performance.now();
    }, 60);
    try {
      await new Promise<void>((resolve) => {
        src.onended = () => resolve();
        src.start();
      });
    } finally {
      clearInterval(meter);
      this.smoothedRms = 0;
    }
  }

  /** Smoothed speech amplitude 0..1 -- drives the speaking waveform. */
  level(): number {
    const age = (performance.now() - this.lastPushAt) / 1000;
    if (age > 1.2) return 0;
    return this.smoothedRms * Math.max(0, 1 - age * 0.6);
  }

  /** Drop anything scheduled ahead (turn cancelled / connection lost). */
  reset(): void {
    if (this.ctx) {
      void this.ctx.close().catch(() => undefined);
      this.ctx = null;
      this.gain = null;
    }
    this.nextTime = 0;
  }
}

export const ttsPlayer = new PcmStreamPlayer();

if (import.meta.env.DEV && typeof window !== 'undefined') {
  (window as unknown as Record<string, unknown>).__hearthAudio = ttsPlayer;
}
