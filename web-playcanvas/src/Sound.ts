export class Sound {
  private ctx: AudioContext;

  constructor() {
    this.ctx = new AudioContext();
    // Resume on first user interaction
    const resume = () => {
      this.ctx.resume();
      window.removeEventListener("click", resume);
      window.removeEventListener("keydown", resume);
    };
    window.addEventListener("click", resume);
    window.addEventListener("keydown", resume);
  }

  shoot() {
    this.noise(0.08, 800, 200, 0.15);
  }

  shootSpecial() {
    this.noise(0.12, 1200, 300, 0.2);
  }

  hit(volume = 0.25) {
    this.noise(0.15, 200, 60, volume);
  }

  explosion() {
    const now = this.ctx.currentTime;

    // Low rumble layer
    const bass = this.ctx.createOscillator();
    const bassGain = this.ctx.createGain();
    bass.type = "square";
    bass.frequency.setValueAtTime(60 + Math.random() * 30, now);
    bass.frequency.exponentialRampToValueAtTime(18, now + 0.8);
    bassGain.gain.setValueAtTime(0.3, now);
    bassGain.gain.exponentialRampToValueAtTime(0.001, now + 0.8);
    bass.connect(bassGain).connect(this.ctx.destination);
    bass.start(now);
    bass.stop(now + 0.8);

    // Mid crackle layer with frequency jitter
    for (let i = 0; i < 3; i++) {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = "sawtooth";
      const startFreq = 100 + Math.random() * 200;
      osc.frequency.setValueAtTime(startFreq, now);
      const dropTime = 0.15 + Math.random() * 0.2;
      osc.frequency.exponentialRampToValueAtTime(20 + Math.random() * 30, now + dropTime);
      osc.frequency.setValueAtTime(60 + Math.random() * 80, now + dropTime);
      osc.frequency.exponentialRampToValueAtTime(15, now + 0.7);
      gain.gain.setValueAtTime(0.12, now + i * 0.03);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.5 + Math.random() * 0.3);
      osc.connect(gain).connect(this.ctx.destination);
      osc.start(now + i * 0.03);
      osc.stop(now + 0.8);
    }

    // High sizzle
    const hi = this.ctx.createOscillator();
    const hiGain = this.ctx.createGain();
    hi.type = "sawtooth";
    hi.frequency.setValueAtTime(300 + Math.random() * 200, now);
    hi.frequency.exponentialRampToValueAtTime(30, now + 0.25);
    hiGain.gain.setValueAtTime(0.15, now);
    hiGain.gain.exponentialRampToValueAtTime(0.001, now + 0.25);
    hi.connect(hiGain).connect(this.ctx.destination);
    hi.start(now);
    hi.stop(now + 0.25);
  }

  pickupRepair() {
    this.tone(0.12, 520, 780, 0.13);
    setTimeout(() => this.tone(0.14, 780, 1040, 0.13), 80);
  }

  pickupShield() {
    this.tone(0.18, 400, 1200, 0.1);
    setTimeout(() => this.tone(0.15, 900, 1400, 0.08), 50);
  }

  pickupDamage() {
    this.noise(0.1, 300, 100, 0.2);
    setTimeout(() => this.noise(0.06, 900, 400, 0.12), 40);
  }

  private noise(
    duration: number,
    freqStart: number,
    freqEnd: number,
    volume: number
  ) {
    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();

    osc.type = "sawtooth";
    osc.frequency.setValueAtTime(freqStart, now);
    osc.frequency.exponentialRampToValueAtTime(freqEnd, now + duration);

    gain.gain.setValueAtTime(volume, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + duration);

    osc.connect(gain).connect(this.ctx.destination);
    osc.start(now);
    osc.stop(now + duration);
  }

  private tone(
    duration: number,
    freqStart: number,
    freqEnd: number,
    volume: number
  ) {
    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();

    osc.type = "sine";
    osc.frequency.setValueAtTime(freqStart, now);
    osc.frequency.linearRampToValueAtTime(freqEnd, now + duration);

    gain.gain.setValueAtTime(volume, now);
    gain.gain.linearRampToValueAtTime(0, now + duration);

    osc.connect(gain).connect(this.ctx.destination);
    osc.start(now);
    osc.stop(now + duration);
  }
}
