class SoundSystem {
  private ctx: AudioContext | null = null;

  private init() {
    if (!this.ctx) {
      this.ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
    }
  }

  private playTone(freq: number, type: OscillatorType = 'sine', duration: number = 0.3, volume: number = 0.1) {
    this.init();
    if (!this.ctx) return;

    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();

    osc.type = type;
    osc.frequency.setValueAtTime(freq, this.ctx.currentTime);

    gain.gain.setValueAtTime(volume, this.ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.0001, this.ctx.currentTime + duration);

    osc.connect(gain);
    gain.connect(this.ctx.destination);

    osc.start();
    osc.stop(this.ctx.currentTime + duration);
  }

  public stepComplete() {
    this.playTone(523.25, 'sine', 0.3); // C5
    setTimeout(() => this.playTone(659.25, 'sine', 0.3), 100); // E5
  }

  public gatePass() {
    this.playTone(523.25, 'sine', 0.2); // C5
    setTimeout(() => this.playTone(783.99, 'sine', 0.2), 100); // G5
  }

  public gateFail() {
    this.playTone(130.81, 'triangle', 0.4, 0.2); // C3
  }

  public notification() {
    this.playTone(440, 'sine', 0.5, 0.1); // A4
  }
}

export const sounds = new SoundSystem();
