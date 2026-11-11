import type { BiomeId } from '../core/types';
import type { EffectDef, ItemTemplate, StatEffect, TriggerEffect } from './types';

const S = (stat: StatEffect['stat'], op: StatEffect['op'], value: number, extra: Partial<StatEffect> = {}): StatEffect =>
  ({ type: 'stat', stat, op, value, ...extra });

const T = (t: Omit<TriggerEffect, 'type'>): TriggerEffect => ({ type: 'trigger', ...t });

export interface UniqueDef {
  id: string;
  name: string;
  baseTemplateId: string;
  neuralCost?: number;
  biomes: BiomeId[];
  effects: EffectDef[];
  desc: string;
  /** Дополнительные заявленные обычные свойства (0–2). */
  extraProps?: StatEffect[];
}

/** Раздел 13 — 18 уникальных эффектов с точными ограничениями. */
export const UNIQUES: UniqueDef[] = [
  {
    id: 'U01', name: '«Чёрный конденсатор»', baseTemplateId: 'IMP_HEAT', neuralCost: 20, biomes: ['B05'],
    desc: 'При heat=100 снимает 25% ТЕКУЩИХ щитов вместо lockout (минимум 1 при shield>0); следующая энергетическая атака в течение 5 с получает MORE=(1+0.01×поглощённые щиты), максимум ×2.0. ICD 8 с. При нулевом щите — обычный lockout.',
    effects: [
      S('energyDamage', 'INCREASED', 20, { synScalable: true }),
      S('heatCooling', 'FLAT', -2, { synScalable: true }),
      T({
        id: 'U01_discharge', event: 'ON_HEAT_FULL', icdMs: 8000,
        action: { kind: 'consumeShieldForDamage', fraction: 0.25, maxMultiplier: 2.0, windowMs: 5000 },
        desc: 'Разряд перегрева в щиты → усиление следующей энергетической атаки.',
      }),
    ],
  },
  {
    id: 'U02', name: '«Эхо смерти»', baseTemplateId: 'IMP_DATA', neuralCost: 18, biomes: ['B06'],
    desc: 'Убийство ПРЯМЫМ ЦИФРОВЫМ уроном создаёт SECONDARY 60% TechPower D по другой живой цели. ICD 3 с. Не запускает новое убийство от U02.',
    effects: [
      S('digitalDamage', 'INCREASED', 18, { synScalable: true }),
      T({
        id: 'U02_echo', event: 'ON_KILL', icdMs: 3000, requireDirect: true, requireKillType: 'DIGITAL',
        action: { kind: 'secondaryDamage', basis: 'techPower', coefficient: 0.6, damageType: 'DIGITAL', targeting: 'otherEnemy', canProc: false },
        desc: 'Эхо убийства по другой цели.',
      }),
    ],
  },
  {
    id: 'U03', name: '«Нулевой провод»', baseTemplateId: 'FOCUS_D1', biomes: ['B04'],
    desc: 'Убийство заражённого врага переносит min(2, остаток стеков VIRUS) на другую цель с исходной остаточной длительностью. ICD 2 с.',
    effects: [
      T({
        id: 'U03_transfer', event: 'ON_KILL', icdMs: 2000, allowStatusTick: true, condition: { kind: 'targetStatus', status: 'VIRUS' },
        action: { kind: 'transferVirus', stacks: 2 }, desc: 'Перенос заражения.',
      }),
    ],
  },
  {
    id: 'U04', name: '«Реактивная оболочка»', baseTemplateId: 'ARM_HEAVY', biomes: ['B02'],
    desc: '20% реально поглощённого щитом урона копится в заряд (максимум 100×H(T)); каждые 4 с следующий успешный main direct hit добавляет заряд как SECONDARY ENERGY.',
    effects: [
      T({ id: 'U04_charge', event: 'ON_SHIELD_ABSORB', action: { kind: 'charge', amountFromAbsorbed: 0.2, capFormula: 'H(T)', capFlat: 100, intervalMs: 4000 }, desc: 'Накопление заряда из поглощённого щитом урона.' }),
      T({ id: 'U04_release', event: 'ON_BEFORE_HIT', requireDirect: true, action: { kind: 'spendFlagForDamage', flag: 'charge', perStack: 1, maxStacks: 1, intervalMs: 4000 }, desc: 'Выброс заряда вторичным ENERGY-пакетом.' }),
    ],
  },
  {
    id: 'U05', name: '«Рой-матрица»', baseTemplateId: 'IMP_DRONE', neuralCost: 20, biomes: ['B03'],
    desc: 'Когда дрон впервые получает смертельный урон в бою — EMP secondary по всем врагам 0.5×droneTechDamage D. ICD 12 с на каждый дрон, без воскрешения.',
    effects: [
      S('droneDamage', 'INCREASED', 20, { synScalable: true }),
      T({
        id: 'U05_emp', event: 'ON_DRONE_DEATH', icdMs: 12000, oncePerDrone: true,
        action: { kind: 'secondaryDamage', basis: 'droneTech', coefficient: 0.5, damageType: 'DIGITAL', targeting: 'allEnemies', canProc: false },
        desc: 'Смертельный EMP роя.',
      }),
    ],
  },
  {
    id: 'U06', name: '«Слепая зона»', baseTemplateId: 'ARM_CLOTH', biomes: ['B01'],
    desc: 'После боя без SK_EMP/SK_CHAIN/SK_PLASMA: −4 розыска и +10% доходов за скрытную победу. Всегда 15% LESS прямого урона.',
    effects: [
      S('moreDirect', 'LESS', 0.15),
      S('evasion', 'FLAT', 10),
    ],
  },
  {
    id: 'U07', name: '«Красная линия»', baseTemplateId: 'PLASMA_E1', biomes: ['B05'],
    desc: 'При heat≥70: +40% MORE ENERGY урона, охлаждение −3/с. Heat lockout сохраняется.',
    effects: [
      S('moreEnergy', 'MORE', 1.4, { condition: { kind: 'heatAtLeast', value: 70 } }),
      S('heatCooling', 'FLAT', -3),
    ],
  },
  {
    id: 'U08', name: '«Перепрошивка»', baseTemplateId: 'OFF_CORE_D', biomes: ['B04'],
    desc: 'После успешного SK_NEURO по механической небоссовой цели с HP≤25%: 35% шанс перехвата на 4 с (цель наносит 40% урона и не даёт лут). ICD 20 с. На боссах вместо перехвата 2 с JAM.',
    effects: [
      S('techPower', 'FLAT', 10, { note: '×H(T)' }),
      T({
        id: 'U08_control', event: 'ON_CAST', skillFilter: ['SK_NEURO'], icdMs: 20000,
        condition: { kind: 'all', inner: [{ kind: 'targetMechanical' }, { kind: 'targetHpBelow', value: 0.25 }] },
        action: { kind: 'control', chance: 0.35, durationMs: 4000, bossFallbackJamMs: 2000 },
        desc: 'Перехват управления.',
      }),
    ],
  },
  {
    id: 'U09', name: '«Дублирующий контур»', baseTemplateId: 'IMP_REGEN', neuralCost: 20, biomes: ['B04'],
    desc: 'Каждые 12 с повторяет последнюю DIGITAL-программу по доступной цели на 50% урона и 0 procWeight. Повтор не тратит энергию и не запускает U09 снова.',
    effects: [
      S('energyRegen', 'FLAT', 5, { synScalable: true }),
      T({ id: 'U09_repeat', event: 'PERIODIC', periodMs: 12000, action: { kind: 'repeatLastDigital', coefficient: 0.5 }, desc: 'Дублирование цифровой программы.' }),
    ],
  },
  {
    id: 'U10', name: '«Бастион»', baseTemplateId: 'OFF_SHIELD', biomes: ['B02'],
    desc: 'Дополнительные maxShields = 0.30 × итоговая броня (без вклада U10). Броня не тратится, зависимость односторонняя.',
    effects: [S('maxShield', 'FLAT', 35, { note: '×D(T)' }), S('shieldRegen', 'FLAT', 1)],
  },
  {
    id: 'U11', name: '«Квантовый долг»', baseTemplateId: 'IMP_HP', neuralCost: 15, biomes: ['B02'],
    desc: 'За каждые потерянные 10% максимального HP: +5% INCREASED урона (максимум +35%). При HP>80%: −10% MORE прямого урона. Бонус текущий, не snapshot.',
    effects: [
      S('maxHP', 'FLAT', 60, { note: '×D(T)', synScalable: true }),
      ...[0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3].map((th) => S('allDamage', 'INCREASED', 5, { condition: { kind: 'hpBelow', value: th }, note: `HP<${th * 100}%` })),
      S('moreDirect', 'LESS', 0.1, { condition: { kind: 'hpAbove', value: 0.8 } }),
    ],
  },
  {
    id: 'U12', name: '«Паразитический коллектор»', baseTemplateId: 'FOCUS_D1', biomes: ['B04'],
    desc: 'Прямое попадание по заражённой цели восстанавливает 4 энергии. ICD 1 с, максимум 12 энергии/с суммарно.',
    effects: [
      T({
        id: 'U12_leech', event: 'ON_HIT', icdMs: 1000, requireDirect: true, condition: { kind: 'targetStatus', status: 'VIRUS' },
        action: { kind: 'restoreEnergy', amount: 4, perSecondCap: 12 }, desc: 'Сбор энергии с заражённой цели.',
      }),
    ],
  },
  {
    id: 'U13', name: '«Призрачный курьер»', baseTemplateId: 'IMP_REFLEX', neuralCost: 18, biomes: ['B01'],
    desc: 'Каждое успешное уклонение даёт стек «фаза» на 8 с (до 3). Следующая main direct атака расходует все стеки: +12% MORE урона за стек.',
    effects: [
      S('attackSpeed', 'INCREASED', 12, { synScalable: true }),
      T({ id: 'U13_phase', event: 'ON_DODGE', action: { kind: 'flag', key: 'phase', amount: 1, max: 3, durationMs: 8000 }, desc: 'Накопление фазы при уклонении.' }),
      T({ id: 'U13_spend', event: 'ON_BEFORE_HIT', action: { kind: 'spendFlagForDamage', flag: 'phase', perStack: 0.12, maxStacks: 3 }, desc: 'Выброс фазы в урон.' }),
    ],
  },
  {
    id: 'U14', name: '«Холодное ядро»', baseTemplateId: 'OFF_COOL', biomes: ['B05'],
    desc: 'Если heat≤25 непрерывно 3 с: +25% MORE урона цифровых программ и +2 энергии/с. При выходе за порог эффект исчезает.',
    effects: [
      S('heatCooling', 'FLAT', 4),
      S('moreSkillDigital', 'MORE', 1.25, { condition: { kind: 'flagAtLeast', key: 'coldStreak', value: 3000 } }),
      S('energyRegen', 'FLAT', 2, { condition: { kind: 'flagAtLeast', key: 'coldStreak', value: 3000 } }),
    ],
  },
  {
    id: 'U15', name: '«Архивариус»', baseTemplateId: 'OFF_TARGET', biomes: ['B01'],
    desc: 'После успешного SK_SCAN: +1 раскрытый дорожный узел следующего сектора, но +2 розыска. Во время боя SK_SCAN даёт ещё +5 точности.',
    effects: [
      S('accuracy', 'FLAT', 12),
      S('armorPen', 'FLAT', 5),
      S('accuracy', 'FLAT', 5, { condition: { kind: 'flagTrue', key: 'scanActive' }, note: 'после SK_SCAN' }),
      T({ id: 'U15_reveal', event: 'ON_CAST', skillFilter: ['SK_SCAN'], action: { kind: 'revealNodes', amount: 1 }, desc: 'Дополнительная разведка карты.' }),
      T({ id: 'U15_wanted', event: 'ON_CAST', skillFilter: ['SK_SCAN'], action: { kind: 'wanted', amount: 2 }, desc: '+2 розыска.' }),
    ],
  },
  {
    id: 'U16', name: '«Командная нить»', baseTemplateId: 'IMP_DRONE', neuralCost: 22, biomes: ['B03'],
    desc: 'Если оба дрона живы и атакуют одну цель: +30% MORE урона дронов. При уничтожении любого бонус исчезает немедленно.',
    effects: [
      S('droneDamage', 'INCREASED', 10, { synScalable: true }),
      S('moreDrone', 'MORE', 1.3, { condition: { kind: 'bothDronesSameTarget' } }),
    ],
  },
  {
    id: 'U17', name: '«Сердце помех»', baseTemplateId: 'ARM_NET', biomes: ['B04'],
    desc: 'Каждый закончившийся вражеский JAM сокращает CD ближайшего SK_EMP на 2 с (не чаще раза в 5 с). Против цифровых врагов: +10 щита/с на 3 с.',
    effects: [
      S('digitalRes', 'FLAT', 10),
      T({ id: 'U17_cd', event: 'ON_STATUS_EXPIRE', statusFilter: ['JAM'], icdMs: 5000, action: { kind: 'reduceCooldown', skillId: 'SK_EMP', amountMs: 2000 }, desc: 'Сокращение CD перехвата после JAM.' }),
      T({
        id: 'U17_regen', event: 'ON_TAKEN_DAMAGE', damageTypeFilter: ['DIGITAL'],
        action: { kind: 'buff', mods: [S('shieldRegen', 'FLAT', 10)], durationMs: 3000 }, desc: 'Ускоренная регенерация щита против цифры.',
      }),
    ],
  },
  {
    id: 'U18', name: '«Долгий импульс»', baseTemplateId: 'RAIL_K6', biomes: ['B06'],
    desc: 'Каждая секунда без main атаки копит +10% MORE следующему K direct hit (до 6 стеков). Стеки сбрасываются только после успешного прямого K-попадания.',
    effects: [
      S('armorPen', 'FLAT', 25),
      T({ id: 'U18_stack', event: 'PERIODIC', periodMs: 1000, action: { kind: 'flag', key: 'longPulse', amount: 1, max: 6 }, desc: 'Накопление импульса.' }),
      T({ id: 'U18_spend', event: 'ON_BEFORE_HIT', damageTypeFilter: ['KINETIC'], action: { kind: 'spendFlagForDamage', flag: 'longPulse', perStack: 0.1, maxStacks: 6 }, desc: 'Выброс импульса в кинетический удар.' }),
    ],
  },
];

export const UNIQUE_BY_ID: Record<string, UniqueDef> = Object.fromEntries(UNIQUES.map((u) => [u.id, u]));

/** Уникальные предметы как itemDefinition с фиксированным эффектом. */
export const UNIQUE_TEMPLATES: ItemTemplate[] = UNIQUES.map((u) => {
  const base = u.baseTemplateId;
  return {
    id: u.id,
    name: u.name,
    category: base.startsWith('IMP_') ? 'IMPLANT' : base.startsWith('ARM_') ? 'ARMOR' : base.startsWith('OFF_') ? 'OFFHAND' : 'MAIN',
    implantSlot: base === 'IMP_HEAT' || base === 'IMP_HP' ? 'CHEST' : base === 'IMP_DATA' ? 'HEAD' : base === 'IMP_REFLEX' ? 'ARMS' : base === 'IMP_DRONE' || base === 'IMP_REGEN' ? 'NEURAL' : undefined,
    neuralCost: u.neuralCost,
    tags: ['unique', ...(base.startsWith('IMP_') ? ['implant'] : [])],
    weapon: base === 'FOCUS_D1' ? { damage: 33, type: 'DIGITAL', intervalMs: 1000 }
      : base === 'PLASMA_E1' ? { damage: 47, type: 'ENERGY', intervalMs: 1200, heatPerAttack: 8 }
      : base === 'RAIL_K6' ? { damage: 92, type: 'KINETIC', intervalMs: 1900, windupMs: 350 }
      : undefined,
    armorBlock: base === 'ARM_HEAVY' ? { hp: 120, shield: 10, armor: 20 }
      : base === 'ARM_CLOTH' ? { hp: 20, shield: 10, armor: 2 }
      : base === 'ARM_NET' ? { hp: 45, shield: 45, armor: 5 }
      : undefined,
    effects: [...u.effects, ...(u.extraProps ?? [])],
    cargoUnits: base.startsWith('ARM_') ? 2 : 1,
    craftable: false,
    uniqueEffectId: u.id,
    baseTemplateId: base,
    biomes: u.biomes,
    desc: u.desc,
  };
});

export const UNIQUE_TEMPLATE_BY_ID: Record<string, ItemTemplate> = Object.fromEntries(UNIQUE_TEMPLATES.map((t) => [t.id, t]));

export function uniquesForBiome(biome: BiomeId): UniqueDef[] {
  return UNIQUES.filter((u) => u.biomes.includes(biome));
}
