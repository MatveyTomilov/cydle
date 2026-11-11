import type { PassiveDef, SkillDef, StatEffect } from './types';

const S = (stat: StatEffect['stat'], op: StatEffect['op'], value: number, extra: Partial<StatEffect> = {}): StatEffect =>
  ({ type: 'stat', stat, op, value, ...extra });

/** Раздел 11 — активные способности. Все cooldown отсчитываются от старта каста. */
export const SKILLS: SkillDef[] = [
  {
    id: 'SK_BURST', name: 'Очередь', channel: 'main', tags: ['K', 'DIRECT', 'MULTI'], coefficient: 0.45, hits: 3, hitCoefficient: 0.45,
    energyCost: 0, heatDelta: 2, windupMs: 180, recoveryMs: 220, cooldownMs: 900, targetMode: 'nearest', procWeight: 0.35,
    basis: 'MAIN_K', requires: ['MAIN_K'], interruptible: false, desc: '3 пакета по 0.45 основного K-урона, procWeight 0.35 на пакет.',
  },
  {
    id: 'SK_PIERCE', name: 'Бронебойный', channel: 'main', tags: ['K', 'DIRECT'], coefficient: 1.6, hits: 1,
    energyCost: 12, heatDelta: 1, windupMs: 300, recoveryMs: 350, cooldownMs: 4000, targetMode: 'nearest', procWeight: 1,
    basis: 'MAIN_K', requires: ['MAIN_K'], interruptible: false,
    extraEffects: [S('armorPen', 'FLAT', 20, { note: 'только этот удар' })], desc: '1.60 K и +20 плоского пробития.',
  },
  {
    id: 'SK_EXEC', name: 'Контрольный', channel: 'main', tags: ['K', 'DIRECT'], coefficient: 1.3, hits: 1,
    energyCost: 15, heatDelta: 2, windupMs: 220, recoveryMs: 350, cooldownMs: 6000, targetMode: 'lowestHPPercent', procWeight: 1,
    basis: 'MAIN_K', special: 'EXECUTE', requires: ['MAIN_K'], interruptible: false, desc: '1.30 K, ×1.4 MORE если HP цели < 30%.',
  },
  {
    id: 'SK_BLADE', name: 'Серия', channel: 'main', tags: ['K', 'DIRECT', 'MULTI'], coefficient: 0.55, hits: 3, hitCoefficient: 0.55,
    energyCost: 10, heatDelta: 4, windupMs: 240, recoveryMs: 360, cooldownMs: 3000, targetMode: 'nearest', procWeight: 0.35,
    basis: 'MAIN_K', requires: ['MAIN_K'], interruptible: false,
    extraEffects: [{ type: 'trigger', id: 'SK_BLADE_bleed', event: 'ON_HIT', action: { kind: 'applyStatus', status: 'BLEED', stacks: 1, target: 'target' }, desc: 'BLEED на последнем ударе серии.' }],
    desc: '3×0.55 K, BLEED на последнем попадании.',
  },
  {
    id: 'SK_PLASMA', name: 'Плазменный', channel: 'main', tags: ['E', 'TECH', 'DIRECT'], coefficient: 1.45, hits: 1,
    energyCost: 16, heatDelta: 12, windupMs: 260, recoveryMs: 320, cooldownMs: 3000, targetMode: 'nearest', procWeight: 1,
    basis: 'TECH_E', interruptible: false, desc: '1.45 TechPower энергетического урона.',
  },
  {
    id: 'SK_ARC', name: 'Электродуга', channel: 'main', tags: ['E', 'TECH', 'DIRECT', 'MULTI'], coefficient: 1.0, hits: 1,
    energyCost: 24, heatDelta: 10, windupMs: 350, recoveryMs: 450, cooldownMs: 7000, targetMode: 'nearest', procWeight: 1,
    basis: 'TECH_E', splash: { coefficient: 0.5, targets: 2, status: 'SHOCK' }, interruptible: false,
    desc: '1.00 TechPower E по основной цели и 0.50 по двум вторичным, SHOCK 1 с.',
  },
  {
    id: 'SK_OVR', name: 'Форсаж', channel: 'main', tags: ['DIRECT'], coefficient: 0, hits: 0,
    energyCost: 20, heatDelta: 15, windupMs: 250, recoveryMs: 250, cooldownMs: 15000, targetMode: 'self', procWeight: 0,
    basis: 'NONE', special: 'OVERCLOCK', interruptible: false,
    extraEffects: [S('attackSpeed', 'INCREASED', 20, { note: '8 секунд' })],
    desc: '+20% скорости атаки на 8 с и +5 нагрева за каждую main автоатаку.',
  },
  {
    id: 'SK_NEURO', name: 'Нейроукол', channel: 'main', tags: ['D', 'TECH', 'DIRECT'], coefficient: 1.0, hits: 1,
    energyCost: 12, heatDelta: 2, windupMs: 180, recoveryMs: 280, cooldownMs: 3000, targetMode: 'nearest', procWeight: 1,
    basis: 'TECH_D', interruptible: false,
    extraEffects: [{ type: 'trigger', id: 'SK_NEURO_virus', event: 'ON_HIT', action: { kind: 'applyStatus', status: 'VIRUS', stacks: 1, target: 'target' }, desc: '+1 VIRUS.' }],
    desc: '1.00 TechPower D и +1 стек VIRUS.',
  },
  {
    id: 'SK_SEED', name: 'Вирусное семя', channel: 'main', tags: ['D', 'TECH', 'DIRECT'], coefficient: 0.7, hits: 1,
    energyCost: 20, heatDelta: 1, windupMs: 320, recoveryMs: 400, cooldownMs: 6000, targetMode: 'infected', procWeight: 1,
    basis: 'TECH_D', interruptible: false,
    extraEffects: [{ type: 'trigger', id: 'SK_SEED_virus', event: 'ON_HIT', action: { kind: 'applyStatus', status: 'VIRUS', stacks: 2, target: 'target' }, desc: '+2 VIRUS.' }],
    desc: '0.70 TechPower D и +2 стека VIRUS.',
  },
  {
    id: 'SK_DETONATE', name: 'Детонация', channel: 'main', tags: ['D', 'TECH', 'DIRECT'], coefficient: 0.6, hits: 1,
    energyCost: 18, heatDelta: 4, windupMs: 200, recoveryMs: 350, cooldownMs: 8000, targetMode: 'infected', procWeight: 1,
    basis: 'NONE', special: 'DETONATE', requires: ['VIRUS'], interruptible: false,
    desc: '0.60 остаточного потенциала VIRUS как мгновенный D-урон, потребляет до 3 стеков.',
  },
  {
    id: 'SK_BREAK', name: 'Разлом', channel: 'main', tags: ['K', 'DIRECT'], coefficient: 0.8, hits: 1,
    energyCost: 12, heatDelta: 2, windupMs: 240, recoveryMs: 330, cooldownMs: 5000, targetMode: 'nearest', procWeight: 1,
    basis: 'MAIN_K', requires: ['MAIN_K'], interruptible: false,
    extraEffects: [{ type: 'trigger', id: 'SK_BREAK_ab', event: 'ON_HIT', action: { kind: 'applyStatus', status: 'ARMOR_BREAK', stacks: 1, target: 'target' }, desc: '+1 ARMOR_BREAK.' }],
    desc: '0.80 K и +1 стек ARMOR_BREAK.',
  },
  {
    id: 'SK_SCAN', name: 'Слабое место', channel: 'main', tags: ['DIRECT'], coefficient: 0, hits: 0,
    energyCost: 12, heatDelta: 0, windupMs: 220, recoveryMs: 270, cooldownMs: 8000, targetMode: 'boss', procWeight: 0,
    basis: 'NONE', special: 'SCAN', interruptible: false,
    desc: 'Метка цели: +12% MORE прямого урона по ней на 6 с.',
  },
  {
    id: 'SK_LEECH', name: 'Паразит', channel: 'main', tags: ['D', 'TECH', 'DIRECT'], coefficient: 1.0, hits: 1,
    energyCost: 14, heatDelta: 5, windupMs: 280, recoveryMs: 330, cooldownMs: 6000, targetMode: 'infected', procWeight: 1,
    basis: 'TECH_D', special: 'LEECH', interruptible: false, desc: '1.00 TechPower D; +8 энергии при попадании по заражённой цели.',
  },
  {
    id: 'SK_CHAIN', name: 'Перегрузка', channel: 'main', tags: ['E', 'TECH', 'DIRECT'], coefficient: 1.65, hits: 1,
    energyCost: 18, heatDelta: 18, windupMs: 400, recoveryMs: 500, cooldownMs: 10000, targetMode: 'nearest', procWeight: 1,
    basis: 'TECH_E', special: 'CHAIN_HEAT', interruptible: false, desc: '1.65 TechPower E; при heat≥80 ещё +25% MORE.',
  },
  {
    id: 'SK_KINETIC', name: 'Ударная волна', channel: 'main', tags: ['K', 'DIRECT', 'MULTI'], coefficient: 0.75, hits: 1,
    energyCost: 20, heatDelta: 5, windupMs: 350, recoveryMs: 400, cooldownMs: 9000, targetMode: 'allEnemies', procWeight: 0.35,
    basis: 'MAIN_K', maxTargets: 4, requires: ['MAIN_K'], interruptible: false, desc: '0.75 K по 4 целям, procWeight 0.35 каждая.',
  },
  {
    id: 'SK_SIDE_FIRE', name: 'Второй ствол', channel: 'main', tags: ['K', 'DIRECT'], coefficient: 1.3, hits: 1,
    energyCost: 8, heatDelta: 1, windupMs: 170, recoveryMs: 240, cooldownMs: 2500, targetMode: 'nearest', procWeight: 1,
    basis: 'OFFHAND', special: 'SIDE_FIRE', requires: ['SIDEARM'], interruptible: false, desc: '1.30 урона запасного оружия.',
  },
  {
    id: 'SK_SHIELD', name: 'Аварийный щит', channel: 'reaction', tags: ['REACTION'], coefficient: 0, hits: 0,
    energyCost: 30, heatDelta: 5, windupMs: 100, recoveryMs: 0, cooldownMs: 20000, targetMode: 'self', procWeight: 0,
    basis: 'NONE', special: 'TEMP_SHIELD', interruptible: false, desc: '+60 временных щитов на 5 с (cap источника 90).',
  },
  {
    id: 'SK_EMP', name: 'Перехват', channel: 'reaction', tags: ['REACTION', 'D', 'TECH', 'INTERRUPT'], coefficient: 0.6, hits: 1,
    energyCost: 18, heatDelta: 4, windupMs: 150, recoveryMs: 0, cooldownMs: 9000, targetMode: 'imminentCast', procWeight: 1,
    basis: 'TECH_D', special: 'EMP', interruptible: false, desc: 'Прерывает прерываемый каст и наносит 0.60 TechPower D.',
  },
  {
    id: 'SK_GUARD', name: 'Дефлектор', channel: 'reaction', tags: ['REACTION'], coefficient: 0, hits: 0,
    energyCost: 10, heatDelta: 0, windupMs: 100, recoveryMs: 0, cooldownMs: 8000, targetMode: 'self', procWeight: 0,
    basis: 'NONE', special: 'GUARD', interruptible: false, desc: '20% LESS входящего кинетического урона на 2 с.',
  },
  {
    id: 'SK_VENT', name: 'Продувка', channel: 'reaction', tags: ['REACTION'], coefficient: 0, hits: 0,
    energyCost: 0, heatDelta: -35, windupMs: 100, recoveryMs: 0, cooldownMs: 12000, targetMode: 'self', procWeight: 0,
    basis: 'NONE', special: 'VENT', interruptible: false, desc: 'Сбрасывает 35 нагрева; при снижении со 100 снимает lockout.',
  },
  {
    id: 'SK_HEAL', name: 'Ремодуль', channel: 'reaction', tags: ['REACTION'], coefficient: 0, hits: 0,
    energyCost: 20, heatDelta: 3, windupMs: 150, recoveryMs: 0, cooldownMs: 12000, targetMode: 'self', procWeight: 0,
    basis: 'NONE', special: 'HEAL', interruptible: false, desc: 'Лечение 30 + 0.10×maxHP (бонус ограничен 12% maxHP, всего ≤22% maxHP).',
  },
  {
    id: 'SK_DRONE_MARK', name: 'Синхрометка', channel: 'reaction', tags: ['REACTION', 'DRONE'], coefficient: 0, hits: 0,
    energyCost: 12, heatDelta: 1, windupMs: 100, recoveryMs: 0, cooldownMs: 6000, targetMode: 'boss', procWeight: 0,
    basis: 'NONE', special: 'DRONE_MARK', interruptible: false, desc: '+15 точности дронам по одной цели на 5 с.',
  },
  {
    id: 'SK_DRONE_REPAIR', name: 'Техподдержка', channel: 'droneA', tags: ['DRONE'], coefficient: 0, hits: 0,
    energyCost: 0, heatDelta: 0, windupMs: 200, recoveryMs: 0, cooldownMs: 15000, targetMode: 'self', procWeight: 0,
    basis: 'NONE', special: 'DRONE_REPAIR', requires: ['DR_MED'], interruptible: false, desc: '«Санитар» лечит себя на 25 HP и даёт оператору +20 щита.',
  },
  {
    id: 'SK_DRONE_EMP', name: 'Малый EMP', channel: 'droneA', tags: ['DRONE', 'D'], coefficient: 0.75, hits: 1,
    energyCost: 0, heatDelta: 0, windupMs: 200, recoveryMs: 0, cooldownMs: 14000, targetMode: 'imminentCast', procWeight: 1,
    basis: 'NONE', special: 'DRONE_EMP', requires: ['DR_EMP'], interruptible: false, desc: '«Фантом» 0.75 собственного TechDamage D и JAM цели.',
  },
];

export const SKILL_BY_ID: Record<string, SkillDef> = Object.fromEntries(SKILLS.map((s) => [s.id, s]));

/** Пассивные протоколы (10, выбрать ≤3). */
export const PASSIVES: PassiveDef[] = [
  { id: 'PP_ARMOR', name: 'Броневой протокол', effects: [S('armor', 'INCREASED', 12)], desc: '+12% INCREASED брони.' },
  { id: 'PP_ACCURACY', name: 'Протокол наведения', effects: [S('accuracy', 'FLAT', 10)], desc: '+10 точности.' },
  { id: 'PP_AMMO', name: 'Боевой протокол', effects: [S('mainDamage', 'INCREASED', 8)], desc: '+8% INCREASED урона основного оружия.' },
  { id: 'PP_HEAT', name: 'Термопротокол', effects: [S('heatCooling', 'FLAT', 2)], desc: '+2 охлаждения/с.' },
  { id: 'PP_VIRUS', name: 'Вирусный протокол', effects: [S('virusDamage', 'INCREASED', 15)], desc: '+15% INCREASED урона тиков VIRUS.' },
  { id: 'PP_SHIELD', name: 'Щитовой протокол', effects: [S('shieldRegen', 'FLAT', 1.5)], desc: '+1.5 щита/с после 4 с без урона.' },
  { id: 'PP_DRONE', name: 'Дроновый протокол', effects: [S('droneDamage', 'INCREASED', 12)], desc: '+12% INCREASED урона дронов.' },
  { id: 'PP_HUNTER', name: 'Протокол охоты', effects: [S('bountyCurrency', 'INCREASED', 10)], desc: '+10% валютных наград только с охотников.' },
  { id: 'PP_ESCAPE', name: 'Протокол отхода', effects: [S('extractionChance', 'FLAT', 15)], desc: '+15 п.п. к шансу аварийной эвакуации.' },
  { id: 'PP_ECONOMY', name: 'Экономный протокол', effects: [S('repairCostLess', 'FLAT', 10)], desc: '−10% стоимости ремонта металлом (округление вверх, минимум 1).' },
];

export const PASSIVE_BY_ID: Record<string, PassiveDef> = Object.fromEntries(PASSIVES.map((p) => [p.id, p]));
