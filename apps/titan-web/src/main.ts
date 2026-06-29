/**
 * Project Titan — playable web client.
 *
 * A thin presentation layer over @titan/engine: it builds a World, runs the
 * deterministic idle loop in real time, renders the fight with simple
 * pixel/emoji sprites (drop-in points for real spritesheets later), computes
 * offline progress on load, and autosaves to localStorage. No game logic lives
 * here — everything authoritative is in the engine.
 */

import {
  ContentRegistry,
  STARTER_CONTENT,
  STARTER_MOUNTS,
  STARTER_SKILLS,
  World,
  Rng,
  simulateOffline,
  makeMountInstance,
  rollSkillInstance,
  expToNext,
  asZoneDefId,
  unwrap,
  ZERO_ATTRIBUTES,
  DEFAULT_WORLD_CONFIG,
  type WorldEvent,
  type WorldSave,
  type Companion,
  type Rarity,
} from '@titan/engine';

// ---------------------------------------------------------------------------
// Content & configuration
// ---------------------------------------------------------------------------

const registry = new ContentRegistry().register(STARTER_CONTENT);
const ZONE = unwrap(registry.zone(asZoneDefId('verdant_fringe')));

const CONFIG = {
  ...DEFAULT_WORLD_CONFIG,
  capture: { ...DEFAULT_WORLD_CONFIG.capture, baseChance: 0.16, skillPool: STARTER_SKILLS },
};

const SAVE_KEY = 'titan-save-v1';
const TICK_MS = 90; // ~11 ticks/sec while watching
const AUTOSAVE_MS = 5000;

/** Placeholder sprites — replace the emoji with <img> spritesheets later. */
const MONSTER_SPRITES: Record<string, string> = {
  'Meadow Crawler': '🐛',
  'Thicket Stalker': '🐺',
};
const spriteFor = (name: string): string => {
  for (const key of Object.keys(MONSTER_SPRITES)) {
    if (name.includes(key)) return MONSTER_SPRITES[key]!;
  }
  return '👾';
};

// ---------------------------------------------------------------------------
// DOM helpers
// ---------------------------------------------------------------------------

const $ = (id: string): HTMLElement => {
  const el = document.getElementById(id);
  if (!el) throw new Error(`missing #${id}`);
  return el;
};

const setBar = (el: HTMLElement, ratio: number): void => {
  el.style.transform = `scaleX(${Math.max(0, Math.min(1, ratio))})`;
};

const rarityClass = (r: Rarity): string => `r-${r}`;

// ---------------------------------------------------------------------------
// World construction / persistence
// ---------------------------------------------------------------------------

interface StoredSave {
  readonly save: WorldSave;
  readonly savedAt: number;
}

function freshWorld(): World {
  const seed = `titan-${Date.now()}-${Math.floor(Math.random() * 1e9)}`;
  const rng = Rng.fromString(seed);
  return new World(
    registry,
    ZONE,
    rng,
    {
      allocated: {
        ...ZERO_ATTRIBUTES,
        strength: 10,
        agility: 8,
        vitality: 10,
        dexterity: 8,
        luck: 5,
      },
      equipment: {},
      mount: makeMountInstance(STARTER_MOUNTS[0]!, 'common', false),
    },
    CONFIG,
    { level: 1, currentExp: 0 },
    {
      skills: [
        rollSkillInstance(STARTER_SKILLS[0]!, rng),
        rollSkillInstance(STARTER_SKILLS[1]!, rng),
      ],
    },
  );
}

function loadWorld(): { world: World; offlineMs: number } {
  const raw = localStorage.getItem(SAVE_KEY);
  if (!raw) return { world: freshWorld(), offlineMs: 0 };
  try {
    const stored = JSON.parse(raw) as StoredSave;
    const world = World.fromSave(registry, ZONE, stored.save, CONFIG);
    return { world, offlineMs: Math.max(0, Date.now() - stored.savedAt) };
  } catch {
    return { world: freshWorld(), offlineMs: 0 };
  }
}

function save(world: World): void {
  const payload: StoredSave = { save: world.serialize(), savedAt: Date.now() };
  try {
    localStorage.setItem(SAVE_KEY, JSON.stringify(payload));
  } catch {
    /* storage full or unavailable — ignore, gameplay continues */
  }
}

// ---------------------------------------------------------------------------
// Game state
// ---------------------------------------------------------------------------

let { world, offlineMs } = loadWorld();
let totalKills = 0;
let paused = false;

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function spawnDamage(side: 'hero' | 'enemy', text: string, kind: string): void {
  const scene = document.querySelector('.scene') as HTMLElement;
  const el = document.createElement('div');
  el.className = `dmg ${kind}`;
  el.textContent = text;
  el.style.left = side === 'enemy' ? '72%' : '22%';
  el.style.top = '40%';
  scene.appendChild(el);
  setTimeout(() => el.remove(), 800);
}

function flash(id: string, cls: string): void {
  const el = $(id);
  el.classList.add(cls);
  setTimeout(() => el.classList.remove(cls), 250);
}

function log(msg: string, cls = ''): void {
  const box = $('log');
  const line = document.createElement('div');
  if (cls) line.className = cls;
  line.textContent = msg;
  box.prepend(line);
  while (box.childElementCount > 40) box.lastElementChild?.remove();
}

function renderParty(party: readonly Companion[], rosterCount: number): void {
  $('roster-count').textContent = String(rosterCount);
  const host = $('party');
  host.innerHTML = '';
  for (const c of party) {
    const chip = document.createElement('div');
    chip.className = `chip ${rarityClass(c.rarity)}`;
    chip.innerHTML = `<span>${c.shiny ? '✦' : ''}${spriteFor(c.baseName)}</span><span>${c.baseName}</span><span class="bond">♥${c.bond}</span>`;
    host.appendChild(chip);
  }
}

function renderStaticFromEvents(events: WorldEvent[]): void {
  for (const e of events) {
    switch (e.type) {
      case 'spawn':
        $('enemy-sprite').textContent = spriteFor(e.monster);
        $('enemy-name').textContent = e.monster;
        break;
      case 'attack':
        if (e.attacker === 'player') {
          flash('hero-sprite', 'attacking');
          flash('enemy-sprite', 'hit');
          spawnDamage('enemy', e.outcome.hit ? String(e.outcome.damage) : 'MISS',
            e.outcome.critical ? 'crit' : e.outcome.hit ? '' : 'miss');
        } else {
          flash('enemy-sprite', 'attacking');
          flash('hero-sprite', 'hit');
          if (e.outcome.hit) spawnDamage('hero', String(e.outcome.damage), '');
        }
        break;
      case 'companionAttack':
        flash('enemy-sprite', 'hit');
        if (e.outcome.damage > 0) spawnDamage('enemy', String(e.outcome.damage), '');
        break;
      case 'skill':
        if (e.damage > 0) spawnDamage('enemy', `${e.skill}! ${e.damage}`, 'skill');
        if (e.heal > 0) spawnDamage('hero', `+${e.heal}`, 'heal');
        break;
      case 'kill':
        totalKills++;
        log(`☠ ปราบ ${e.monster}  (+${e.experience} EXP, +${e.gold}💰)`, 'log-kill');
        break;
      case 'levelUp':
        log(`⬆ เลเวลอัป! ตอนนี้ Lv ${e.level}`, 'log-level');
        break;
      case 'companionJoined':
        log(`${e.shiny ? '✦ ' : ''}🪄 จับ ${e.companion} เข้าทีม!`,
          e.shiny ? 'log-shiny' : 'log-join');
        break;
      case 'fusion':
        log(`🧬 รวมร่างเป็น ${e.result}!`, 'log-fuse');
        break;
      case 'playerDefeated':
        log(`💀 พ่ายแพ้ต่อ ${e.byMonster} — ถอยกลับมารักษาตัว`, 'log-defeat');
        break;
      default:
        break;
    }
  }
}

function renderVitals(): void {
  const v = world.vitals;
  $('level').textContent = String(v.level);
  $('gold').textContent = v.gold.toLocaleString();
  const need = expToNext(v.level);
  const ratio = Number.isFinite(need) ? v.currentExp / need : 1;
  setBar($('xpfill'), ratio);
  $('xptext').textContent = Number.isFinite(need)
    ? `${v.currentExp} / ${need}`
    : 'MAX';

  const hero = world.hero;
  setBar($('hero-hp'), hero.currentHp / hero.maxHp);
  const enemy = world.enemy;
  if (enemy) setBar($('enemy-hp'), enemy.currentHp / enemy.maxHp);

  $('hero-mount').textContent = v.mount
    ? `🐎 ${v.mount.shiny ? '✦' : ''}${v.mount.rarity}`
    : '';

  $('kills').textContent = totalKills.toLocaleString();
  $('items').textContent = v.inventoryCount.toLocaleString();
  $('shinies').textContent = String(v.roster.filter((c) => c.shiny).length);

  renderParty(v.party, v.roster.length);
}

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

function step(): void {
  if (paused) return;
  const events = world.tick();
  renderStaticFromEvents(events);
  renderVitals();
}

// ---------------------------------------------------------------------------
// Offline welcome-back
// ---------------------------------------------------------------------------

function showWelcomeBack(): void {
  if (offlineMs < 60_000) return; // ignore short absences
  const summary = simulateOffline(world, offlineMs);
  totalKills += summary.kills;
  if (summary.kills === 0) return;
  const mins = Math.round(offlineMs / 60000);
  $('welcome-body').innerHTML = `
    <p>คุณไม่อยู่ไป <b>${mins}</b> นาที ทีมยังลุยต่อ:</p>
    <p>☠ ปราบมอนสเตอร์ <b>${summary.kills.toLocaleString()}</b> ตัว</p>
    <p>⬆ เลเวล +<b>${summary.levelsGained}</b></p>
    <p>💰 ทอง +<b>${summary.goldGained.toLocaleString()}</b></p>
    <p>🎁 ไอเทม <b>${summary.loot.length.toLocaleString()}</b> ชิ้น</p>`;
  $('welcome').classList.add('show');
}

// ---------------------------------------------------------------------------
// Wire up
// ---------------------------------------------------------------------------

$('welcome-ok').addEventListener('click', () => $('welcome').classList.remove('show'));

$('pause').addEventListener('click', () => {
  paused = !paused;
  $('pause').textContent = paused ? '▶ เล่นต่อ' : '⏸ หยุด';
});

$('reset').addEventListener('click', () => {
  if (!confirm('เริ่มเกมใหม่ทั้งหมด? เซฟปัจจุบันจะถูกลบ')) return;
  localStorage.removeItem(SAVE_KEY);
  world = freshWorld();
  totalKills = 0;
  $('log').innerHTML = '';
  log('เริ่มการผจญภัยใหม่!');
  renderVitals();
});

window.addEventListener('beforeunload', () => save(world));
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') save(world);
});

showWelcomeBack();
renderVitals();
log('ออกผจญภัย! ฮีโร่เดินและสู้เองอัตโนมัติ ⚔');
setInterval(step, TICK_MS);
setInterval(() => save(world), AUTOSAVE_MS);
