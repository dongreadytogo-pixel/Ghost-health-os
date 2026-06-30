/**
 * Audio — lightweight, original sound.
 *
 * SFX are synthesized on the fly with the Web Audio API (no asset files, no
 * licensing). Background music is intentionally left as a slot for the project
 * owner's own licensed tracks: drop a file in and call `setMusic(url)`.
 * Browsers block audio until a user gesture, so everything is unlocked on the
 * first tap/click.
 */

let ctx: AudioContext | undefined;
let muted = false;
let unlocked = false;
const bgm = new Audio();
bgm.loop = true;
bgm.volume = 0.5;
let musicUrl: string | undefined;

function ac(): AudioContext | undefined {
  if (muted) return undefined;
  if (!ctx) {
    const Ctor =
      window.AudioContext ??
      (window as unknown as { webkitAudioContext?: typeof AudioContext })
        .webkitAudioContext;
    if (!Ctor) return undefined;
    ctx = new Ctor();
  }
  return ctx;
}

function blip(freq: number, durMs: number, type: OscillatorType, gain = 0.05): void {
  const a = ac();
  if (!a) return;
  const osc = a.createOscillator();
  const g = a.createGain();
  osc.type = type;
  osc.frequency.value = freq;
  g.gain.value = gain;
  g.gain.exponentialRampToValueAtTime(0.0001, a.currentTime + durMs / 1000);
  osc.connect(g).connect(a.destination);
  osc.start();
  osc.stop(a.currentTime + durMs / 1000);
}

function arp(freqs: number[], stepMs: number, type: OscillatorType = 'square'): void {
  freqs.forEach((f, i) => setTimeout(() => blip(f, stepMs * 1.4, type, 0.06), i * stepMs));
}

export const sfx = {
  hit: () => blip(220, 70, 'triangle', 0.03),
  crit: () => blip(560, 120, 'square', 0.05),
  levelUp: () => arp([523, 659, 784, 1047], 70),
  capture: () => arp([784, 988, 1319], 60, 'triangle'),
  fusion: () => arp([392, 523, 659, 880, 1175], 60),
  defeat: () => blip(110, 300, 'sawtooth', 0.05),
  equip: () => blip(880, 90, 'square', 0.04),
};

export function setMuted(value: boolean): void {
  muted = value;
  bgm.muted = value;
  if (value) {
    void ctx?.suspend();
  } else {
    void ctx?.resume();
    if (unlocked && musicUrl && bgm.paused) void bgm.play().catch(() => {});
  }
}

export const isMuted = (): boolean => muted;

/** Provide the owner's licensed background track. */
export function setMusic(url: string): void {
  musicUrl = url;
  bgm.src = url;
  if (unlocked && !muted) void bgm.play().catch(() => {});
}

/** Call once from a user gesture to satisfy browser autoplay policies. */
export function unlockAudio(): void {
  if (unlocked) return;
  unlocked = true;
  void ac()?.resume();
  if (musicUrl && !muted) void bgm.play().catch(() => {});
}
