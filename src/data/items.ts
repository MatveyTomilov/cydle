import type { ItemTemplate } from './types';
import { mod } from '../core/math/stats';
import type { StatEffect } from './types';

const S = (stat: StatEffect['stat'], op: StatEffect['op'], value: number, extra: Partial<StatEffect> = {}): StatEffect => ({ type: 'stat', stat, op, value, ...extra });
void mod;

/** Раздел 10 — полный каталог базовых предметов. */
export const ITEM_TEMPLATES: ItemTemplate[] = [
  /* ---------------- 10.1 Вооружение (12 main) ---------------- */
  {
    id: 'PISTOL_K1', name: '«Кобра»', category: 'MAIN', tags: ['weapon', 'kinetic', 'pistol'], cargoUnits: 1, craftable: true,
    weapon: { damage: 34, type: 'KINETIC', intervalMs: 750 },
    effects: [S('accuracy', 'FLAT', 5)], desc: 'Надёжный пистолет. +5 точности.',
  },
  {
    id: 'RIFLE_K2', name: '«Гвоздь»', category: 'MAIN', tags: ['weapon', 'kinetic', 'rifle'], cargoUnits: 2, craftable: true,
    weapon: { damage: 52, type: 'KINETIC', intervalMs: 1100 },
    effects: [S('armorPen', 'FLAT', 10, { condition: { kind: 'flagTrue', key: 'firstAttack' }, note: 'первая атака боя' })],
    desc: '10 плоского пробития в первой атаке каждого боя.',
  },
  {
    id: 'SMG_K3', name: '«Искра»', category: 'MAIN', tags: ['weapon', 'kinetic', 'smg', 'fast'], cargoUnits: 1, craftable: true,
    weapon: { damage: 19, type: 'KINETIC', intervalMs: 360, procWeight: 0.6 },
    effects: [], desc: 'Очень быстрый ПП. procWeight 0.6 на выстрел.',
  },
  {
    id: 'BLADE_K4', name: '«Сдвиг»', category: 'MAIN', tags: ['weapon', 'kinetic', 'blade', 'bleed'], cargoUnits: 1, craftable: true,
    weapon: { damage: 68, type: 'KINETIC', intervalMs: 1350 },
    effects: [S('kineticDamage', 'INCREASED', 10, { condition: { kind: 'targetStatus', status: 'BLEED' }, note: 'по кровоточащей цели' })],
    desc: '+10% урона по цели с BLEED.',
  },
  {
    id: 'SHOTGUN_K5', name: '«Соты»', category: 'MAIN', tags: ['weapon', 'kinetic', 'shotgun'], cargoUnits: 2, craftable: true,
    weapon: { damage: 24, type: 'KINETIC', intervalMs: 1600, pelletCount: 4, pelletProcWeight: 0.25 },
    effects: [], desc: '4 пакета по 24, procWeight 0.25 каждый, один общий кулдаун.',
  },
  {
    id: 'RAIL_K6', name: '«Нить»', category: 'MAIN', tags: ['weapon', 'kinetic', 'rail', 'heavy'], cargoUnits: 2, craftable: true,
    weapon: { damage: 92, type: 'KINETIC', intervalMs: 1900, windupMs: 350 },
    effects: [S('armorPen', 'FLAT', 25)], desc: '+25 плоского пробития, windup 350 мс.',
  },
  {
    id: 'PLASMA_E1', name: '«Жар»', category: 'MAIN', tags: ['weapon', 'energy', 'heat'], cargoUnits: 2, craftable: true,
    weapon: { damage: 47, type: 'ENERGY', intervalMs: 1200, heatPerAttack: 8 },
    effects: [], desc: '+8 нагрева за автоатаку.',
  },
  {
    id: 'ARC_E2', name: '«Разряд»', category: 'MAIN', tags: ['weapon', 'energy', 'arc'], cargoUnits: 1, craftable: true,
    weapon: { damage: 31, type: 'ENERGY', intervalMs: 950 },
    effects: [{
      type: 'trigger', id: 'ARC_E2_splash', event: 'ON_ATTACK_COUNTER', counterEvery: 4,
      action: { kind: 'secondaryDamage', basis: 'mainWeapon', coefficient: 0.25, damageType: 'ENERGY', targeting: 'secondary', canProc: false },
      desc: 'Каждая 4-я атака: 25% всплеска по второй цели без on-hit.',
    }],
    desc: 'Каждая 4-я атака бьёт вторую цель на 25%.',
  },
  {
    id: 'LASER_E3', name: '«Световод»', category: 'MAIN', tags: ['weapon', 'energy', 'laser', 'fast'], cargoUnits: 1, craftable: true,
    weapon: { damage: 30, type: 'ENERGY', intervalMs: 620, heatPerAttack: 3, energyPerAttack: 3 },
    effects: [S('accuracy', 'FLAT', 8)], desc: '+3 нагрева и +3 энергии за атаку, +8 точности.',
  },
  {
    id: 'FOCUS_D1', name: '«Кодер»', category: 'MAIN', tags: ['weapon', 'digital', 'virus'], cargoUnits: 1, craftable: true,
    weapon: { damage: 33, type: 'DIGITAL', intervalMs: 1000 },
    effects: [{
      type: 'trigger', id: 'FOCUS_D1_virus', event: 'ON_ATTACK_COUNTER', counterEvery: 4,
      action: { kind: 'applyStatus', status: 'VIRUS', stacks: 1, target: 'target' },
      desc: 'Каждый 4-й прямой удар добавляет 1 стек VIRUS.',
    }],
    desc: 'Каждый 4-й успешный прямой удар: +1 VIRUS.',
  },
  {
    id: 'SPIKE_D2', name: '«Жало»', category: 'MAIN', tags: ['weapon', 'digital', 'pen'], cargoUnits: 1, craftable: true,
    weapon: { damage: 50, type: 'DIGITAL', intervalMs: 1300 },
    effects: [S('digitalPen', 'FLAT', 5)], desc: '+5 п.п. пробития цифрового сопротивления.',
  },
  {
    id: 'DUAL_H1', name: '«Синхроны»', category: 'MAIN', tags: ['weapon', 'mixed', 'hybrid'], cargoUnits: 2, craftable: true,
    weapon: {
      damage: 55, type: 'KINETIC', intervalMs: 1150,
      packets: [{ type: 'KINETIC', amount: 36 }, { type: 'ENERGY', amount: 19 }],
    },
    effects: [], desc: 'Смешанная атака 36 K + 19 E, каждая половина проходит свою защиту.',
  },

  /* ---------------- 10.2 Offhand (6) ---------------- */
  {
    id: 'SIDEARM_1', name: 'Запасной пистолет', category: 'OFFHAND', tags: ['offhand', 'sidearm', 'kinetic'], cargoUnits: 1, craftable: true,
    weapon: { damage: 18, type: 'KINETIC', intervalMs: 900, sidearmOnly: true },
    effects: [], desc: 'Участвует только в умении «Второй ствол», не в автоатаке.',
  },
  {
    id: 'OFF_SHIELD', name: 'Генератор щита', category: 'OFFHAND', tags: ['offhand', 'shield'], cargoUnits: 1, craftable: true,
    effects: [S('maxShield', 'FLAT', 35, { note: '×D(T)', synScalable: false }), S('shieldRegen', 'FLAT', 1)],
    desc: '+35 щита ×D(T) и +1 щит/с после 4 с без урона.',
  },
  {
    id: 'OFF_CORE_E', name: 'Энергоблок', category: 'OFFHAND', tags: ['offhand', 'energy', 'tech'], cargoUnits: 1, craftable: true,
    effects: [S('techPower', 'FLAT', 12, { note: '×H(T)' }), S('energySkillCostFlat', 'FLAT', 2)],
    desc: '+12 TechPower ×H(T), −2 энергии на энергетические программы.',
  },
  {
    id: 'OFF_CORE_D', name: 'Нейроключ', category: 'OFFHAND', tags: ['offhand', 'digital', 'tech', 'virus'], cargoUnits: 1, craftable: true,
    effects: [S('techPower', 'FLAT', 10, { note: '×H(T)' }), S('virusDuration', 'INCREASED', 10)],
    desc: '+10 TechPower ×H(T), +10% длительности VIRUS.',
  },
  {
    id: 'OFF_TARGET', name: 'Оптическая рамка', category: 'OFFHAND', tags: ['offhand', 'accuracy'], cargoUnits: 1, craftable: true,
    effects: [S('accuracy', 'FLAT', 12), S('armorPen', 'FLAT', 5)], desc: '+12 точности, +5 пробития брони.',
  },
  {
    id: 'OFF_COOL', name: 'Теплосток', category: 'OFFHAND', tags: ['offhand', 'heat', 'cooling'], cargoUnits: 1, craftable: true,
    effects: [S('heatCooling', 'FLAT', 4), S('energyDamage', 'INCREASED', -10)],
    desc: '+4 охлаждения/с, −10% энергетического урона (trade-off).',
  },

  /* ---------------- 10.3 Бронекостюмы (6) ---------------- */
  {
    id: 'ARM_CLOTH', name: 'Городская оболочка', category: 'ARMOR', tags: ['armor', 'evasion'], cargoUnits: 2, craftable: true,
    armorBlock: { hp: 20, shield: 10, armor: 2 }, effects: [S('evasion', 'FLAT', 10)], desc: '+10 уклонения.',
  },
  {
    id: 'ARM_LIGHT', name: 'Курьер', category: 'ARMOR', tags: ['armor', 'speed'], cargoUnits: 2, craftable: true,
    armorBlock: { hp: 40, shield: 15, armor: 4 }, effects: [S('attackSpeed', 'INCREASED', 4)], desc: '+4% скорости атаки.',
  },
  {
    id: 'ARM_MID', name: 'Корпоративный', category: 'ARMOR', tags: ['armor', 'energy'], cargoUnits: 2, craftable: true,
    armorBlock: { hp: 80, shield: 25, armor: 10 }, effects: [S('energyRes', 'FLAT', 10)], desc: '+10 п.п. сопротивления энергии.',
  },
  {
    id: 'ARM_HEAVY', name: 'Бастион', category: 'ARMOR', tags: ['armor', 'heavy'], cargoUnits: 2, craftable: true,
    armorBlock: { hp: 120, shield: 10, armor: 20 }, effects: [S('attackSpeed', 'INCREASED', -10)], desc: '−10% скорости атаки.',
  },
  {
    id: 'ARM_NET', name: 'Сетевая кожа', category: 'ARMOR', tags: ['armor', 'digital'], cargoUnits: 2, craftable: true,
    armorBlock: { hp: 45, shield: 45, armor: 5 }, effects: [S('digitalRes', 'FLAT', 10)], desc: '+10 п.п. цифрового сопротивления.',
  },
  {
    id: 'ARM_HEAT', name: 'Термоконтур', category: 'ARMOR', tags: ['armor', 'heat'], cargoUnits: 2, craftable: true,
    armorBlock: { hp: 65, shield: 35, armor: 8 }, effects: [S('heatCooling', 'FLAT', 3)], desc: '+3 охлаждения/с.',
  },

  /* ---------------- 10.4 Импланты (12) ---------------- */
  {
    id: 'IMP_ARMOR', name: '«Титановая решётка»', category: 'IMPLANT', implantSlot: 'CHEST', neuralCost: 16, tags: ['implant', 'armor'], cargoUnits: 1, craftable: true,
    effects: [S('armor', 'INCREASED', 20, { synScalable: true })], desc: '+20% INCREASED брони.',
  },
  {
    id: 'IMP_HP', name: '«Глубокий резерв»', category: 'IMPLANT', implantSlot: 'CHEST', neuralCost: 12, tags: ['implant', 'hp'], cargoUnits: 1, craftable: true,
    effects: [S('maxHP', 'FLAT', 60, { note: '×D(T)', synScalable: true })], desc: '+60 HP ×D(T).',
  },
  {
    id: 'IMP_REFLEX', name: '«Миоконтур»', category: 'IMPLANT', implantSlot: 'ARMS', neuralCost: 14, tags: ['implant', 'speed'], cargoUnits: 1, craftable: true,
    effects: [S('attackSpeed', 'INCREASED', 12, { synScalable: true })], desc: '+12% скорости атаки.',
  },
  {
    id: 'IMP_CRIT', name: '«Слепая игла»', category: 'IMPLANT', implantSlot: 'HEAD', neuralCost: 16, tags: ['implant', 'crit'], cargoUnits: 1, craftable: true,
    effects: [S('critChance', 'FLAT', 5)], desc: '+5 п.п. шанса крита.',
  },
  {
    id: 'IMP_DATA', name: '«Дешифратор»', category: 'IMPLANT', implantSlot: 'HEAD', neuralCost: 14, tags: ['implant', 'digital'], cargoUnits: 1, craftable: true,
    effects: [S('digitalDamage', 'INCREASED', 18, { synScalable: true })], desc: '+18% цифрового урона.',
  },
  {
    id: 'IMP_HEAT', name: '«Турбопроток»', category: 'IMPLANT', implantSlot: 'CHEST', neuralCost: 15, tags: ['implant', 'heat', 'energy'], cargoUnits: 1, craftable: true,
    effects: [S('heatCooling', 'FLAT', -2, { synScalable: true }), S('energyDamage', 'INCREASED', 20, { synScalable: true })],
    desc: '−2 охлаждения/с, +20% энергетического урона.',
  },
  {
    id: 'IMP_COOL', name: '«Сухой лёд»', category: 'IMPLANT', implantSlot: 'UNIVERSAL', neuralCost: 10, tags: ['implant', 'cooling'], cargoUnits: 1, craftable: true,
    effects: [S('heatCooling', 'FLAT', 5, { synScalable: true }), S('energyDamage', 'INCREASED', -8, { synScalable: true })],
    desc: '+5 охлаждения/с, −8% энергетического урона.',
  },
  {
    id: 'IMP_REGEN', name: '«Периферийный заряд»', category: 'IMPLANT', implantSlot: 'NEURAL', neuralCost: 15, tags: ['implant', 'energy'], cargoUnits: 1, craftable: true,
    effects: [S('energyRegen', 'FLAT', 5, { synScalable: true })], desc: '+5 энергии/с.',
  },
  {
    id: 'IMP_CAP', name: '«Пустой канал»', category: 'IMPLANT', implantSlot: 'NEURAL', neuralCost: 8, tags: ['implant', 'capacity'], cargoUnits: 1, craftable: true,
    effects: [S('neuralCapacity', 'FLAT', 24)], desc: '+24 нейроёмкости (не масштабируется SYN).',
  },
  {
    id: 'IMP_SHIELD', name: '«Эхобарьер»', category: 'IMPLANT', implantSlot: 'CHEST', neuralCost: 16, tags: ['implant', 'shield'], cargoUnits: 1, craftable: true,
    effects: [S('maxShield', 'FLAT', 60, { note: '×D(T)', synScalable: true })], desc: '+60 щита ×D(T).',
  },
  {
    id: 'IMP_DRONE', name: '«Тактовый центр»', category: 'IMPLANT', implantSlot: 'NEURAL', neuralCost: 18, tags: ['implant', 'drone'], cargoUnits: 1, craftable: true,
    effects: [S('droneDamage', 'INCREASED', 20, { synScalable: true })], desc: '+20% урона дронов.',
  },
  {
    id: 'IMP_VIRUS', name: '«Мнемофаг»', category: 'IMPLANT', implantSlot: 'HEAD', neuralCost: 17, tags: ['implant', 'virus', 'digital'], cargoUnits: 1, craftable: true,
    effects: [S('virusDamage', 'INCREASED', 15, { synScalable: true })], desc: '+15% урона статусных цифровых тиков.',
  },

  /* ---------------- 10.5 Дроны (6) ---------------- */
  {
    id: 'DR_GUN', name: '«Оса»', category: 'DRONE', tags: ['drone', 'kinetic'], cargoUnits: 1, craftable: true,
    drone: { hp: 100, armor: 4, shield: 0, damage: 20, intervalMs: 950, type: 'KINETIC', role: 'mark' },
    effects: [], desc: 'Приоритет отмеченной цели.',
  },
  {
    id: 'DR_ARC', name: '«Молния»', category: 'DRONE', tags: ['drone', 'energy'], cargoUnits: 1, craftable: true,
    drone: { hp: 80, armor: 3, shield: 10, damage: 16, intervalMs: 850, type: 'ENERGY', role: 'shock' },
    effects: [{
      type: 'trigger', id: 'DR_ARC_shock', event: 'ON_ATTACK_COUNTER', counterEvery: 5,
      action: { kind: 'applyStatus', status: 'SHOCK', target: 'target' }, desc: 'Каждая 5-я атака накладывает SHOCK.',
    }],
    desc: 'Каждая 5-я атака переносит SHOCK.',
  },
  {
    id: 'DR_MED', name: '«Санитар»', category: 'DRONE', tags: ['drone', 'digital', 'support'], cargoUnits: 1, craftable: true,
    drone: { hp: 120, armor: 4, shield: 10, damage: 6, intervalMs: 1700, type: 'DIGITAL', role: 'medic' },
    effects: [{
      type: 'trigger', id: 'DR_MED_heal', event: 'PERIODIC', periodMs: 10000,
      action: { kind: 'restoreShield', amount: 18 }, desc: '18 щита оператору каждые 10 секунд.',
    }],
    desc: '18 щита оператору каждые 10 с.',
  },
  {
    id: 'DR_EMP', name: '«Фантом»', category: 'DRONE', tags: ['drone', 'digital', 'control'], cargoUnits: 1, craftable: true,
    drone: { hp: 75, armor: 3, shield: 10, damage: 15, intervalMs: 1300, type: 'DIGITAL', role: 'emp' },
    effects: [{
      type: 'trigger', id: 'DR_EMP_interrupt', event: 'PERIODIC', periodMs: 14000,
      action: { kind: 'interrupt' }, desc: 'EMP-перехват каждые 14 секунд.',
    }],
    desc: 'EMP interrupt каждые 14 с.',
  },
  {
    id: 'DR_BULWARK', name: '«Клин»', category: 'DRONE', tags: ['drone', 'kinetic', 'tank'], cargoUnits: 1, craftable: true,
    drone: { hp: 180, armor: 10, shield: 30, damage: 7, intervalMs: 1800, type: 'KINETIC', role: 'bulwark' },
    effects: [], desc: 'Перенаправляет 10% входящего урона на себя (до 20 за попадание).',
  },
  {
    id: 'DR_SWARM', name: '«Рой»', category: 'DRONE', tags: ['drone', 'kinetic', 'swarm'], cargoUnits: 1, craftable: true,
    drone: { hp: 90, armor: 2, shield: 0, damage: 8, intervalMs: 1500, type: 'KINETIC', pellets: 3, role: 'swarm' },
    effects: [], desc: 'Три пакета по 8 с procWeight 0.25 каждый.',
  },

  /* ---------------- 10.6 Транспорт ---------------- */
  {
    id: 'TR_ENGINE_1', name: 'Двигатель «Трасса»', category: 'ENGINE', tags: ['transport', 'engine'], cargoUnits: 1, craftable: true,
    effects: [S('fuelMax', 'FLAT', 0)], desc: '24 топлива, 1 топливо за ребро.',
  },
  {
    id: 'TR_ENGINE_2', name: 'Двигатель «Дальний ход»', category: 'ENGINE', tags: ['transport', 'engine', 'enhanced'], cargoUnits: 1, craftable: true,
    effects: [S('fuelMax', 'FLAT', 8), S('travelDurationLess', 'FLAT', 10)], desc: '32 топлива, −10% времени переезда.',
  },
  {
    id: 'TR_CHASSIS_1', name: 'Корпус «Ржавчина»', category: 'CHASSIS', tags: ['transport', 'chassis'], cargoUnits: 1, craftable: true,
    effects: [], desc: '100 корпуса.',
  },
  {
    id: 'TR_CHASSIS_2', name: 'Корпус «Шёлк»', category: 'CHASSIS', tags: ['transport', 'chassis', 'enhanced'], cargoUnits: 1, craftable: true,
    effects: [S('hullMax', 'FLAT', 30), S('repairCostLess', 'FLAT', -10)], desc: '+30 корпуса, +10% стоимости ремонта.',
  },
  {
    id: 'TR_SCANNER_1', name: 'Приёмник', category: 'SCANNER', tags: ['transport', 'scanner'], cargoUnits: 1, craftable: true,
    effects: [], desc: 'Видит тип соседних узлов.',
  },
  {
    id: 'TR_SCANNER_2', name: 'Сканер «Вектор»', category: 'SCANNER', tags: ['transport', 'scanner', 'enhanced'], cargoUnits: 1, craftable: true,
    effects: [S('scanRange', 'FLAT', 1)], desc: 'Показывает диапазон угроз и добычи на слой дальше.',
  },
  {
    id: 'TR_SERVICE_1', name: 'Набор ремонта', category: 'SERVICE', tags: ['transport', 'service'], cargoUnits: 1, craftable: true,
    effects: [], desc: 'Нет авто-ремонта.',
  },
  {
    id: 'TR_SERVICE_2', name: 'Сервис «Медтех»', category: 'SERVICE', tags: ['transport', 'service', 'enhanced'], cargoUnits: 1, craftable: true,
    effects: [S('repairPower', 'INCREASED', 15)], desc: 'После checkpoint +15% потерянного HP и прочности брони за 5 лома.',
  },
  {
    id: 'TR_CARGO_1', name: 'Отсек 1', category: 'CARGO', tags: ['transport', 'cargo'], cargoUnits: 1, craftable: true,
    effects: [], desc: '20 единиц груза.',
  },
  {
    id: 'TR_CARGO_2', name: 'Отсек 2', category: 'CARGO', tags: ['transport', 'cargo', 'enhanced'], cargoUnits: 1, craftable: true,
    effects: [S('cargoUnits', 'FLAT', 12)], desc: '32 единицы груза.',
  },
  {
    id: 'TR_SUPPORT_1', name: 'Связь', category: 'SUPPORT', tags: ['transport', 'support'], cargoUnits: 1, craftable: true,
    effects: [], desc: 'Нет боевой атаки.',
  },
  {
    id: 'TR_SUPPORT_2', name: 'Релейная батарея', category: 'SUPPORT', tags: ['transport', 'support', 'enhanced'], cargoUnits: 1, craftable: true,
    effects: [{
      type: 'trigger', id: 'TR_SUPPORT_blast', event: 'PERIODIC', periodMs: 25000,
      action: { kind: 'secondaryDamage', basis: 'flat', coefficient: 40, damageType: 'ENERGY', targeting: 'nearest', canProc: false },
      desc: 'ENERGY-залп 40×H(T) каждые 25 секунд, procWeight 0.',
    }],
    desc: 'Один ENERGY-залп 40×H(T) каждые 25 с.',
  },
  /* Материал */
  {
    id: 'MAT_CORE', name: 'Калибровочное ядро', category: 'MATERIAL', tags: ['material', 'core'], cargoUnits: 0, craftable: false,
    effects: [], desc: 'Редкий материал калибровки TechLevel. Группа указана в предмете.',
  },
];

export const ITEM_BY_ID: Record<string, ItemTemplate> = Object.fromEntries(ITEM_TEMPLATES.map((t) => [t.id, t]));

export const MAIN_WEAPONS = ITEM_TEMPLATES.filter((t) => t.category === 'MAIN');
export const OFFHANDS = ITEM_TEMPLATES.filter((t) => t.category === 'OFFHAND');
export const ARMORS = ITEM_TEMPLATES.filter((t) => t.category === 'ARMOR');
export const IMPLANTS = ITEM_TEMPLATES.filter((t) => t.category === 'IMPLANT');
export const DRONES = ITEM_TEMPLATES.filter((t) => t.category === 'DRONE');
export const TRANSPORT = ITEM_TEMPLATES.filter((t) => ['ENGINE', 'CHASSIS', 'SCANNER', 'SERVICE', 'CARGO', 'SUPPORT'].includes(t.category));

export function templatesByCategory(cat: string): ItemTemplate[] {
  return ITEM_TEMPLATES.filter((t) => t.category === cat);
}
