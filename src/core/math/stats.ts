import type { SourceKind, StatusId } from '../types';
import { clamp, finite } from './formula';
import { FORMULA_VERSION, node, type TraceNode } from './trace';

/* ------------------------------------------------------------------ */
/* Реестр характеристик                                                */
/* ------------------------------------------------------------------ */

export type StatId =
  // пулы и защита
  | 'maxHP' | 'maxShield' | 'armor' | 'energyRes' | 'digitalRes' | 'evasion' | 'accuracy'
  | 'critChance' | 'critMultiplier'
  // ресурсы
  | 'maxEnergy' | 'energyRegen' | 'maxHeat' | 'heatCooling' | 'neuralCapacity' | 'shieldRegen'
  // урон (INCREASED %)
  | 'kineticDamage' | 'energyDamage' | 'digitalDamage' | 'mainDamage' | 'allDamage' | 'droneDamage'
  | 'statusDamage' | 'virusDamage' | 'bleedDamage' | 'dotDuration' | 'healing'
  // пробитие
  | 'armorPen' | 'armorPenPercent' | 'energyPen' | 'energyPenPercent' | 'digitalPen' | 'digitalPenPercent'
  // время
  | 'attackSpeed' | 'cooldownRecovery' | 'reactionCooldownLess'
  // множители урона (Π)
  | 'moreKinetic' | 'moreEnergy' | 'moreDigital' | 'moreDirect' | 'moreMain' | 'moreDrone'
  | 'moreSkillDigital' | 'moreSkillEnergy' | 'moreExecute' | 'moreCritDamage' | 'moreAttackSpeed'
  // входящий урон (Π)
  | 'incomingAll' | 'incomingKinetic' | 'incomingEnergy' | 'incomingDigital' | 'incomingShield'
  // технологии
  | 'techPower'
  // дроны
  | 'droneHP' | 'droneShield' | 'droneAccuracy' | 'droneAttackSpeed' | 'repairPower' | 'droneJamDurationLess'
  // прочее
  | 'procMultiplier' | 'extractionChance' | 'bountyCurrency' | 'repairCostLess'
  | 'energySkillCostFlat' | 'skillEnergyCostLess' | 'reactionCostMore' | 'virusDuration'
  | 'bleedStackCap' | 'virusStackCap' | 'droneCooldownMore' | 'telegraphBonusMs'
  | 'empCostFlat' | 'shieldCostFlat' | 'detonateCoefficient' | 'droneMedBonus' | 'droneMarkBonusMs'
  | 'scanMarkBonusMs' | 'shieldLeakDurationLess' | 'moreDroneHP' | 'moreMaxHP' | 'moreMaxShield'
  // транспорт / дорога
  | 'fuelMax' | 'hullMax' | 'cargoUnits' | 'travelDurationLess' | 'scanRange';

export interface StatDef {
  id: StatId;
  name: string;
  unit: string;
  base: number;
  min?: number;
  max?: number;
  /** true → сумма FLAT и clamp, без INCREASED/MORE стадий (crit chance, resistances). */
  additiveOnly?: boolean;
  /** true → значение-множитель: база 1, MORE умножает, LESS уменьшает. */
  multiplier?: boolean;
  integer?: boolean;
  group: 'defense' | 'resource' | 'offense' | 'time' | 'drone' | 'road' | 'meta';
  desc: string;
}

function def(id: StatId, name: string, unit: string, base: number, group: StatDef['group'], desc: string, extra: Partial<StatDef> = {}): StatDef {
  return { id, name, unit, base, group, desc, ...extra };
}

export const STAT_REGISTRY: Record<StatId, StatDef> = {
  maxHP: def('maxHP', 'Максимум HP', 'HP', 300, 'defense', 'Базовое здоровье оператора 300 + снаряжение', { min: 1 }),
  maxShield: def('maxShield', 'Максимум щита', 'щит', 75, 'defense', 'Базовый щит 75 + снаряжение', { min: 0 }),
  armor: def('armor', 'Броня', 'ед.', 5, 'defense', 'Кинетическое снижение = armorEff/(armorEff+100), максимум 85%', { min: 0 }),
  energyRes: def('energyRes', 'Сопротивление энергии', 'п.п.', 0, 'defense', 'Ограничение [-50; 75] п.п.', { additiveOnly: true, min: -50, max: 75 }),
  digitalRes: def('digitalRes', 'Сопротивление цифре', 'п.п.', 0, 'defense', 'Ограничение [-50; 75] п.п.', { additiveOnly: true, min: -50, max: 75 }),
  evasion: def('evasion', 'Уклонение', 'ед.', 20, 'defense', 'pHit = Accuracy/(Accuracy+Evasion), не даёт иммунитета', { min: 0 }),
  accuracy: def('accuracy', 'Точность', 'ед.', 100, 'offense', 'Минимальный шанс попадания 5%', { min: 1 }),
  critChance: def('critChance', 'Шанс крита', '%', 5, 'offense', 'База 5% + плоские пункты, clamp [0; 95]', { additiveOnly: true, min: 0, max: 95 }),
  critMultiplier: def('critMultiplier', 'Множитель крита', '×', 1.5, 'offense', 'База ×1.5, минимум ×1', { min: 1 }),
  maxEnergy: def('maxEnergy', 'Максимум энергии', 'энергия', 100, 'resource', 'Минимум 10', { min: 10 }),
  energyRegen: def('energyRegen', 'Регенерация энергии', '/с', 8, 'resource', 'Восстановление энергии в секунду'),
  maxHeat: def('maxHeat', 'Максимум нагрева', 'нагрев', 100, 'resource', 'Минимум 20; порог перегрева 100', { min: 20 }),
  heatCooling: def('heatCooling', 'Охлаждение', '/с', 5, 'resource', 'Сброс нагрева в секунду', { min: 0 }),
  neuralCapacity: def('neuralCapacity', 'Нейроёмкость', 'ед.', 100, 'resource', 'Слоты конфигурации имплантов', { min: 0 }),
  shieldRegen: def('shieldRegen', 'Регенерация щита', '/с', 0, 'resource', 'Работает после 4 секунд без урона'),
  kineticDamage: def('kineticDamage', 'Кинетический урон', '%', 0, 'offense', 'INCREASED группа kinetic'),
  energyDamage: def('energyDamage', 'Энергетический урон', '%', 0, 'offense', 'INCREASED группа energy'),
  digitalDamage: def('digitalDamage', 'Цифровой урон', '%', 0, 'offense', 'INCREASED группа digital'),
  mainDamage: def('mainDamage', 'Урон основного оружия', '%', 0, 'offense', 'INCREASED группа main'),
  allDamage: def('allDamage', 'Весь урон', '%', 0, 'offense', 'INCREASED группа all'),
  droneDamage: def('droneDamage', 'Урон дронов', '%', 0, 'drone', 'INCREASED группа drone'),
  statusDamage: def('statusDamage', 'Урон статусов', '%', 0, 'offense', 'INCREASED группа status (все DoT)'),
  virusDamage: def('virusDamage', 'Урон VIRUS', '%', 0, 'offense', 'INCREASED группа virus'),
  bleedDamage: def('bleedDamage', 'Урон BLEED', '%', 0, 'offense', 'INCREASED группа bleed'),
  dotDuration: def('dotDuration', 'Длительность DoT', '%', 0, 'offense', 'INCREASED длительности периодического урона'),
  healing: def('healing', 'Сила лечения', '%', 0, 'defense', 'INCREASED лечения'),
  armorPen: def('armorPen', 'Пробитие брони', 'ед.', 0, 'offense', 'Плоское вычитание брони цели', { min: 0 }),
  armorPenPercent: def('armorPenPercent', 'Пробитие брони', '%', 0, 'offense', 'Процентное пробитие, clamp [0;100]', { min: 0, max: 100 }),
  energyPen: def('energyPen', 'Пробитие сопр. энергии', 'п.п.', 0, 'offense', 'Плоское снижение сопротивления', { min: 0 }),
  energyPenPercent: def('energyPenPercent', 'Пробитие сопр. энергии', '%', 0, 'offense', 'Доля от положительного сопротивления', { min: 0, max: 100 }),
  digitalPen: def('digitalPen', 'Пробитие сопр. цифры', 'п.п.', 0, 'offense', 'Плоское снижение сопротивления', { min: 0 }),
  digitalPenPercent: def('digitalPenPercent', 'Пробитие сопр. цифры', '%', 0, 'offense', 'Доля от положительного сопротивления', { min: 0, max: 100 }),
  attackSpeed: def('attackSpeed', 'Скорость атаки', '%', 0, 'time', 'INCREASED; интервал = base/(1+inc/100)/Πmore, min 150 мс'),
  cooldownRecovery: def('cooldownRecovery', 'Восстановление CD', '%', 0, 'time', 'cooldown = base/(1+rate/100), min 250 мс'),
  reactionCooldownLess: def('reactionCooldownLess', 'Сокращение CD реакций', '%', 0, 'time', 'LESS к базовому cooldown реакций', { min: 0, max: 80 }),
  moreKinetic: def('moreKinetic', 'Множитель кинетики', '×', 1, 'offense', 'Независимые множители MORE/LESS', { multiplier: true, min: 0 }),
  moreEnergy: def('moreEnergy', 'Множитель энергии', '×', 1, 'offense', 'Независимые множители MORE/LESS', { multiplier: true, min: 0 }),
  moreDigital: def('moreDigital', 'Множитель цифры', '×', 1, 'offense', 'Независимые множители MORE/LESS', { multiplier: true, min: 0 }),
  moreDirect: def('moreDirect', 'Множитель прямого урона', '×', 1, 'offense', 'Только прямые попадания', { multiplier: true, min: 0 }),
  moreMain: def('moreMain', 'Множитель основного оружия', '×', 1, 'offense', 'Только main-канал', { multiplier: true, min: 0 }),
  moreDrone: def('moreDrone', 'Множитель дронов', '×', 1, 'drone', 'Независимые множители урона дронов', { multiplier: true, min: 0 }),
  moreSkillDigital: def('moreSkillDigital', 'Множитель цифровых программ', '×', 1, 'offense', 'Только SKILL с тегом D', { multiplier: true, min: 0 }),
  moreSkillEnergy: def('moreSkillEnergy', 'Множитель энергетических программ', '×', 1, 'offense', 'Только SKILL с тегом E', { multiplier: true, min: 0 }),
  moreExecute: def('moreExecute', 'Множитель добивания', '×', 1, 'offense', 'Условия по HP цели задаёт эффект', { multiplier: true, min: 0 }),
  moreCritDamage: def('moreCritDamage', 'Множитель крит. урона', '×', 1, 'offense', 'Применяется только к критическим пакетам', { multiplier: true, min: 0 }),
  moreAttackSpeed: def('moreAttackSpeed', 'Множитель скорости атаки', '×', 1, 'time', 'Независимые множители скорости', { multiplier: true, min: 0.01 }),
  incomingAll: def('incomingAll', 'Входящий урон (все типы)', '×', 1, 'defense', 'MORE/LESS получаемого урона', { multiplier: true, min: 0 }),
  incomingKinetic: def('incomingKinetic', 'Входящая кинетика', '×', 1, 'defense', 'MORE/LESS кинетики', { multiplier: true, min: 0 }),
  incomingEnergy: def('incomingEnergy', 'Входящая энергия', '×', 1, 'defense', 'MORE/LESS энергии', { multiplier: true, min: 0 }),
  incomingDigital: def('incomingDigital', 'Входящая цифра', '×', 1, 'defense', 'MORE/LESS цифры', { multiplier: true, min: 0 }),
  incomingShield: def('incomingShield', 'Урон по щиту', '×', 1, 'defense', 'Меняет только часть, поглощённую щитом', { multiplier: true, min: 0 }),
  techPower: def('techPower', 'TechPower (плоский бонус)', 'ед.', 0, 'offense', 'Плоские добавки offhand-фокусов'),
  droneHP: def('droneHP', 'HP дронов', '%', 0, 'drone', 'INCREASED HP дронов'),
  droneShield: def('droneShield', 'Щит дронов', '%', 0, 'drone', 'INCREASED щита дронов'),
  droneAccuracy: def('droneAccuracy', 'Точность дронов', 'ед.', 0, 'drone', 'Плоская точность дронов'),
  droneAttackSpeed: def('droneAttackSpeed', 'Скорость атаки дронов', '%', 0, 'drone', 'INCREASED скорость дронов'),
  repairPower: def('repairPower', 'Сила ремонта', '%', 0, 'drone', 'INCREASED лечения от дронов/сервисов'),
  droneJamDurationLess: def('droneJamDurationLess', 'Сокращение DRONE_JAM', '%', 0, 'drone', 'LESS длительности помех дронам', { min: 0, max: 80 }),
  procMultiplier: def('procMultiplier', 'Множитель проков', '×', 1, 'meta', 'actorProcMultiplier в effectiveChance', { multiplier: true, min: 0 }),
  extractionChance: def('extractionChance', 'Шанс аварийной эвакуации', 'п.п.', 0, 'meta', 'Бонус к рискованной эвакуации'),
  bountyCurrency: def('bountyCurrency', 'Награды охотников', '%', 0, 'meta', 'Только bounty-источники'),
  repairCostLess: def('repairCostLess', 'Скидка на ремонт', '%', 0, 'meta', 'LESS стоимости ремонта металлом', { min: 0, max: 80 }),
  empCostFlat: def('empCostFlat', 'Скидка энергии SK_EMP', 'ед.', 0, 'resource', 'Плоское снижение стоимости перехвата', { min: 0 }),
  shieldCostFlat: def('shieldCostFlat', 'Скидка энергии SK_SHIELD', 'ед.', 0, 'resource', 'Плоское снижение стоимости аварийного щита', { min: 0 }),
  detonateCoefficient: def('detonateCoefficient', 'Коэффициент детонации', '×', 0.6, 'offense', 'Доля остаточного потенциала VIRUS'),
  droneMedBonus: def('droneMedBonus', 'Бонус лечения «Санитара»', 'щит', 0, 'drone', 'Добавка к периодическому лечению дрона'),
  droneMarkBonusMs: def('droneMarkBonusMs', 'Длительность синхрометки', 'мс', 0, 'drone', 'Добавка к длительности метки дрона'),
  scanMarkBonusMs: def('scanMarkBonusMs', 'Длительность метки SK_SCAN', 'мс', 0, 'offense', 'Добавка к длительности метки'),
  shieldLeakDurationLess: def('shieldLeakDurationLess', 'Сокращение SHIELD_LEAK', '%', 0, 'defense', 'LESS длительности утечки щита', { min: 0, max: 80 }),
  moreDroneHP: def('moreDroneHP', 'Множитель HP дронов', '×', 1, 'drone', 'Независимые множители HP дронов', { multiplier: true, min: 0.05 }),
  moreMaxHP: def('moreMaxHP', 'Множитель макс. HP', '×', 1, 'defense', 'Независимые множители HP', { multiplier: true, min: 0.05 }),
  moreMaxShield: def('moreMaxShield', 'Множитель макс. щита', '×', 1, 'defense', 'Независимые множители щита', { multiplier: true, min: 0 }),
  energySkillCostFlat: def('energySkillCostFlat', 'Скидка энергии энергопрограмм', 'ед.', 0, 'resource', 'Плоское снижение стоимости, минимум 1', { min: 0 }),
  skillEnergyCostLess: def('skillEnergyCostLess', 'Снижение стоимости программ', '%', 0, 'resource', 'LESS стоимости энергии программ', { min: 0, max: 60 }),
  reactionCostMore: def('reactionCostMore', 'Удорожание реакций', '%', 0, 'resource', 'MORE стоимости энергии реакций'),
  virusDuration: def('virusDuration', 'Длительность VIRUS', '%', 0, 'offense', 'INCREASED длительности VIRUS'),
  bleedStackCap: def('bleedStackCap', 'Лимит стеков BLEED', 'шт.', 0, 'offense', 'Добавка к базовому лимиту 10', { integer: true }),
  virusStackCap: def('virusStackCap', 'Лимит стеков VIRUS', 'шт.', 0, 'offense', 'Добавка к базовому лимиту 6', { integer: true }),
  droneCooldownMore: def('droneCooldownMore', 'Замедление дронов', '%', 0, 'drone', 'MORE cooldown способностей дронов'),
  telegraphBonusMs: def('telegraphBonusMs', 'Раннее чтение телеграфа', 'мс', 0, 'time', 'Телеграф начинается раньше'),
  fuelMax: def('fuelMax', 'Запас топлива', 'ед.', 24, 'road', 'Базовый бак 24', { min: 0 }),
  hullMax: def('hullMax', 'Прочность корпуса', 'ед.', 100, 'road', 'Базовый корпус 100', { min: 1 }),
  cargoUnits: def('cargoUnits', 'Вместимость груза', 'ед.', 20, 'road', 'Базовый отсек 20', { min: 0 }),
  travelDurationLess: def('travelDurationLess', 'Сокращение переездов', '%', 0, 'road', 'LESS 25 секунд переезда', { min: 0, max: 60 }),
  scanRange: def('scanRange', 'Дальность разведки', 'слоёв', 0, 'road', 'Дополнительные раскрытые слои', { min: 0, integer: true }),
};

export const STAT_IDS = Object.keys(STAT_REGISTRY) as StatId[];

/* ------------------------------------------------------------------ */
/* Условия                                                             */
/* ------------------------------------------------------------------ */

export type Condition =
  | { kind: 'always' }
  | { kind: 'hpBelow'; value: number }
  | { kind: 'hpAbove'; value: number }
  | { kind: 'shieldBelow'; value: number }
  | { kind: 'energyAtLeast'; value: number }
  | { kind: 'energyBelow'; value: number }
  | { kind: 'heatAtLeast'; value: number }
  | { kind: 'heatAtMost'; value: number }
  | { kind: 'heatLockout' }
  | { kind: 'targetStatus'; status: StatusId; minStacks?: number }
  | { kind: 'targetNoStatus'; status: StatusId }
  | { kind: 'targetHpBelow'; value: number }
  | { kind: 'targetHpAbove'; value: number }
  | { kind: 'targetIsBoss' }
  | { kind: 'targetNotBoss' }
  | { kind: 'targetMechanical' }
  | { kind: 'targetAlone' }
  | { kind: 'enemiesAtLeast'; value: number }
  | { kind: 'dronesAlive'; value: number }
  | { kind: 'otherDroneDead' }
  | { kind: 'bothDronesSameTarget' }
  | { kind: 'firstSeconds'; value: number }
  | { kind: 'afterSeconds'; value: number }
  | { kind: 'flagAtLeast'; key: string; value: number }
  | { kind: 'flagTrue'; key: string }
  | { kind: 'hasUnique'; id: string }
  | { kind: 'not'; inner: Condition }
  | { kind: 'all'; inner: Condition[] }
  | { kind: 'any'; inner: Condition[] };

export interface ActorView {
  hp: number;
  maxHP: number;
  shield: number;
  maxShield: number;
  energy: number;
  heat: number;
  statuses: Partial<Record<StatusId, number>>;
  isBoss?: boolean;
  isMechanical?: boolean;
  isDrone?: boolean;
}

export interface StatContext {
  self?: ActorView;
  target?: ActorView;
  enemiesAlive?: number;
  dronesAlive?: number;
  otherDroneDead?: boolean;
  bothDronesSameTarget?: boolean;
  timeMs?: number;
  heatLockout?: boolean;
  flags?: Record<string, number>;
  uniques?: string[];
}

export const EMPTY_CONTEXT: StatContext = {};

export function conditionText(c: Condition): string {
  switch (c.kind) {
    case 'always': return 'всегда';
    case 'hpBelow': return `HP < ${Math.round(c.value * 100)}%`;
    case 'hpAbove': return `HP > ${Math.round(c.value * 100)}%`;
    case 'shieldBelow': return `щит < ${Math.round(c.value * 100)}%`;
    case 'energyAtLeast': return `энергия ≥ ${c.value}`;
    case 'energyBelow': return `энергия < ${c.value}`;
    case 'heatAtLeast': return `нагрев ≥ ${c.value}`;
    case 'heatAtMost': return `нагрев ≤ ${c.value}`;
    case 'heatLockout': return 'перегрев (lockout)';
    case 'targetStatus': return `цель имеет ${c.status}${c.minStacks ? ` ≥${c.minStacks}` : ''}`;
    case 'targetNoStatus': return `цель без ${c.status}`;
    case 'targetHpBelow': return `HP цели < ${Math.round(c.value * 100)}%`;
    case 'targetHpAbove': return `HP цели > ${Math.round(c.value * 100)}%`;
    case 'targetIsBoss': return 'цель — босс';
    case 'targetNotBoss': return 'цель не босс';
    case 'targetMechanical': return 'цель механическая';
    case 'targetAlone': return 'цель одна';
    case 'enemiesAtLeast': return `врагов ≥ ${c.value}`;
    case 'dronesAlive': return `живых дронов ≥ ${c.value}`;
    case 'otherDroneDead': return 'второй дрон мёртв/отсутствует';
    case 'bothDronesSameTarget': return 'оба дрона бьют одну цель';
    case 'firstSeconds': return `первые ${c.value} с боя`;
    case 'afterSeconds': return `после ${c.value} с боя`;
    case 'flagAtLeast': return `${c.key} ≥ ${c.value}`;
    case 'flagTrue': return `${c.key} активно`;
    case 'hasUnique': return `экипирован ${c.id}`;
    case 'not': return `НЕ (${conditionText(c.inner)})`;
    case 'all': return c.inner.map(conditionText).join(' И ');
    case 'any': return c.inner.map(conditionText).join(' ИЛИ ');
  }
}

export function evalCondition(c: Condition | undefined, ctx: StatContext): boolean {
  if (!c || c.kind === 'always') return true;
  const s = ctx.self;
  const t = ctx.target;
  switch (c.kind) {
    case 'hpBelow': return !!s && s.maxHP > 0 && s.hp / s.maxHP < c.value;
    case 'hpAbove': return !!s && s.maxHP > 0 && s.hp / s.maxHP > c.value;
    case 'shieldBelow': return !!s && (s.maxShield <= 0 || s.shield / s.maxShield < c.value);
    case 'energyAtLeast': return !!s && s.energy >= c.value;
    case 'energyBelow': return !!s && s.energy < c.value;
    case 'heatAtLeast': return !!s && s.heat >= c.value;
    case 'heatAtMost': return !!s && s.heat <= c.value;
    case 'heatLockout': return !!ctx.heatLockout;
    case 'targetStatus': return !!t && (t.statuses[c.status] ?? 0) >= (c.minStacks ?? 1);
    case 'targetNoStatus': return !!t && (t.statuses[c.status] ?? 0) === 0;
    case 'targetHpBelow': return !!t && t.maxHP > 0 && t.hp / t.maxHP < c.value;
    case 'targetHpAbove': return !!t && t.maxHP > 0 && t.hp / t.maxHP > c.value;
    case 'targetIsBoss': return !!t?.isBoss;
    case 'targetNotBoss': return !!t && !t.isBoss;
    case 'targetMechanical': return !!t?.isMechanical;
    case 'targetAlone': return (ctx.enemiesAlive ?? 1) <= 1;
    case 'enemiesAtLeast': return (ctx.enemiesAlive ?? 0) >= c.value;
    case 'dronesAlive': return (ctx.dronesAlive ?? 0) >= c.value;
    case 'otherDroneDead': return !!ctx.otherDroneDead;
    case 'bothDronesSameTarget': return !!ctx.bothDronesSameTarget;
    case 'firstSeconds': return (ctx.timeMs ?? 0) <= c.value * 1000;
    case 'afterSeconds': return (ctx.timeMs ?? 0) >= c.value * 1000;
    case 'flagAtLeast': return (ctx.flags?.[c.key] ?? 0) >= c.value;
    case 'flagTrue': return (ctx.flags?.[c.key] ?? 0) > 0;
    case 'hasUnique': return (ctx.uniques ?? []).includes(c.id);
    case 'not': return !evalCondition(c.inner, ctx);
    case 'all': return c.inner.every((x) => evalCondition(x, ctx));
    case 'any': return c.inner.some((x) => evalCondition(x, ctx));
  }
}

/** Сигнатура активных условий — ключ кеша листа характеристик. */
export function conditionSignature(mods: Modifier[], ctx: StatContext): string {
  let sig = '';
  for (const m of mods) {
    if (!m.condition || m.condition.kind === 'always') continue;
    if (evalCondition(m.condition, ctx)) sig += m.id + ';';
  }
  return sig;
}

/* ------------------------------------------------------------------ */
/* Модификаторы                                                        */
/* ------------------------------------------------------------------ */

export type ModOp = 'BASE' | 'FLAT' | 'INCREASED' | 'MORE' | 'LESS' | 'OVERRIDE' | 'CAP' | 'FLOOR';

export interface Modifier {
  id: string;
  sourceId: string;
  sourceName: string;
  sourceKind: SourceKind;
  stat: StatId;
  op: ModOp;
  /** FLAT/INCREASED/CAP/FLOOR — число; MORE — множитель (1.2); LESS — доля снятия (0.15). */
  value: number;
  stackGroup?: string;
  condition?: Condition;
  stage?: number;
  synScalable?: boolean;
  note?: string;
}

export function mod(
  stat: StatId,
  op: ModOp,
  value: number,
  source: { id: string; name: string; kind: SourceKind },
  extra: Partial<Modifier> = {},
): Modifier {
  return {
    id: extra.id ?? `${source.id}:${stat}:${op}:${extra.stage ?? 0}`,
    sourceId: source.id,
    sourceName: source.name,
    sourceKind: source.kind,
    stat,
    op,
    value,
    ...extra,
  };
}

export interface StatResult {
  statId: StatId;
  value: number;
  unit: string;
  trace: TraceNode;
  contextFingerprint: string;
}

export interface ConversionDef {
  id: string;
  from: StatId;
  to: StatId;
  ratio: number;
  sourceId: string;
  sourceName: string;
  sourceKind: SourceKind;
  condition?: Condition;
  policy: 'snapshot' | 'live';
  stage: number;
}

export type StatSheet = Record<StatId, number>;
export type StatResults = Record<StatId, StatResult>;

export interface ModBundle {
  mods: Modifier[];
  byStat: Map<StatId, Modifier[]>;
  conversions: ConversionDef[];
}

export function bundle(mods: Modifier[], conversions: ConversionDef[] = []): ModBundle {
  const byStat = new Map<StatId, Modifier[]>();
  for (const m of mods) {
    const arr = byStat.get(m.stat);
    if (arr) arr.push(m);
    else byStat.set(m.stat, [m]);
  }
  return { mods, byStat, conversions };
}

/**
 * Единый pipeline: (base + Σflat) × (1 + ΣincreasedГруппы/100) × Πmore → conversions → caps/floors.
 * Все промежуточные значения сохраняются в CalcTrace без округления.
 */
export function computeStat(
  statId: StatId,
  b: ModBundle,
  ctx: StatContext = EMPTY_CONTEXT,
  precomputed?: Partial<StatSheet>,
  fingerprint = '',
): StatResult {
  const d = STAT_REGISTRY[statId];
  const list = b.byStat.get(statId) ?? [];
  const children: TraceNode[] = [];

  let base = d.base;
  const overrides = list.filter((m) => m.op === 'OVERRIDE' && evalCondition(m.condition, ctx));
  if (overrides.length) {
    const chosen = overrides[overrides.length - 1]!;
    base = chosen.value;
    children.push(node('BASE', 'база (override)', base, {
      sourceId: chosen.sourceId, sourceName: chosen.sourceName, sourceKind: chosen.sourceKind,
      unit: d.unit, localizedExplanation: `База переопределена: ${chosen.sourceName}`, inputs: [chosen.value],
    }));
  } else {
    children.push(node('BASE', 'база', base, {
      sourceId: `base:${statId}`, sourceName: d.name, sourceKind: 'base', unit: d.unit,
      localizedExplanation: d.desc, inputs: [base],
    }));
  }
  for (const m of list.filter((x) => x.op === 'BASE' && evalCondition(x.condition, ctx))) {
    base += m.value;
    children.push(node('ADD', 'база', base, {
      sourceId: m.sourceId, sourceName: m.sourceName, sourceKind: m.sourceKind, unit: d.unit,
      inputs: [m.value], conditionPredicate: m.condition ? conditionText(m.condition) : undefined,
      conditionActive: true, localizedExplanation: `${m.sourceName}: +${m.value} к базе`,
    }));
  }

  let flatSum = 0;
  for (const m of list.filter((x) => x.op === 'FLAT')) {
    const active = evalCondition(m.condition, ctx);
    if (active) flatSum += m.value;
    children.push(node('ADD', 'плоские', m.value, {
      sourceId: m.sourceId, sourceName: m.sourceName, sourceKind: m.sourceKind, unit: d.unit,
      inputs: [m.value], conditionPredicate: m.condition ? conditionText(m.condition) : undefined,
      conditionActive: active, tags: m.synScalable ? ['SYN_SCALABLE'] : undefined,
      localizedExplanation: `${m.sourceName}: ${m.value >= 0 ? '+' : ''}${m.value} ${d.unit}${m.note ? ` (${m.note})` : ''}`,
    }));
  }
  let value = base + flatSum;
  const afterFlat = value;
  children.push(node('SUM', 'плоские', afterFlat, {
    sourceId: `sum:${statId}`, sourceName: 'База + плоские', unit: d.unit, inputs: [base, flatSum],
    localizedExplanation: `${base} + ${flatSum} = ${afterFlat}`,
  }));

  if (!d.additiveOnly && !d.multiplier) {
    const groups = new Map<string, { sum: number; members: Modifier[] }>();
    for (const m of list.filter((x) => x.op === 'INCREASED')) {
      const active = evalCondition(m.condition, ctx);
      const g = m.stackGroup ?? statId;
      if (!groups.has(g)) groups.set(g, { sum: 0, members: [] });
      const entry = groups.get(g)!;
      entry.members.push(m);
      if (active) entry.sum += m.value;
      children.push(node('ADD', `складывающиеся % [${g}]`, m.value, {
        sourceId: m.sourceId, sourceName: m.sourceName, sourceKind: m.sourceKind, unit: '%',
        inputs: [m.value], conditionPredicate: m.condition ? conditionText(m.condition) : undefined,
        conditionActive: active, localizedExplanation: `${m.sourceName}: +${m.value}% (группа ${g})`,
      }));
    }
    for (const [g, entry] of groups) {
      const factor = 1 + entry.sum / 100;
      value *= factor;
      children.push(node('MULTIPLY', `складывающиеся % [${g}]`, value, {
        sourceId: `group:${g}`, sourceName: `Группа ${g}`, unit: '×', inputs: [entry.sum, factor],
        localizedExplanation: `Сумма группы ${g}: ${entry.sum}% → ×${factor}`,
      }));
    }
    for (const m of list.filter((x) => x.op === 'MORE' || x.op === 'LESS')) {
      const active = evalCondition(m.condition, ctx);
      const factor = m.op === 'MORE' ? m.value : 1 - clamp(m.value, 0, 1);
      if (active) value *= factor;
      children.push(node('MULTIPLY', 'независимые множители', factor, {
        sourceId: m.sourceId, sourceName: m.sourceName, sourceKind: m.sourceKind, unit: '×',
        inputs: [m.value, factor], conditionPredicate: m.condition ? conditionText(m.condition) : undefined,
        conditionActive: active,
        localizedExplanation: `${m.sourceName}: ${m.op === 'MORE' ? `×${m.value} MORE` : `−${m.value * 100}% LESS`}`,
      }));
    }
  } else if (d.multiplier) {
    for (const m of list.filter((x) => x.op === 'MORE' || x.op === 'LESS' || x.op === 'INCREASED')) {
      const active = evalCondition(m.condition, ctx);
      const factor = m.op === 'MORE' ? m.value : m.op === 'LESS' ? 1 - clamp(m.value, 0, 1) : 1 + m.value / 100;
      if (active) value *= factor;
      children.push(node('MULTIPLY', 'независимые множители', factor, {
        sourceId: m.sourceId, sourceName: m.sourceName, sourceKind: m.sourceKind, unit: '×',
        inputs: [m.value, factor], conditionPredicate: m.condition ? conditionText(m.condition) : undefined,
        conditionActive: active,
        localizedExplanation: `${m.sourceName}: ${m.op === 'MORE' ? `×${m.value} MORE` : m.op === 'LESS' ? `−${m.value * 100}% LESS` : `+${m.value}%`}`,
      }));
    }
    for (const m of list.filter((x) => x.op === 'FLAT')) {
      const active = evalCondition(m.condition, ctx);
      if (active) value += m.value;
      children.push(node('ADD', 'плоские', m.value, {
        sourceId: m.sourceId, sourceName: m.sourceName, sourceKind: m.sourceKind, unit: d.unit,
        conditionPredicate: m.condition ? conditionText(m.condition) : undefined, conditionActive: active,
        localizedExplanation: `${m.sourceName}: +${m.value}`,
      }));
    }
  }

  // Конверсии в эту характеристику (топологически отсортированы вызывающим).
  for (const conv of b.conversions.filter((c) => c.to === statId)) {
    const active = evalCondition(conv.condition, ctx);
    const srcValue = precomputed?.[conv.from] ?? computeStat(conv.from, b, ctx, undefined, fingerprint).value;
    const add = active ? srcValue * conv.ratio : 0;
    value += add;
    children.push(node('CONVERT', 'конверсия', add, {
      sourceId: conv.sourceId, sourceName: conv.sourceName, sourceKind: conv.sourceKind, unit: d.unit,
      inputs: [srcValue, conv.ratio, add], conditionPredicate: conv.condition ? conditionText(conv.condition) : undefined,
      conditionActive: active, snapshot: conv.policy === 'snapshot',
      localizedExplanation: `${conv.sourceName}: ${conv.ratio} × ${conv.from} (${srcValue}) = ${add}`,
    }));
  }

  const beforeClamp = value;
  let lo = d.min ?? -Infinity;
  let hi = d.max ?? Infinity;
  for (const m of list.filter((x) => x.op === 'CAP')) if (evalCondition(m.condition, ctx)) hi = Math.min(hi, m.value);
  for (const m of list.filter((x) => x.op === 'FLOOR')) if (evalCondition(m.condition, ctx)) lo = Math.max(lo, m.value);
  value = clamp(value, lo, hi);
  if (d.integer) value = Math.round(value);
  value = finite(value, d.base);
  if (beforeClamp !== value || lo !== -Infinity || hi !== Infinity) {
    children.push(node('CLAMP', 'ограничение', value, {
      sourceId: `cap:${statId}`, sourceName: 'Пределы реестра', unit: d.unit, inputs: [beforeClamp, lo, hi],
      localizedExplanation: `Ограничение [${lo === -Infinity ? '−∞' : lo}; ${hi === Infinity ? '∞' : hi}] → ${value}`,
    }));
  }

  const trace = node('SUM', 'итог', value, {
    id: `stat:${statId}`, sourceId: statId, sourceName: d.name, unit: d.unit,
    inputs: [base, flatSum], children,
    localizedExplanation: `${d.name} = ${value} ${d.unit}`,
  });
  return { statId, value, unit: d.unit, trace, contextFingerprint: fingerprint };
}

/** Порядок вычисления с учётом графа конверсий (циклы запрещены). */
export function conversionOrder(conversions: ConversionDef[]): StatId[] {
  const deps = new Map<StatId, Set<StatId>>();
  for (const c of conversions) {
    if (!deps.has(c.to)) deps.set(c.to, new Set());
    deps.get(c.to)!.add(c.from);
  }
  const order: StatId[] = [];
  const visiting = new Set<StatId>();
  const done = new Set<StatId>();
  const visit = (id: StatId, path: string[]) => {
    if (done.has(id)) return;
    if (visiting.has(id)) throw new Error(`Цикл конверсий: ${[...path, id].join(' → ')}`);
    visiting.add(id);
    for (const dep of deps.get(id) ?? []) visit(dep, [...path, id]);
    visiting.delete(id);
    done.add(id);
    order.push(id);
  };
  for (const id of STAT_IDS) visit(id, []);
  return order;
}

export function resolveStats(b: ModBundle, ctx: StatContext = EMPTY_CONTEXT, order?: StatId[]): StatResults {
  const sig = conditionSignature(b.mods, ctx);
  const seq = order ?? conversionOrder(b.conversions);
  const sheet: Partial<StatSheet> = {};
  const out = {} as StatResults;
  for (const id of seq) {
    const r = computeStat(id, b, ctx, sheet, sig);
    sheet[id] = r.value;
    out[id] = r;
  }
  return out;
}

export function sheetOf(results: StatResults): StatSheet {
  const out = {} as StatSheet;
  for (const id of STAT_IDS) out[id] = results[id]?.value ?? STAT_REGISTRY[id].base;
  return out;
}

export function emptySheet(): StatSheet {
  const out = {} as StatSheet;
  for (const id of STAT_IDS) out[id] = STAT_REGISTRY[id].base;
  return out;
}

export const MATH_VERSION = FORMULA_VERSION;
