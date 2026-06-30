/**
 * Pixel sprite renderer — blits frames from a real, good-looking CC0 spritesheet:
 * "DungeonTileset II" by 0x72 (https://0x72.itch.io/dungeontileset-ii, CC0 1.0).
 * See ATTRIBUTIONS in the repo. Frames are the documented idle animations; we
 * cycle them for a lively, professional look.
 *
 * To use a different pack, swap the PNG + the FRAMES table — nothing else
 * changes. Content stays data-driven; archetype names map view → engine.
 */

declare global {
  interface Window {
    /** Optional inlined atlas (data URI) for self-contained single-file builds. */
    __ATLAS__?: string;
  }
}

const ATLAS_URL =
  typeof window !== 'undefined' && window.__ATLAS__
    ? window.__ATLAS__
    : './assets/0x72_dungeon.png';

interface Frame {
  readonly x: number;
  readonly y: number;
  readonly w: number;
  readonly h: number;
  readonly n: number; // animation frame count (laid out horizontally)
}

/** Idle-animation frames from DungeonTileset II v1.3. */
const FRAMES: Record<string, Frame> = {
  knight: { x: 128, y: 106, w: 16, h: 22, n: 4 }, // hero
  elf: { x: 128, y: 42, w: 16, h: 22, n: 4 },
  swampy: { x: 432, y: 112, w: 16, h: 16, n: 4 }, // green slime blob
  muddy: { x: 368, y: 112, w: 16, h: 16, n: 4 },
  goblin: { x: 368, y: 37, w: 16, h: 11, n: 4 },
  imp: { x: 368, y: 48, w: 16, h: 16, n: 4 },
  skelet: { x: 368, y: 80, w: 16, h: 16, n: 4 },
  zombie: { x: 368, y: 144, w: 16, h: 16, n: 4 },
  orc: { x: 368, y: 204, w: 16, h: 20, n: 4 },
  chort: { x: 368, y: 328, w: 16, h: 24, n: 4 },
  big_demon: { x: 16, y: 364, w: 32, h: 36, n: 4 }, // boss
};

/** Static tiles (1 frame) for the dungeon backdrop and the hero's weapon. */
const TILES = {
  floor1: { x: 16, y: 64, w: 16, h: 16 },
  floor2: { x: 32, y: 64, w: 16, h: 16 },
  wallMid: { x: 32, y: 16, w: 16, h: 16 },
  wallTop: { x: 32, y: 0, w: 16, h: 16 },
  banner: { x: 16, y: 32, w: 16, h: 16 }, // red banner
  sword: { x: 339, y: 120, w: 10, h: 23 }, // weapon_knight_sword
};

const FIGHTER_SCALE = 3;

let atlas: HTMLImageElement | undefined;
let ready = false;

export function loadAtlas(): Promise<void> {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      atlas = img;
      ready = true;
      resolve();
    };
    img.onerror = () => resolve(); // fail soft: bars/text still work
    img.src = ATLAS_URL;
  });
}

export const isAtlasReady = (): boolean => ready;

/** Map a content name to an atlas archetype. */
export function artForName(name: string): string {
  if (name.includes('Crawler')) return 'swampy';
  if (name.includes('Stalker')) return 'goblin';
  if (name.includes('Dummy')) return 'skelet';
  if (name.includes('King') || name.includes('Demon')) return 'big_demon';
  return 'imp';
}

function blit(
  ctx: CanvasRenderingContext2D,
  art: string,
  frameIndex: number,
  scale: number,
  canvasW: number,
  canvasH: number,
): void {
  if (!atlas) return;
  const f = FRAMES[art] ?? FRAMES.imp!;
  const fi = ((frameIndex % f.n) + f.n) % f.n;
  const sx = f.x + fi * f.w;
  const dw = f.w * scale;
  const dh = f.h * scale;
  const dx = Math.round((canvasW - dw) / 2);
  const dy = canvasH - dh; // feet on the ground
  ctx.imageSmoothingEnabled = false;
  ctx.clearRect(0, 0, canvasW, canvasH);
  ctx.drawImage(atlas, sx, f.y, f.w, f.h, dx, dy, dw, dh);
}

/** Draw an animated fighter (hero or monster) into a target canvas. */
export function drawFighter(
  target: HTMLCanvasElement,
  art: string,
  frameIndex: number,
): void {
  const ctx = target.getContext('2d');
  if (!ctx) return;
  blit(ctx, art, frameIndex, FIGHTER_SCALE, target.width, target.height);

  // Give the hero a sword in hand.
  if (art === 'knight' && atlas) {
    const f = FRAMES.knight!;
    const dw = f.w * FIGHTER_SCALE;
    const dh = f.h * FIGHTER_SCALE;
    const hx = Math.round((target.width - dw) / 2);
    const hy = target.height - dh;
    const s = TILES.sword;
    const bob = (frameIndex % f.n) === 1 || (frameIndex % f.n) === 2 ? 1 : 0;
    ctx.drawImage(
      atlas,
      s.x, s.y, s.w, s.h,
      hx + dw - s.w * 2, hy + dh - s.h * 2 - bob, s.w * 2, s.h * 2,
    );
  }
}

/** Paint the tiled dungeon backdrop (floor + wall row) into a target canvas. */
export function drawBackground(target: HTMLCanvasElement): void {
  if (!atlas) return;
  const ctx = target.getContext('2d');
  if (!ctx) return;
  ctx.imageSmoothingEnabled = false;
  const S = 32; // 16px tile at 2x
  const cols = Math.ceil(target.width / S);
  const rows = Math.ceil(target.height / S);
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      let t = (c + r) % 2 ? TILES.floor2 : TILES.floor1;
      if (r === 0) t = TILES.wallTop;
      else if (r === 1) t = c % 5 === 2 ? TILES.banner : TILES.wallMid;
      ctx.drawImage(atlas, t.x, t.y, t.w, t.h, c * S, r * S, S, S);
    }
  }
}

/** A small static chip sprite (frame 0) for party/roster lists. */
export function drawChip(art: string): HTMLCanvasElement {
  const cv = document.createElement('canvas');
  cv.width = 20;
  cv.height = 22;
  const ctx = cv.getContext('2d');
  if (ctx) blit(ctx, art, 0, 1, cv.width, cv.height);
  return cv;
}
