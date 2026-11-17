import type { EscalationModDef, GarageObjectDef, MutationDef, StatEffect } from './types';

const S = (stat: StatEffect['stat'], op: StatEffect['op'], value: number, extra: Partial<StatEffect> = {}): StatEffect =>
  ({ type: 'stat', stat, op, value, ...extra });

/** Раздел 15 — 12 временных мутаций выезда. */
export const MUTATIONS: MutationDef[] = [
  {
    id: 'MUT_CHAIN', name: 'Цепной разряд', benefit: 'Прямая E-атака даёт вторичный пакет 0.3 TechPower E по соседней цели (ICD 2 с)', cost: '−10% прямого E-урона', tags: ['energy'],
    effects: [
      S('moreEnergy', 'LESS', 0.1),
      { type: 'trigger', id: 'MUT_CHAIN', event: 'ON_HIT', icdMs: 2000, requireDirect: true, damageTypeFilter: ['ENERGY'], action: { kind: 'secondaryDamage', basis: 'techPower', coefficient: 0.3, damageType: 'ENERGY', targeting: 'otherEnemy', canProc: false }, desc: 'Цепь по соседней цели' },
    ],
  },
  { id: 'MUT_VIRUS', name: 'Разносчик', benefit: 'Убийство заражённого переносит 1 стек VIRUS (ICD 2 с)', cost: '−15% D по одиночной цели', tags: ['digital', 'virus'],
    effects: [
      S('moreDigital', 'LESS', 0.15, { condition: { kind: 'targetAlone' } }),
      { type: 'trigger', id: 'MUT_VIRUS', event: 'ON_KILL', icdMs: 2000, condition: { kind: 'targetStatus', status: 'VIRUS' }, action: { kind: 'transferVirus', stacks: 1 }, desc: 'Перенос одного стека' },
    ] },
  { id: 'MUT_SWARM', name: 'Роевой приказ', benefit: 'Два дрона по одной отмеченной цели: +25% MORE урона дронов', cost: '+20% cooldown дронов', tags: ['drone'],
    effects: [S('moreDrone', 'MORE', 1.25, { condition: { kind: 'bothDronesSameTarget' } }), S('droneCooldownMore', 'FLAT', 20)] },
  { id: 'MUT_HEAT', name: 'Форсаж нагрева', benefit: '+15% MORE E при heat≥70', cost: 'Нагрев растёт на 30% быстрее, охлаждение −2/с', tags: ['heat', 'energy'],
    effects: [S('moreEnergy', 'MORE', 1.15, { condition: { kind: 'heatAtLeast', value: 70 } }), S('heatCooling', 'FLAT', -2)] },
  { id: 'MUT_SAFE', name: 'Броневой резерв', benefit: '+25% MORE максимума HP', cost: '−15% урона основного оружия', tags: ['defense'],
    effects: [S('moreMaxHP', 'MORE', 1.25), S('moreMain', 'LESS', 0.15)] },
  { id: 'MUT_RISK', name: 'Ставка на риск', benefit: '+25% количества предметов на элитных узлах', cost: '−20% максимума щита', tags: ['loot'],
    effects: [S('moreMaxShield', 'LESS', 0.2)] },
  { id: 'MUT_FUEL', name: 'Топливный резерв', benefit: '+3 топлива на каждом checkpoint', cost: '+5 розыска после босса', tags: ['road'], effects: [] },
  { id: 'MUT_GHOST', name: 'Призрачный шаг', benefit: '+15 уклонения', cost: '−10% K-урона', tags: ['evasion'],
    effects: [S('evasion', 'FLAT', 15), S('kineticDamage', 'INCREASED', -10)] },
  { id: 'MUT_REGEN', name: 'Машинное эхо', benefit: '+3 энергии/с', cost: '+2 нагрева за каждое умение', tags: ['energy'],
    effects: [S('energyRegen', 'FLAT', 3)] },
  { id: 'MUT_BLEED', name: 'Кровавый контур', benefit: '+2 к лимиту стеков BLEED', cost: '−12% урона прочих DoT', tags: ['bleed', 'kinetic'],
    effects: [S('bleedStackCap', 'FLAT', 2), S('statusDamage', 'INCREASED', -12), S('bleedDamage', 'INCREASED', 12)] },
  { id: 'MUT_WARD', name: 'Цифровой оберег', benefit: '−20% MORE входящего D-урона', cost: '+10% MORE входящего K-урона', tags: ['defense', 'digital'],
    effects: [S('incomingDigital', 'LESS', 0.2), S('incomingKinetic', 'MORE', 1.1)] },
  { id: 'MUT_CRIT', name: 'Критический резонанс', benefit: '×1.30 MORE крит. урона', cost: '−5 п.п. шанса крита', tags: ['crit'],
    effects: [S('moreCritDamage', 'MORE', 1.3), S('critChance', 'FLAT', -5)] },
];

export const MUTATION_BY_ID: Record<string, MutationDef> = Object.fromEntries(MUTATIONS.map((m) => [m.id, m]));

/** Раздел 21 — восемь модификаторов эскалации. */
export const ESCALATION_MODS: EscalationModDef[] = [
  { id: 'WANTED_PLUS', name: 'Розыск+', benefit: '+15% кредитных наград', cost: '+5 розыска за элиту', effects: [], worldFlags: { wantedPerElite: 5, creditsMult: 1.15 } },
  { id: 'HUNT_FAST', name: 'Быстрая охота', benefit: '+15% количества предметов', cost: 'Windup тяжёлых кастов −20% (минимум 600 мс)', effects: [], worldFlags: { itemQuantity: 0.15, enemyWindupMult: 0.8 } },
  { id: 'REPAIR_RARE', name: 'Дефицит ремонта', benefit: '+10% лома', cost: 'На один REPAIR-узел меньше в секторе', effects: [], worldFlags: { scrapMult: 1.1, repairNodes: -1 } },
  { id: 'SCAN_DARK', name: 'Тёмный эфир', benefit: '+10% данных', cost: '−1 уровень раскрытия узлов', effects: [], worldFlags: { dataMult: 1.1, reveal: -1 } },
  { id: 'DRONE_WAR', name: 'Война дронов', benefit: '+15% количества добычи', cost: 'Элиты могут получать DRONE_JAM', effects: [], worldFlags: { itemQuantity: 0.15, eliteAntiDrone: 1 } },
  { id: 'HEAT_FOG', name: 'Тепловой туман', benefit: '+10% вес ENERGY-предметов', cost: 'Охлаждение в бою −2/с (минимум 0)', effects: [S('heatCooling', 'FLAT', -2)], worldFlags: { energyWeight: 0.1 } },
  { id: 'SHIELD_BREAK', name: 'Взлом щитов', benefit: '+10% шанс RARE (за счёт COMMON)', cost: 'Элиты получают +10 плоского пробития', effects: [], worldFlags: { rareShift: 0.1, elitePen: 10 } },
  { id: 'LONG_RUN', name: 'Долгий тракт', benefit: 'Босс даёт +25% количества предметов', cost: 'Переезды +15 с', effects: [], worldFlags: { travelAdd: 15000, bossQuantity: 0.25 } },
];

export const ESCALATION_BY_ID: Record<string, EscalationModDef> = Object.fromEntries(ESCALATION_MODS.map((m) => [m.id, m]));

/** Раздел 22.3 — восемь объектов гаража. */
export const GARAGE_OBJECTS: GarageObjectDef[] = [
  { id: 'WORKSHOP', name: 'Мастерская', desc: 'Ремонт, разбор, крафт и модификация предметов.', levels: ['Ремонт и разбор', 'Крафт базовых предметов и изменение ролла', 'Повышение tier и добавление аффикса'] },
  { id: 'NEUROLAB', name: 'Нейролаборатория', desc: 'Импланты и нейроёмкость.', levels: ['Чтение имплантов', '5-й слот импланта (после d5)', '6-й слот импланта (после d8)'], gate: [{ object: 'sector', value: 5 }, { object: 'sector', value: 9 }] },
  { id: 'SERVER', name: 'Сервер тактики', desc: 'Редактор тактики и архив боёв.', levels: ['Редактирование тактики', '5 сохранённых профилей', 'Экспорт трасс и архив реплеев'], extraData: 10 },
  { id: 'HANGAR', name: 'Ангар', desc: 'Дроны и их обслуживание.', levels: ['Старт с DR_GUN', 'Второй слот дрона (после d6)', '−20% стоимости ремонта дронов'], gate: [{ object: 'sector', value: 6 }] },
  { id: 'MARKET', name: 'Рынок', desc: 'Предложения перед выездом.', levels: ['3 стартовых предложения', '5 ротационных предложений каждый выезд', '+1 тематическое целевое предложение'] },
  { id: 'INTEL', name: 'Разведка', desc: 'Раскрытие дорожной карты.', levels: ['Тип соседних узлов', 'Диапазон наград и угроз', 'Ещё один слой известной карты'] },
  { id: 'GARAGE_MED', name: 'Медотсек', desc: 'Восстановление оператора и корпуса.', levels: ['Ремонт и подъём после смерти', '−50% стоимости подъёма', '100% корпуса/HP при старте за ceil(8×R(d)) кредитов'] },
  { id: 'CALIBRATOR', name: 'Калибратор', desc: 'Повышение TechLevel предметов.', levels: ['Калибровка до открытого форпоста', '−10% стоимости лома', 'Пакетная калибровка двух предметов'], extraData: 5 },
];

export const GARAGE_BY_ID: Record<string, GarageObjectDef> = Object.fromEntries(GARAGE_OBJECTS.map((g) => [g.id, g]));

export const GARAGE_MAX_LEVEL = 3;

/** Цена перехода l → l+1 (раздел 22.3). */
export function garageUpgradeCost(objectId: string, currentLevel: number, maxForpost: number, startDepth: number) {
  const R = (d: number) => Math.pow(1 + 0.06 * Math.max(0, d - 1), 1.4);
  const scale = R(maxForpost + 1);
  const def = GARAGE_BY_ID[objectId]!;
  const credits = Math.ceil((40 + 25 * currentLevel) * scale);
  const scrap = Math.ceil((15 + 10 * currentLevel) * scale);
  let data = 0;
  if (def.extraData && currentLevel >= 1) {
    data = objectId === 'CALIBRATOR' ? Math.ceil(5 * R(startDepth)) : def.extraData;
  }
  return { credits, scrap, data };
}
