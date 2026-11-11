import type { BossTemplate, EnemyAbility, EnemyTemplate } from './types';

const ab = (a: Partial<EnemyAbility> & { id: string; kind: EnemyAbility['kind']; desc: string }): EnemyAbility => ({
  firstAtMs: 5000, everyMs: 10000, windupMs: 0, telegraphMs: 0, interruptible: false, ...a,
});

interface Row {
  id: string; name: string; hp: number; shield: number; armor: number; resE: number; resD: number; eva: number;
  damage: number; interval: number; type: 'KINETIC' | 'ENERGY' | 'DIGITAL'; threat: number; mech?: boolean; healer?: boolean;
  role: string; unlock: number; biomes: string[]; abilities?: EnemyAbility[]; desc: string;
}

const ROWS: Row[] = [
  { id: 'E01', name: 'Рейдер', hp: 140, shield: 0, armor: 3, resE: 0, resD: 0, eva: 20, damage: 19, interval: 1100, type: 'KINETIC', threat: 1, role: 'melee', unlock: 1, biomes: ['B01', 'B03'], desc: 'Быстрые одиночные атаки.' },
  { id: 'E02', name: 'Ночной стрелок', hp: 110, shield: 0, armor: 2, resE: 0, resD: 0, eva: 30, damage: 29, interval: 1800, type: 'KINETIC', threat: 1, role: 'sniper', unlock: 1, biomes: ['B01'], desc: 'Опасный выстрел с телеграфом 900 мс после 5 с.',
    abilities: [ab({ id: 'E02_snipe', kind: 'heavyAttack', firstAtMs: 5000, everyMs: 9000, windupMs: 900, telegraphMs: 900, interruptible: true, damage: 58, damageType: 'KINETIC', desc: 'Прицельный выстрел двойного урона' })] },
  { id: 'E03', name: 'Уличный щитоносец', hp: 230, shield: 60, armor: 14, resE: 5, resD: 0, eva: 10, damage: 14, interval: 1600, type: 'KINETIC', threat: 1, role: 'tank', unlock: 1, biomes: ['B01', 'B02'], desc: 'Восстанавливает 20 щита каждые 8 с.',
    abilities: [ab({ id: 'E03_shield', kind: 'shieldRestore', firstAtMs: 8000, everyMs: 8000, amount: 20, desc: 'Восстановление 20 щита' })] },
  { id: 'E04', name: 'Дозорный', hp: 150, shield: 20, armor: 6, resE: 0, resD: 0, eva: 20, damage: 17, interval: 950, type: 'KINETIC', threat: 1, role: 'marker', unlock: 1, biomes: ['B01', 'B02'], desc: 'Отмечает героя: следующий удар +30%.',
    abilities: [ab({ id: 'E04_mark', kind: 'mark', firstAtMs: 4000, everyMs: 8000, status: 'MARK', statusDurationMs: 6000, desc: 'Метка: следующий удар по оператору +30%' })] },
  { id: 'E05', name: 'Курьер-тень', hp: 95, shield: 0, armor: 1, resE: 0, resD: 0, eva: 60, damage: 17, interval: 650, type: 'KINETIC', threat: 1, role: 'evader', unlock: 1, biomes: ['B01'], desc: 'Высокое уклонение.' },
  { id: 'E06', name: 'Сборщик', hp: 200, shield: 0, armor: 8, resE: 0, resD: 0, eva: 15, damage: 23, interval: 1450, type: 'KINETIC', threat: 1, role: 'looter', unlock: 1, biomes: ['B03'], desc: 'Если выживает 15 с — сбегает с одним незакреплённым предметом.',
    abilities: [ab({ id: 'E06_escape', kind: 'escape', firstAtMs: 15000, everyMs: 999000, desc: 'Побег с грузом через 15 с' })] },
  { id: 'E07', name: 'Артиллерист', hp: 150, shield: 0, armor: 5, resE: 0, resD: 0, eva: 10, damage: 39, interval: 2500, type: 'KINETIC', threat: 2, role: 'burst', unlock: 2, biomes: ['B02', 'B03'], desc: 'Опасный каст с windup 2.0 с, прерываемый.',
    abilities: [ab({ id: 'E07_shell', kind: 'heavyAttack', firstAtMs: 5000, everyMs: 9000, windupMs: 2000, telegraphMs: 2000, interruptible: true, damage: 78, damageType: 'KINETIC', desc: 'Артобстрел двойного урона' })] },
  { id: 'E08', name: 'Турель', hp: 190, shield: 20, armor: 10, resE: 10, resD: 0, eva: 0, damage: 17, interval: 800, type: 'KINETIC', threat: 2, mech: true, role: 'turret', unlock: 2, biomes: ['B03', 'B02'], desc: 'Стационарна, иммунитет только к смещению.' },
  { id: 'E09', name: 'Техник', hp: 170, shield: 30, armor: 4, resE: 0, resD: 10, eva: 20, damage: 13, interval: 1500, type: 'ENERGY', threat: 2, mech: true, healer: true, role: 'healer', unlock: 2, biomes: ['B02', 'B03'], desc: 'Лечит союзника с наименьшим HP на 30 каждые 8 с.',
    abilities: [ab({ id: 'E09_heal', kind: 'heal', firstAtMs: 8000, everyMs: 8000, windupMs: 800, telegraphMs: 800, interruptible: true, amount: 30, desc: 'Ремонт союзника 30 HP' })] },
  { id: 'E10', name: 'Дроновод', hp: 145, shield: 20, armor: 3, resE: 0, resD: 10, eva: 15, damage: 16, interval: 1200, type: 'DIGITAL', threat: 2, mech: true, role: 'summoner', unlock: 2, biomes: ['B03', 'B04'], desc: 'Выпускает мелкий рой на 5-й секунде (лимит 2).',
    abilities: [ab({ id: 'E10_summon', kind: 'summon', firstAtMs: 5000, everyMs: 999000, summonId: 'E20', summonCount: 1, windupMs: 1000, telegraphMs: 1000, interruptible: true, desc: 'Призыв роя' })] },
  { id: 'E11', name: 'Перехватчик', hp: 180, shield: 0, armor: 6, resE: 0, resD: 0, eva: 30, damage: 21, interval: 1100, type: 'KINETIC', threat: 2, role: 'hunter', unlock: 2, biomes: ['B01', 'B02'], desc: 'После боя +3 розыска.',
    abilities: [ab({ id: 'E11_wanted', kind: 'wantedBoost', amount: 3, desc: '+3 розыска после боя' })] },
  { id: 'E12', name: 'Корп. щитовик', hp: 290, shield: 95, armor: 16, resE: 15, resD: 5, eva: 10, damage: 20, interval: 1500, type: 'KINETIC', threat: 2, role: 'protector', unlock: 2, biomes: ['B02'], desc: 'Прикрывает слабейшего союзника: −15% получаемого урона.',
    abilities: [ab({ id: 'E12_protect', kind: 'protectAlly', amount: 15, desc: 'Прикрытие союзника' })] },
  { id: 'E13', name: 'Нейроловец', hp: 175, shield: 0, armor: 3, resE: 0, resD: 30, eva: 25, damage: 27, interval: 1800, type: 'DIGITAL', threat: 2, role: 'jammer', unlock: 5, biomes: ['B04'], desc: 'JAM 3 с каждые 10 с.',
    abilities: [ab({ id: 'E13_jam', kind: 'applyStatus', firstAtMs: 6000, everyMs: 10000, status: 'JAM', statusDurationMs: 3000, windupMs: 800, telegraphMs: 800, interruptible: true, desc: 'Цифровые помехи' })] },
  { id: 'E14', name: 'Паразит', hp: 140, shield: 10, armor: 3, resE: 0, resD: 10, eva: 35, damage: 16, interval: 1050, type: 'DIGITAL', threat: 2, role: 'infector', unlock: 5, biomes: ['B04'], desc: 'Каждый третий прямой удар накладывает VIRUS.',
    abilities: [ab({ id: 'E14_virus', kind: 'applyStatus', firstAtMs: 0, everyMs: 0, status: 'VIRUS', desc: 'VIRUS на каждом 3-м ударе' })] },
  { id: 'E15', name: 'Кодер', hp: 200, shield: 20, armor: 5, resE: 5, resD: 20, eva: 20, damage: 21, interval: 1350, type: 'DIGITAL', threat: 2, mech: true, role: 'droneDenial', unlock: 5, biomes: ['B04', 'B03'], desc: 'DRONE_JAM 2 с каждые 9 с.',
    abilities: [ab({ id: 'E15_dronejam', kind: 'applyStatus', firstAtMs: 5000, everyMs: 9000, status: 'DRONE_JAM', statusDurationMs: 2000, windupMs: 700, telegraphMs: 700, interruptible: true, desc: 'Помехи дронам' })] },
  { id: 'E16', name: 'Медик корпорации', hp: 165, shield: 35, armor: 5, resE: 0, resD: 15, eva: 15, damage: 13, interval: 1500, type: 'ENERGY', threat: 2, healer: true, role: 'healer', unlock: 5, biomes: ['B02'], desc: '+40 HP союзнику каждые 9 с, прерываемо.',
    abilities: [ab({ id: 'E16_heal', kind: 'heal', firstAtMs: 9000, everyMs: 9000, windupMs: 1200, telegraphMs: 1200, interruptible: true, amount: 40, desc: 'Лечение союзника 40 HP' })] },
  { id: 'E17', name: 'Пиромант', hp: 180, shield: 20, armor: 3, resE: 20, resD: 0, eva: 20, damage: 22, interval: 1300, type: 'ENERGY', threat: 3, role: 'heat', unlock: 5, biomes: ['B05'], desc: '+10 нагрева герою каждые 6 с.',
    abilities: [ab({ id: 'E17_heat', kind: 'heat', firstAtMs: 6000, everyMs: 6000, amount: 10, windupMs: 600, telegraphMs: 600, interruptible: true, desc: 'Тепловой импульс' })] },
  { id: 'E18', name: 'Тепловой страж', hp: 260, shield: 55, armor: 12, resE: 25, resD: 0, eva: 10, damage: 22, interval: 1750, type: 'ENERGY', threat: 3, role: 'tank', unlock: 5, biomes: ['B05'], desc: 'SHIELD_LEAK 4 с при первом попадании.',
    abilities: [ab({ id: 'E18_leak', kind: 'applyStatus', firstAtMs: 0, everyMs: 0, status: 'SHIELD_LEAK', statusDurationMs: 4000, desc: 'Утечка щита при первом ударе' })] },
  { id: 'E19', name: 'Реактор', hp: 270, shield: 40, armor: 9, resE: 35, resD: 0, eva: 5, damage: 25, interval: 1700, type: 'ENERGY', threat: 3, mech: true, role: 'burst', unlock: 5, biomes: ['B05'], desc: 'При гибели 45 E вторичного урона с телеграфом 1.2 с.',
    abilities: [ab({ id: 'E19_death', kind: 'deathBurst', damage: 45, damageType: 'ENERGY', telegraphMs: 1200, desc: 'Взрыв при гибели' })] },
  { id: 'E20', name: 'Рой мелких', hp: 75, shield: 0, armor: 0, resE: 0, resD: 0, eva: 40, damage: 8, interval: 550, type: 'KINETIC', threat: 3, role: 'swarm', unlock: 5, biomes: ['B03', 'B04', 'B06'], desc: 'Появляется группой 2–4, без бесконечного спавна.' },
  { id: 'E21', name: 'Охотник нуль', hp: 280, shield: 50, armor: 12, resE: 5, resD: 20, eva: 20, damage: 28, interval: 1450, type: 'DIGITAL', threat: 3, role: 'hunter', unlock: 9, biomes: ['B06', 'B04'], desc: 'Чередует DRONE_JAM и обход щита 20%.',
    abilities: [
      ab({ id: 'E21_jam', kind: 'applyStatus', firstAtMs: 6000, everyMs: 12000, status: 'DRONE_JAM', statusDurationMs: 2000, windupMs: 800, telegraphMs: 800, interruptible: true, desc: 'Помехи дронам' }),
      ab({ id: 'E21_bypass', kind: 'shieldBypass', firstAtMs: 12000, everyMs: 12000, amount: 0.2, windupMs: 1000, telegraphMs: 1000, interruptible: true, desc: 'Обход щита 20%' }),
    ] },
  { id: 'E22', name: 'Хамелеон', hp: 150, shield: 0, armor: 2, resE: 0, resD: 0, eva: 80, damage: 19, interval: 900, type: 'KINETIC', threat: 3, role: 'evader', unlock: 9, biomes: ['B01', 'B06'], desc: 'Очень высокое уклонение, сканирование раскрывает слабость.' },
  { id: 'E23', name: 'Киберберсерк', hp: 240, shield: 0, armor: 6, resE: 0, resD: 0, eva: 5, damage: 28, interval: 1200, type: 'KINETIC', threat: 3, role: 'melee', unlock: 9, biomes: ['B06', 'B05'], desc: '+15% MORE урона после гибели союзника, максимум 2 стека.',
    abilities: [ab({ id: 'E23_rage', kind: 'applyStatus', firstAtMs: 0, everyMs: 0, status: 'BERSERK', desc: 'Ярость после гибели союзника' })] },
  { id: 'E24', name: 'Архивный судья', hp: 250, shield: 80, armor: 10, resE: 10, resD: 25, eva: 20, damage: 25, interval: 1550, type: 'DIGITAL', threat: 3, mech: true, role: 'punisher', unlock: 9, biomes: ['B06', 'B04'], desc: 'Троекратное подряд применение одной программы вызывает JAM 2 с.',
    abilities: [ab({ id: 'E24_punish', kind: 'jamPunish', status: 'JAM', statusDurationMs: 2000, desc: 'Наказание за повтор программы' })] },
];

export const ENEMIES: EnemyTemplate[] = ROWS.map((r) => ({
  id: r.id, name: r.name, hp: r.hp, shield: r.shield, armor: r.armor, resE: r.resE, resD: r.resD, evasion: r.eva,
  damage: r.damage, intervalMs: r.interval, type: r.type, threatUnits: r.threat, mechanical: !!r.mech, healer: !!r.healer,
  role: r.role, abilities: r.abilities ?? [], unlockDepth: r.unlock, biomes: r.biomes as EnemyTemplate['biomes'], desc: r.desc,
}));

export const ENEMY_BY_ID: Record<string, EnemyTemplate> = Object.fromEntries(ENEMIES.map((e) => [e.id, e]));

/* ---------------- Боссы (раздел 18) ---------------- */

export const BOSSES: BossTemplate[] = [
  {
    ...ENEMY_BY_ID['E01']!, id: 'BOSS_A', name: 'Бастион', hp: 1250, shield: 250, armor: 25, resE: 15, resD: 10, evasion: 10,
    damage: 45, intervalMs: 1700, type: 'KINETIC', threatUnits: 6, mechanical: true, healer: false, role: 'boss',
    unlockDepth: 4, biomes: ['B01'], isBoss: true, accuracy: 110,
    desc: 'Координатор блокпостов. Тяжёлый рельсовый выстрел и подкрепление.',
    phases: [
      { hpFraction: 0.7, kind: 'summon', summonId: 'E09', desc: 'На 70% вызывает техника' },
      { hpFraction: 0.35, kind: 'attackSpeed', amount: 0.2, desc: 'На 35% +20% скорости атаки' },
    ],
    abilities: [ab({ id: 'BOSS_A_rail', kind: 'heavyAttack', firstAtMs: 12000, everyMs: 12000, windupMs: 1500, telegraphMs: 1500, interruptible: true, damage: 125, damageType: 'KINETIC', desc: 'Рельсовый выстрел 125 K' })],
  },
  {
    ...ENEMY_BY_ID['E01']!, id: 'BOSS_B', name: 'Хирург', hp: 1550, shield: 180, armor: 18, resE: 10, resD: 20, evasion: 15,
    damage: 40, intervalMs: 1300, type: 'KINETIC', threatUnits: 6, mechanical: false, healer: false, role: 'boss',
    unlockDepth: 8, biomes: ['B04'], isBoss: true, accuracy: 110,
    desc: 'Перехватчик подсети. Цифровой скальпель обходит щит и вызывает утечку.',
    phases: [
      { hpFraction: 0.6, kind: 'intervalReduce', amount: 0.15, desc: 'На 60% ускоряет атаки' },
      { hpFraction: 0.3, kind: 'cleanse', desc: 'На 30% один раз снимает свои статусы' },
    ],
    abilities: [ab({ id: 'BOSS_B_scalpel', kind: 'heavyAttack', firstAtMs: 11000, everyMs: 11000, windupMs: 1500, telegraphMs: 1500, interruptible: true, damage: 95, damageType: 'DIGITAL', bypassShieldRatio: 0.25, status: 'SHIELD_LEAK', statusDurationMs: 4000, desc: 'Скальпель 95 D, обход щита 25%, SHIELD_LEAK' })],
  },
  {
    ...ENEMY_BY_ID['E01']!, id: 'BOSS_C', name: 'Хор-9', hp: 1350, shield: 350, armor: 12, resE: 5, resD: 35, evasion: 15,
    damage: 45, intervalMs: 1600, type: 'DIGITAL', threatUnits: 6, mechanical: true, healer: false, role: 'boss',
    unlockDepth: 8, biomes: ['B04'], isBoss: true, accuracy: 110,
    desc: 'Автономный ИИ-хор. Призывы и сетевой импульс.',
    phases: [
      { hpFraction: 0.65, kind: 'summon', summonId: 'E14', desc: 'На 65% призывает паразита' },
      { hpFraction: 0.3, kind: 'summon', summonId: 'E15', desc: 'На 30% призывает кодера' },
    ],
    abilities: [ab({ id: 'BOSS_C_pulse', kind: 'heavyAttack', firstAtMs: 15000, everyMs: 15000, windupMs: 1500, telegraphMs: 1500, interruptible: true, damage: 75, damageType: 'DIGITAL', desc: 'Сетевой импульс 75 D' })],
  },
  {
    ...ENEMY_BY_ID['E01']!, id: 'BOSS_D', name: 'Огненное сердце', hp: 1650, shield: 150, armor: 16, resE: 35, resD: 5, evasion: 10,
    damage: 48, intervalMs: 1700, type: 'ENERGY', threatUnits: 6, mechanical: true, healer: false, role: 'boss',
    unlockDepth: 8, biomes: ['B05'], isBoss: true, accuracy: 110, ambientHeatPerSec: 2,
    desc: 'Реактор термического пояса. Постоянный нагрев и тепловые взрывы.',
    phases: [
      { hpFraction: 0.6, kind: 'attackSpeed', amount: 0.1, desc: 'На 60% +10% скорости атаки' },
      { hpFraction: 0.25, kind: 'intervalReduce', amount: 0.29, desc: 'На 25% интервал взрыва 10 с' },
    ],
    abilities: [ab({ id: 'BOSS_D_burst', kind: 'heavyAttack', firstAtMs: 14000, everyMs: 14000, windupMs: 1500, telegraphMs: 1500, interruptible: true, damage: 85, damageType: 'ENERGY', desc: 'Тепловой взрыв 85 E' })],
  },
  {
    ...ENEMY_BY_ID['E01']!, id: 'BOSS_E', name: 'Патрон', hp: 1500, shield: 230, armor: 20, resE: 10, resD: 10, evasion: 10,
    damage: 40, intervalMs: 1400, type: 'KINETIC', threatUnits: 6, mechanical: false, healer: false, role: 'boss',
    unlockDepth: 8, biomes: ['B02'], isBoss: true, accuracy: 110,
    desc: 'Корпоративный куратор. Подкрепления и тяжёлый удар.',
    phases: [
      { hpFraction: 0.7, kind: 'summon', summonId: 'E09', desc: 'На 70% вызывает техника' },
      { hpFraction: 0.4, kind: 'summon', summonId: 'E08', desc: 'На 40% ставит турель' },
    ],
    abilities: [ab({ id: 'BOSS_E_heavy', kind: 'heavyAttack', firstAtMs: 13000, everyMs: 13000, windupMs: 1600, telegraphMs: 1600, interruptible: true, damage: 100, damageType: 'KINETIC', desc: 'Тяжёлый удар 100 K' })],
  },
  {
    ...ENEMY_BY_ID['E01']!, id: 'BOSS_CORE', name: 'Сердце тракта', hp: 1900, shield: 400, armor: 22, resE: 20, resD: 25, evasion: 15,
    damage: 45, intervalMs: 1400, type: 'ENERGY', threatUnits: 8, mechanical: true, healer: false, role: 'boss',
    unlockDepth: 12, biomes: ['B06'], isBoss: true, accuracy: 110,
    desc: 'CORE_12. Двойной пакет 22.5 E + 22.5 D и ротация трёх телеграфируемых волн.',
    phases: [
      { hpFraction: 0.7, kind: 'summon', summonId: 'E09', desc: 'На 70% вызывает техника' },
      { hpFraction: 0.4, kind: 'bypassUpgrade', amount: 0.25, desc: 'На 40% цифровая волна обходит 25% щита' },
      { hpFraction: 0.15, kind: 'castSpeed', amount: 0.2, desc: 'На 15% +20% скорости каста' },
    ],
    abilities: [],
    rotating: [
      ab({ id: 'CORE_rail', kind: 'heavyAttack', firstAtMs: 12000, everyMs: 36000, windupMs: 1500, telegraphMs: 1500, interruptible: true, damage: 115, damageType: 'KINETIC', desc: 'K-рельс 115' }),
      ab({ id: 'CORE_jam', kind: 'heavyAttack', firstAtMs: 24000, everyMs: 36000, windupMs: 1500, telegraphMs: 1500, interruptible: true, damage: 80, damageType: 'DIGITAL', status: 'JAM', statusDurationMs: 3000, desc: 'Цифровая волна 80 D + JAM' }),
      ab({ id: 'CORE_suppress', kind: 'applyStatus', firstAtMs: 36000, everyMs: 36000, status: 'DRONE_JAM', statusDurationMs: 2000, windupMs: 1500, telegraphMs: 1500, interruptible: true, desc: 'Подавление дронов 2 с' }),
    ],
  },
];

export const BOSS_BY_ID: Record<string, BossTemplate> = Object.fromEntries(BOSSES.map((b) => [b.id, b]));

export function isBossId(id: string): boolean {
  return id.startsWith('BOSS_');
}

export function enemyTemplate(id: string): EnemyTemplate | BossTemplate {
  return BOSS_BY_ID[id] ?? ENEMY_BY_ID[id]!;
}

export const ELITE_MODS = [
  { id: 'EL_SHIELD', name: 'Щитовой', desc: '+30% щита и разовое восстановление 20 щита при HP<50%' },
  { id: 'EL_FAST', name: 'Скоростной', desc: '+20% скорости атаки, −10% HP' },
  { id: 'EL_VIRUS', name: 'Заражённый', desc: 'Каждый 3-й удар накладывает VIRUS, +10% цифрового сопротивления' },
  { id: 'EL_ANTI_DRONE', name: 'Противодроновый', desc: 'DRONE_JAM каждые 8 с с телеграфом 1.2 с' },
  { id: 'EL_PEN', name: 'Пробивающий', desc: '+10 плоского пробития брони, +200 мс windup' },
  { id: 'EL_SPLIT', name: 'Делящийся', desc: 'При гибели появляются два E20 с 50% HP без лута' },
] as const;

export type EliteModId = (typeof ELITE_MODS)[number]['id'];
