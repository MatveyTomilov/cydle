import type { EffectDef, StatEffect, TreeNodeDef, TriggerEffect } from './types';

const S = (stat: StatEffect['stat'], op: StatEffect['op'], value: number, extra: Partial<StatEffect> = {}): StatEffect =>
  ({ type: 'stat', stat, op, value, ...extra });
const T = (t: Omit<TriggerEffect, 'type'>): TriggerEffect => ({ type: 'trigger', ...t });

type Branch = 'K' | 'H' | 'N' | 'D' | 'S' | 'R';

function n(
  branch: Branch, tier: 1 | 2 | 3 | 4, pos: 'A' | 'B' | 'C' | 'D',
  name: string, effects: EffectDef[], desc: string, keystone = false,
): TreeNodeDef {
  return { id: `${branch}${tier}${pos}`, branch, tier, pos, name, keystone, effects, desc };
}

/** Раздел 14 — 96 узлов ветвей + 4 перекрёстных = 100. */
export const TREE_NODES: TreeNodeDef[] = [
  /* ---------------- K — кинетика ---------------- */
  n('K', 1, 'A', 'Калибровка ствола', [S('kineticDamage', 'INCREASED', 6)], '+6% кинетического урона'),
  n('K', 1, 'B', 'Твёрдый сердечник', [S('armorPen', 'FLAT', 3)], '+3 плоского пробития брони'),
  n('K', 1, 'C', 'Стабилизатор', [S('accuracy', 'FLAT', 4)], '+4 точности'),
  n('K', 1, 'D', 'Рваные кромки', [S('bleedDamage', 'INCREASED', 5)], '+5% урона BLEED'),
  n('K', 2, 'A', 'Лёгкий затвор', [S('attackSpeed', 'INCREASED', 5, { condition: { kind: 'flagTrue', key: 'mainKinetic' } })], '+5% скорости атаки с K-оружием'),
  n('K', 2, 'B', 'Вскрытый шов', [S('kineticDamage', 'INCREASED', 10, { condition: { kind: 'targetStatus', status: 'ARMOR_BREAK' } })], '+10% K-урона по цели с ARMOR_BREAK'),
  n('K', 2, 'C', 'Дробовой картечь', [S('armorPen', 'FLAT', 2), S('kineticDamage', 'INCREASED', 6, { condition: { kind: 'flagTrue', key: 'weaponShotgun' } })], '+2 пробития, +6% урона SHOTGUN'),
  n('K', 2, 'D', 'Глубокий разрез', [S('bleedStackCap', 'FLAT', 1)], '+1 к лимиту стеков BLEED (11)'),
  n('K', 3, 'A', 'Раскол брони', [T({ id: 'K3A', event: 'ON_HIT', chance: 0.12, icdMs: 4000, requireDirect: true, damageTypeFilter: ['KINETIC'], action: { kind: 'applyStatus', status: 'ARMOR_BREAK', stacks: 1, target: 'target' }, desc: '12% шанс прямого K-удара наложить ARMOR_BREAK, ICD 4 с' })], '12% шанс ARMOR_BREAK на прямом K-ударе, ICD 4 с'),
  n('K', 3, 'B', 'Первый контакт', [S('moreKinetic', 'MORE', 1.08, { condition: { kind: 'targetHpAbove', value: 0.8 } })], '+8% MORE K-урона по цели с HP>80%'),
  n('K', 3, 'C', 'Резонанс кромки', [S('critMultiplier', 'FLAT', 0.1, { condition: { kind: 'flagTrue', key: 'mainKinetic' } })], '+0.10 к множителю крита с K-оружием'),
  n('K', 3, 'D', 'Трофейный заряд', [T({ id: 'K3D', event: 'ON_KILL', icdMs: 2000, requireKillType: 'KINETIC', action: { kind: 'restoreEnergy', amount: 4 }, desc: '+4 энергии при K-убийстве, ICD 2 с' })], 'При K-убийстве +4 энергии, ICD 2 с'),
  n('K', 4, 'A', 'Кинетический доминант', [S('moreKinetic', 'MORE', 1.15), S('energyDamage', 'INCREASED', -8)], '+15% MORE K-урона, −8% энергетического урона'),
  n('K', 4, 'B', 'Отдача в щит', [T({ id: 'K4B', event: 'ON_HIT', icdMs: 3000, damageTypeFilter: ['KINETIC'], requireDirect: true, condition: { kind: 'targetStatus', status: 'ARMOR_BREAK', minStacks: 2 }, action: { kind: 'restoreShield', amount: 12 }, desc: 'K-удар по цели с ≥2 ARMOR_BREAK восстанавливает 12 щита' })], 'K-удар по цели с ≥2 ARMOR_BREAK: +12 щита, ICD 3 с'),
  n('K', 4, 'C', 'KEYSTONE: Тройной пробой', [
    S('attackSpeed', 'INCREASED', -10),
    T({ id: 'K4C', event: 'ON_BEFORE_HIT', counterEvery: 3, damageTypeFilter: ['KINETIC'], requireDirect: true, action: { kind: 'packetMod', penMultiplier: 2 }, desc: 'Каждый 3-й прямой K-удар удваивает плоское пробитие' }),
  ], 'Каждый 3-й прямой K-удар удваивает плоское пробитие, но −10% скорости атаки', true),
  n('K', 4, 'D', 'KEYSTONE: Кровавая жатва', [
    S('moreExecute', 'MORE', 1.3, { condition: { kind: 'targetStatus', status: 'BLEED', minStacks: 5 } }),
    S('moreKinetic', 'LESS', 0.15, { condition: { kind: 'targetNoStatus', status: 'BLEED' } }),
  ], 'BLEED≥5: +30% MORE K-добивания (HP цели<30%), но −15% K по цели без кровотечения', true),

  /* ---------------- H — энергетика/нагрев ---------------- */
  n('H', 1, 'A', 'Разогнанный контур', [S('energyDamage', 'INCREASED', 6)], '+6% энергетического урона'),
  n('H', 1, 'B', 'Радиатор', [S('heatCooling', 'FLAT', 2)], '+2 охлаждения/с'),
  n('H', 1, 'C', 'Дополнительная ячейка', [S('maxEnergy', 'FLAT', 10)], '+10 максимума энергии'),
  n('H', 1, 'D', 'Быстрый заряд', [S('energyRegen', 'FLAT', 3)], '+3 энергии/с'),
  n('H', 2, 'A', 'Горячая фаза', [S('moreEnergy', 'MORE', 1.1, { condition: { kind: 'heatAtLeast', value: 60 } })], 'При heat≥60: +10% MORE энергии'),
  n('H', 2, 'B', 'Форсированная продувка', [T({ id: 'H2B', event: 'ON_CAST', skillFilter: ['SK_VENT'], action: { kind: 'changeHeat', amount: -10 }, desc: 'SK_VENT снимает ещё 10 нагрева' })], 'SK_VENT снимает +10 нагрева'),
  n('H', 2, 'C', 'Экономный разряд', [S('skillEnergyCostLess', 'FLAT', 8)], '−8% стоимости энергии программ (минимум 1)'),
  n('H', 2, 'D', 'Полный бак', [S('attackSpeed', 'INCREASED', 8, { condition: { kind: 'energyAtLeast', value: 80 } })], 'При энергии≥80: +8% скорости атаки'),
  n('H', 3, 'A', 'Термощит', [T({ id: 'H3A', event: 'ON_HEAT_FULL', icdMs: 10000, action: { kind: 'tempShield', amount: 20, cap: 20, durationMs: 5000 }, desc: 'Пересечение 100 нагрева даёт 20 временных щитов' })], 'При пересечении heat 100: +20 временных щитов, ICD 10 с'),
  n('H', 3, 'B', 'Плазменный ожог', [T({ id: 'H3B', event: 'ON_CAST', skillFilter: ['SK_PLASMA'], icdMs: 3000, action: { kind: 'applyStatus', status: 'BURN', stacks: 1, target: 'target' }, desc: 'SK_PLASMA накладывает BURN' })], 'SK_PLASMA: +1 BURN, ICD 3 с'),
  n('H', 3, 'C', 'Теплосброс', [T({ id: 'H3C', event: 'ON_KILL', requireKillType: 'ENERGY', action: { kind: 'changeHeat', amount: -15 }, desc: 'После E-убийства −15 нагрева' })], 'После энергетического убийства −15 нагрева'),
  n('H', 3, 'D', 'Аварийный заряд', [T({ id: 'H3D', event: 'ON_HEAT_LOCKOUT_END', action: { kind: 'buff', mods: [S('energyRegen', 'FLAT', 5)], durationMs: 4000 }, desc: 'После lockout +5 энергии/с на 4 с' })], 'После heat lockout: +5 энергии/с на 4 с'),
  n('H', 4, 'A', 'Перегретый реактор', [S('moreEnergy', 'MORE', 1.2, { condition: { kind: 'heatAtLeast', value: 70 } }), S('heatCooling', 'FLAT', -3)], '+20% MORE энергии при heat≥70, −3 охлаждения'),
  n('H', 4, 'B', 'Холодный расчёт', [S('moreSkillDigital', 'MORE', 1.2, { condition: { kind: 'heatAtMost', value: 25 } }), S('energyDamage', 'INCREASED', -10)], 'При heat≤25: +20% MORE цифровых программ, −10% энергии'),
  n('H', 4, 'C', 'KEYSTONE: Импульс перегрева', [T({ id: 'H4C_pulse', event: 'ON_HEAT_FULL', icdMs: 12000, action: { kind: 'secondaryDamage', basis: 'techPower', coefficient: 0.7, damageType: 'ENERGY', targeting: 'allEnemies', canProc: false }, desc: 'heat=100 запускает бесплатный импульс 0.7 TechPower E' })], 'heat=100: импульс 0.7 TechPower E по всем врагам, ICD 12 с, lockout 1 с', true),
  n('H', 4, 'D', 'KEYSTONE: Щитовой форсаж', [T({ id: 'H4D', event: 'ON_BEFORE_HIT', damageTypeFilter: ['ENERGY'], condition: { kind: 'heatAtLeast', value: 80 }, action: { kind: 'packetMod', damageMultiplier: 1.25, consumeShield: 10, requireShield: 10 }, desc: 'E-атака при heat≥80 тратит 10 щита ради +25% MORE' })], 'E-атаки при heat≥80 тратят 10 щита и получают +25% MORE (нужно ≥10 щита)', true),

  /* ---------------- N — нетраннер ---------------- */
  n('N', 1, 'A', 'Оптимизация кода', [S('digitalDamage', 'INCREASED', 6)], '+6% цифрового урона'),
  n('N', 1, 'B', 'Агрессивный штамм', [S('virusDamage', 'INCREASED', 10)], '+10% урона VIRUS'),
  n('N', 1, 'C', 'Тихий цикл', [S('energyRegen', 'FLAT', 2)], '+2 энергии/с'),
  n('N', 1, 'D', 'Файрвол', [S('digitalRes', 'FLAT', 4)], '+4 п.п. цифрового сопротивления'),
  n('N', 2, 'A', 'Стойкая инфекция', [S('virusDuration', 'INCREASED', 16.67, { note: '+1 с к 6 с' })], 'Длительность VIRUS +1 с'),
  n('N', 2, 'B', 'Точный укол', [S('moreDigital', 'MORE', 1.1, { condition: { kind: 'flagTrue', key: 'skill_SK_NEURO' } })], 'SK_NEURO: +10% урона'),
  n('N', 2, 'C', 'Дешёвый перехват', [S('empCostFlat', 'FLAT', 4)], 'SK_EMP: −4 энергии'),
  n('N', 2, 'D', 'Взломанный канал', [S('digitalDamage', 'INCREASED', 10, { condition: { kind: 'targetStatus', status: 'JAM' } })], '+10% прямого D по цели с JAM'),
  n('N', 3, 'A', 'Утечка через вирус', [T({ id: 'N3A', event: 'ON_HIT', icdMs: 6000, requireDirect: true, damageTypeFilter: ['DIGITAL'], condition: { kind: 'targetStatus', status: 'VIRUS' }, action: { kind: 'applyStatus', status: 'SHIELD_LEAK', target: 'target' }, desc: 'Прямой D-удар по заражённой цели накладывает SHIELD_LEAK' })], 'Прямой D-удар по заражённой цели: SHIELD_LEAK, ICD 6 с'),
  n('N', 3, 'B', 'Двойное семя', [T({ id: 'N3B', event: 'ON_CAST', skillFilter: ['SK_SEED'], action: { kind: 'applyStatus', status: 'VIRUS', stacks: 1, target: 'target' }, desc: 'SK_SEED накладывает ещё 1 стек' })], 'SK_SEED: +1 дополнительный стек VIRUS'),
  n('N', 3, 'C', 'Утилизация данных', [T({ id: 'N3C', event: 'ON_KILL', icdMs: 3000, requireKillType: 'DIGITAL', action: { kind: 'restoreEnergy', amount: 8 }, desc: 'D-убийство восстанавливает 8 энергии' })], 'При D-убийстве +8 энергии, ICD 3 с'),
  n('N', 3, 'D', 'Изолированная цель', [S('moreDigital', 'MORE', 1.15, { condition: { kind: 'targetAlone' } })], '+15% MORE D по одиночной цели'),
  n('N', 4, 'A', 'Сверхдетонация', [S('detonateCoefficient', 'FLAT', 0.2), S('virusDamage', 'INCREASED', -10)], 'SK_DETONATE: коэффициент 0.80 вместо 0.60, −10% урона тиков VIRUS'),
  n('N', 4, 'B', 'Цифровая броня', [S('digitalRes', 'FLAT', 15), S('kineticDamage', 'INCREASED', -5)], '+15 п.п. цифрового сопротивления, −5% K-урона'),
  n('N', 4, 'C', 'KEYSTONE: Разносчик', [
    T({ id: 'N4C', event: 'ON_KILL', icdMs: 2000, condition: { kind: 'targetStatus', status: 'VIRUS' }, action: { kind: 'transferVirus', stacks: 2 }, desc: 'Перенос 2 остаточных стеков VIRUS при убийстве' }),
    S('moreDigital', 'LESS', 0.15, { condition: { kind: 'targetAlone' } }),
  ], 'Убийство заражённого переносит 2 стека VIRUS, ICD 2 с; −15% D по одиночной цели', true),
  n('N', 4, 'D', 'KEYSTONE: Двойной перехват', [
    T({ id: 'N4D', event: 'ON_INTERRUPT', icdMs: 15000, action: { kind: 'extraReaction', windowMs: 2000 }, desc: 'Успешный EMP даёт дополнительное reaction-действие' }),
    S('reactionCostMore', 'FLAT', 20),
  ], 'Успешный EMP даёт ещё одно reaction-действие в течение 2 с (ICD 15 с), но +20% стоимости реакций', true),

  /* ---------------- D — дроны ---------------- */
  n('D', 1, 'A', 'Боевые подпрограммы', [S('droneDamage', 'INCREASED', 8)], '+8% урона дронов'),
  n('D', 1, 'B', 'Усиленный каркас', [S('droneHP', 'INCREASED', 10)], '+10% HP дронов'),
  n('D', 1, 'C', 'Синхронное наведение', [S('droneAccuracy', 'FLAT', 5)], '+5 точности дронов'),
  n('D', 1, 'D', 'Ремонтные протоколы', [S('repairPower', 'INCREASED', 5)], '+5% силы ремонта'),
  n('D', 2, 'A', 'Помехоустойчивость', [S('droneJamDurationLess', 'FLAT', 20)], 'Длительность DRONE_JAM −20%'),
  n('D', 2, 'B', 'Дроновый барьер', [S('droneShield', 'INCREASED', 10)], '+10% щита дронов'),
  n('D', 2, 'C', 'Расширенный медпакет', [S('droneMedBonus', 'FLAT', 8)], '«Санитар»: +8 щита за срабатывание'),
  n('D', 2, 'D', 'Разогнанные роторы', [S('droneAttackSpeed', 'INCREASED', 5)], '+5% скорости атаки дронов'),
  n('D', 3, 'A', 'Одиночный охотник', [S('moreDrone', 'MORE', 1.15, { condition: { kind: 'otherDroneDead' } })], '+15% MORE урона дрона, если второй мёртв/отсутствует'),
  n('D', 3, 'B', 'Совместный залп', [S('moreDrone', 'MORE', 1.1, { condition: { kind: 'bothDronesSameTarget' } })], 'Оба дрона по одной цели: +10% MORE урона'),
  n('D', 3, 'C', 'Последний заряд', [T({ id: 'D3C', event: 'ON_DRONE_DEATH', oncePerDrone: true, action: { kind: 'restoreEnergy', amount: 20 }, desc: 'Гибель дрона даёт 20 энергии' })], 'При гибели дрона +20 энергии (раз за дрон за бой)'),
  n('D', 3, 'D', 'Стойкая метка', [S('droneMarkBonusMs', 'FLAT', 2000)], 'Синхрометка держится +2 с'),
  n('D', 4, 'A', 'Роевой приоритет', [S('moreDrone', 'MORE', 1.2), S('moreMain', 'LESS', 0.1)], '+20% MORE урона дронов, −10% урона героя'),
  n('D', 4, 'B', 'Живучий рой', [S('moreDroneHP', 'MORE', 1.25), S('droneDamage', 'INCREASED', -5)], '+25% MORE HP дронов, −5% их урона'),
  n('D', 4, 'C', 'KEYSTONE: Синхрония', [
    T({ id: 'D4C_stack', event: 'PERIODIC', periodMs: 1000, condition: { kind: 'dronesAlive', value: 2 }, action: { kind: 'flag', key: 'synchrony', amount: 1, max: 5 }, desc: 'Два живых дрона копят 1 синхронию/с' }),
    T({ id: 'D4C_spend', event: 'ON_BEFORE_HIT', requireDrone: true, action: { kind: 'spendFlagForDamage', flag: 'synchrony', perStack: 0.1, maxStacks: 5, onlyAtMax: true }, desc: 'На 5 синхронии следующий удар дрона ×1.5 MORE' }),
  ], 'Два живых дрона копят синхронию (макс 5); на максимуме следующий удар ×1.5 MORE и сброс', true),
  n('D', 4, 'D', 'KEYSTONE: Прощальный EMP', [
    T({ id: 'D4D', event: 'ON_DRONE_DEATH', icdMs: 15000, action: { kind: 'secondaryDamage', basis: 'droneTech', coefficient: 0.6, damageType: 'DIGITAL', targeting: 'allEnemies', canProc: false }, desc: 'Гибель дрона: EMP 0.6 droneTechPower D' }),
    S('moreDroneHP', 'LESS', 0.2),
  ], 'Гибель дрона: EMP 0.6 droneTechPower D по всем (ICD 15 с), но −20% HP дронов', true),

  /* ---------------- S — защита ---------------- */
  n('S', 1, 'A', 'Резерв тканей', [S('maxHP', 'INCREASED', 8)], '+8% максимума HP'),
  n('S', 1, 'B', 'Ёмкий барьер', [S('maxShield', 'INCREASED', 8)], '+8% максимума щита'),
  n('S', 1, 'C', 'Композит', [S('armor', 'INCREASED', 6)], '+6% брони'),
  n('S', 1, 'D', 'Диэлектрик', [S('energyRes', 'FLAT', 4)], '+4 п.п. сопротивления энергии'),
  n('S', 2, 'A', 'Восстановление барьера', [S('shieldRegen', 'FLAT', 2)], '+2 щита/с после 4 с без урона'),
  n('S', 2, 'B', 'Экранирование', [S('digitalRes', 'FLAT', 5)], '+5 п.п. цифрового сопротивления'),
  n('S', 2, 'C', 'Дополнительный резерв', [S('maxHP', 'FLAT', 20, { note: '×D(T текущей брони)' })], '+20 HP ×D(T текущей экипировки)'),
  n('S', 2, 'D', 'Плотный барьер', [S('incomingShield', 'LESS', 0.05)], '−5% урона, поглощаемого щитом'),
  n('S', 3, 'A', 'Отдача барьера', [T({ id: 'S3A', event: 'ON_SHIELD_ABSORB', icdMs: 3000, minAmount: 50, action: { kind: 'restoreEnergy', amount: 8 }, desc: 'Щит поглотил ≥50 за удар → +8 энергии' })], 'Щит поглотил ≥50 за один удар: +8 энергии, ICD 3 с'),
  n('S', 3, 'B', 'Порог выживания', [S('incomingAll', 'LESS', 0.1, { condition: { kind: 'hpBelow', value: 0.35 } })], 'При HP<35%: −10% LESS всего входящего урона'),
  n('S', 3, 'C', 'Регенерационный контур', [S('healing', 'INCREASED', 15)], '+15% силы лечения'),
  n('S', 3, 'D', 'Герметизация', [S('shieldLeakDurationLess', 'FLAT', 25)], 'Длительность SHIELD_LEAK −25%'),
  n('S', 4, 'A', 'Тяжёлый каркас', [S('moreMaxHP', 'MORE', 1.15), S('attackSpeed', 'INCREASED', -5)], '+15% MORE максимума HP, −5% скорости атаки'),
  n('S', 4, 'B', 'Реактор барьера', [S('moreMaxShield', 'MORE', 1.2), S('energyRegen', 'INCREASED', -5)], '+20% MORE максимума щита, −5% регенерации энергии'),
  n('S', 4, 'C', 'KEYSTONE: Последний барьер', [
    T({ id: 'S4C', event: 'ON_HP_THRESHOLD', hpThreshold: 0.2, oncePerCombat: true, action: { kind: 'tempShield', amount: 80, cap: 80, durationMs: 5000, scaleWithArmorT: true }, desc: 'HP<20%: 80 временных щитов ×D(T брони) на 5 с' }),
    S('moreDirect', 'LESS', 0.1),
  ], 'HP<20%: 80 временных щитов ×D(T брони) на 5 с, раз за бой; −10% урона', true),
  n('S', 4, 'D', 'KEYSTONE: Зеркальный барьер', [
    T({ id: 'S4D', event: 'ON_SHIELD_ABSORB', icdMs: 3000, action: { kind: 'secondaryDamage', basis: 'consumedShield', coefficient: 0.15, damageType: 'DIGITAL', targeting: 'attacker', canProc: false }, desc: '15% поглощённого щитом урона отражается цифрой' }),
    S('moreMaxShield', 'LESS', 0.1),
  ], 'Поглощение щитом отражает 15% цифровым SECONDARY (ICD 3 с), но −10% максимума щита', true),

  /* ---------------- R — реакция/тактика ---------------- */
  n('R', 1, 'A', 'Точный глаз', [S('accuracy', 'FLAT', 5)], '+5 точности'),
  n('R', 1, 'B', 'Лёгкий шаг', [S('evasion', 'FLAT', 5)], '+5 уклонения'),
  n('R', 1, 'C', 'Быстрые руки', [S('attackSpeed', 'INCREASED', 5)], '+5% скорости атаки'),
  n('R', 1, 'D', 'Готовность реакций', [S('reactionCooldownLess', 'FLAT', 5)], '−5% cooldown реакций'),
  n('R', 2, 'A', 'Кинетический возврат', [T({ id: 'R2A', event: 'ON_DODGE', icdMs: 1000, action: { kind: 'restoreEnergy', amount: 2 }, desc: 'Уклонение даёт 2 энергии' })], 'Успешное уклонение: +2 энергии, ICD 1 с'),
  n('R', 2, 'B', 'Усиленный резонанс', [S('critMultiplier', 'FLAT', 0.08)], '+0.08 к множителю крита'),
  n('R', 2, 'C', 'Экономный барьер', [S('shieldCostFlat', 'FLAT', 5)], 'SK_SHIELD: −5 энергии'),
  n('R', 2, 'D', 'Чтение боя', [S('telegraphBonusMs', 'FLAT', 200)], 'Телеграфы боссов начинаются на 200 мс раньше'),
  n('R', 3, 'A', 'Контрудар', [T({ id: 'R3A', event: 'ON_DODGE', icdMs: 3000, action: { kind: 'buff', mods: [S('moreDirect', 'MORE', 1.12)], durationMs: 5000, consumeOnHit: true }, desc: 'Уклонение усиливает следующую атаку' })], 'Уклонение: следующая атака +12% MORE, ICD 3 с'),
  n('R', 3, 'B', 'Перехват энергии', [T({ id: 'R3B', event: 'ON_INTERRUPT', action: { kind: 'restoreShield', amount: 10 }, desc: 'Успешное прерывание даёт 10 щита' })], 'Успешное прерывание: +10 щита'),
  n('R', 3, 'C', 'Долгая метка', [S('scanMarkBonusMs', 'FLAT', 2000)], 'Метка SK_SCAN держится +2 с'),
  n('R', 3, 'D', 'Пристрелка', [T({ id: 'R3D', event: 'ON_ATTACK_COUNTER', counterEvery: 4, action: { kind: 'buff', mods: [S('accuracy', 'FLAT', 8)], durationMs: 4000 }, desc: '4 удара по одной цели дают +8 точности' })], '4 атаки по одной цели: +8 точности на 4 с'),
  n('R', 4, 'A', 'Смертельный резонанс', [S('moreCritDamage', 'MORE', 1.15), S('critChance', 'FLAT', -8)], '+15% MORE крит. урона, −8 п.п. шанса крита'),
  n('R', 4, 'B', 'Вход в бой', [S('incomingAll', 'LESS', 0.08, { condition: { kind: 'firstSeconds', value: 3 } })], '−8% LESS урона в первые 3 с боя'),
  n('R', 4, 'C', 'KEYSTONE: Аварийный протокол', [T({ id: 'R4C', event: 'ON_COMBAT_START', oncePerCombat: true, action: { kind: 'flag', key: 'emergencyReaction', amount: 1, max: 1 }, desc: 'Одна реакция за бой без энергии' })], 'Раз за бой реакция игнорирует стоимость энергии, но даёт +20 нагрева и +3 с к её cooldown', true),
  n('R', 4, 'D', 'KEYSTONE: Фазовый сдвиг', [
    T({ id: 'R4D', event: 'ON_DODGE', counterEvery: 3, icdMs: 12000, action: { kind: 'reduceCooldown', amountMs: 2000 }, desc: 'Каждое 3-е уклонение освежает ближайшее готовое main-умение' }),
    S('moreMaxHP', 'LESS', 0.1),
  ], 'Каждое 3-е уклонение сокращает CD ближайшего main-умения на 2 с (ICD 12 с), но −10% максимума HP', true),

  /* ---------------- Перекрёстные ---------------- */
  {
    id: 'X1', branch: 'X', tier: 4, pos: 'X', name: 'Термоброня', keystone: false,
    requires: [{ branch: 'H', points: 6 }, { branch: 'S', points: 6 }],
    effects: [T({ id: 'X1', event: 'ON_EFFECT_SHIELD_SPENT', icdMs: 1000, action: { kind: 'tempShield', amount: 0, cap: 25, durationMs: 5000, fromFlag: 'effectShieldSpent', ratio: 0.5 }, desc: 'Половина щитов, потраченных U01/H4D, возвращается временным щитом' })],
    desc: 'Каждый щит, потраченный на U01 или H4D, даёт 0.5 временного щита на 5 с (макс 25), ICD 1 с',
  },
  {
    id: 'X2', branch: 'X', tier: 4, pos: 'X', name: 'Киберрой', keystone: false,
    requires: [{ branch: 'N', points: 6 }, { branch: 'D', points: 6 }],
    effects: [T({ id: 'X2', event: 'ON_HIT', icdMs: 2000, requireDrone: true, requireDirect: true, damageTypeFilter: ['DIGITAL'], condition: { kind: 'targetStatus', status: 'VIRUS' }, action: { kind: 'extendStatus', status: 'VIRUS', ms: 1000, stacks: 1 }, desc: 'Цифровой удар дрона продлевает стек VIRUS' })],
    desc: 'Каждый прямой цифровой удар дрона по заражённой цели продлевает один стек на 1 с, ICD 2 с',
  },
  {
    id: 'X3', branch: 'X', tier: 4, pos: 'X', name: 'Предвидение', keystone: false,
    requires: [{ branch: 'R', points: 6 }, { branch: 'S', points: 6 }],
    effects: [T({ id: 'X3', event: 'ON_ENEMY_TELEGRAPH', action: { kind: 'buff', mods: [S('evasion', 'MORE', 1.2)], durationMs: 1000, maxStacks: 1 }, desc: 'Телеграф опасного каста даёт +20% уклонения' })],
    desc: 'При телеграфе опасного каста: +20% MORE уклонения на 1 с, без стеков',
  },
  {
    id: 'X4', branch: 'X', tier: 4, pos: 'X', name: 'Взломный выстрел', keystone: false,
    requires: [{ branch: 'K', points: 6 }, { branch: 'N', points: 6 }],
    effects: [T({ id: 'X4', event: 'ON_HIT', icdMs: 3000, requireDirect: true, damageTypeFilter: ['KINETIC'], condition: { kind: 'targetStatus', status: 'JAM' }, action: { kind: 'secondaryDamage', basis: 'techPower', coefficient: 0.3, damageType: 'DIGITAL', targeting: 'target', canProc: false }, desc: 'K-удар по цели с JAM добавляет цифровой вторичный пакет' })],
    desc: 'Первый прямой K-удар по цели с JAM добавляет 0.30 TechPower D вторичным пакетом, ICD 3 с',
  },
];

export const TREE_BY_ID: Record<string, TreeNodeDef> = Object.fromEntries(TREE_NODES.map((t) => [t.id, t]));

export const MAX_TREE_POINTS = 60;
export const MAX_KEYSTONES = 2;

export function branchPoints(allocated: string[], branch: string): number {
  return allocated.filter((id) => TREE_BY_ID[id]?.branch === branch).length;
}

export function keystoneCount(allocated: string[]): number {
  return allocated.filter((id) => TREE_BY_ID[id]?.keystone).length;
}

/** Проверка доступности узла по правилам раздела 14. */
export function nodeLockReason(nodeId: string, allocated: string[], availablePoints: number): string | null {
  const node = TREE_BY_ID[nodeId];
  if (!node) return 'Неизвестный узел';
  if (allocated.includes(nodeId)) return 'Уже изучен';
  if (availablePoints <= 0) return 'Нет свободных очков';
  if (node.branch === 'X') {
    for (const req of node.requires ?? []) {
      if (branchPoints(allocated, req.branch) < req.points) return `Нужно ${req.points} очков в ветви ${req.branch}`;
    }
    return null;
  }
  const pts = branchPoints(allocated, node.branch);
  const hasTier = (t: number) => allocated.some((id) => TREE_BY_ID[id]?.branch === node.branch && TREE_BY_ID[id]?.tier === t);
  if (node.tier === 2 && (pts < 2 || !hasTier(1))) return 'Нужно ≥2 очков в ветви и один узел T1';
  if (node.tier === 3 && (pts < 5 || !hasTier(2))) return 'Нужно ≥5 очков в ветви и один узел T2';
  if (node.tier === 4 && (pts < 9 || !hasTier(3))) return 'Нужно ≥9 очков в ветви и один узел T3';
  if (node.keystone && keystoneCount(allocated) >= MAX_KEYSTONES) return 'Достигнут лимит двух keystone';
  return null;
}

/** Дети узла при респке: узлы более высоких тиеров той же ветви, если теряется требование. */
export function dependentsToRemove(nodeId: string, allocated: string[]): string[] {
  const remaining = allocated.filter((id) => id !== nodeId);
  const removed: string[] = [];
  let changed = true;
  while (changed) {
    changed = false;
    for (const id of [...remaining]) {
      const node = TREE_BY_ID[id]!;
      const pts = branchPoints(remaining, node.branch);
      let invalid = false;
      if (node.branch === 'X') {
        invalid = (node.requires ?? []).some((r) => branchPoints(remaining, r.branch) < r.points);
      } else {
        const hasTier = (t: number) => remaining.some((x) => TREE_BY_ID[x]?.branch === node.branch && TREE_BY_ID[x]?.tier === t);
        if (node.tier === 2) invalid = pts < 2 || !hasTier(1);
        if (node.tier === 3) invalid = pts < 5 || !hasTier(2);
        if (node.tier === 4) invalid = pts < 9 || !hasTier(3);
      }
      if (invalid) {
        remaining.splice(remaining.indexOf(id), 1);
        removed.push(id);
        changed = true;
      }
    }
  }
  return removed;
}
