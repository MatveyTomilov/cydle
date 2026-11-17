import type { DamageType, StatusId } from '../types';

export interface StatusDef {
  id: StatusId;
  name: string;
  damageType?: DamageType;
  durationMs: number;
  tickMs?: number;
  /** доля от snapshot-величины за тик */
  tickFraction?: number;
  snapshotFrom: 'rawDamage' | 'techPower' | 'none';
  maxStacks: number;
  refresh: boolean;
  independentStacks: boolean;
  desc: string;
  harmful: boolean;
}

export const STATUS_DEFS: Record<StatusId, StatusDef> = {
  BLEED: { id: 'BLEED', name: 'Кровотечение', damageType: 'KINETIC', durationMs: 4000, tickMs: 1000, tickFraction: 0.03, snapshotFrom: 'rawDamage', maxStacks: 10, refresh: false, independentStacks: true, harmful: true, desc: 'Кинетический DoT 4 с, 1 тик/с, 3% raw-урона наложившей атаки, до 10 независимых стеков.' },
  BURN: { id: 'BURN', name: 'Горение', damageType: 'ENERGY', durationMs: 5000, tickMs: 1000, tickFraction: 0.05, snapshotFrom: 'rawDamage', maxStacks: 5, refresh: false, independentStacks: true, harmful: true, desc: 'Энергетический DoT 5 с, 5% raw-урона за тик, до 5 стеков.' },
  VIRUS: { id: 'VIRUS', name: 'Вирус', damageType: 'DIGITAL', durationMs: 6000, tickMs: 1000, tickFraction: 0.06, snapshotFrom: 'techPower', maxStacks: 6, refresh: false, independentStacks: true, harmful: true, desc: 'Цифровой DoT 6 с, 6% snapshot TechPower за тик, до 6 стеков.' },
  ARMOR_BREAK: { id: 'ARMOR_BREAK', name: 'Разлом брони', durationMs: 5000, snapshotFrom: 'none', maxStacks: 3, refresh: false, independentStacks: true, harmful: true, desc: '−10 плоской брони за стек на 5 с, до 3 стеков.' },
  JAM: { id: 'JAM', name: 'Помехи', durationMs: 3000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: true, desc: 'Цифровые cooldown +30% на 3 с, обновляется.' },
  SHOCK: { id: 'SHOCK', name: 'Шок', durationMs: 1000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: true, desc: 'Скорость действий −30% на 1 с, обновляется.' },
  DRONE_JAM: { id: 'DRONE_JAM', name: 'Помехи дронам', durationMs: 2000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: true, desc: 'Эффективность дронов −50% на 2 с.' },
  SHIELD_LEAK: { id: 'SHIELD_LEAK', name: 'Утечка щита', durationMs: 4000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: true, desc: 'Восстановление щита −30% на 4 с.' },
  STUN: { id: 'STUN', name: 'Оглушение', durationMs: 800, snapshotFrom: 'none', maxStacks: 1, refresh: false, independentStacks: false, harmful: true, desc: 'Остановка windup/recovery на 0.8 с; боссы получают 50% длительности; повторный ICD 3 с.' },
  MARK: { id: 'MARK', name: 'Метка', durationMs: 6000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: true, desc: 'Следующий удар по цели наносит +30% урона.' },
  PHASE: { id: 'PHASE', name: 'Фаза', durationMs: 8000, snapshotFrom: 'none', maxStacks: 3, refresh: true, independentStacks: false, harmful: false, desc: 'Стеки фазы от уклонений.' },
  SYNCHRONY: { id: 'SYNCHRONY', name: 'Синхрония', durationMs: 999000, snapshotFrom: 'none', maxStacks: 5, refresh: true, independentStacks: false, harmful: false, desc: 'Синхрония двух дронов.' },
  CHARGE: { id: 'CHARGE', name: 'Заряд оболочки', durationMs: 999000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: false, desc: 'Накопленный заряд из поглощённого щитом урона.' },
  LONG_PULSE: { id: 'LONG_PULSE', name: 'Долгий импульс', durationMs: 999000, snapshotFrom: 'none', maxStacks: 6, refresh: true, independentStacks: false, harmful: false, desc: 'Накопленные стеки импульса.' },
  OVERCLOCK: { id: 'OVERCLOCK', name: 'Форсаж', durationMs: 8000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: false, desc: '+20% скорости атаки и +5 нагрева за автоатаку.' },
  GUARD: { id: 'GUARD', name: 'Дефлектор', durationMs: 2000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: false, desc: '−20% входящего кинетического урона.' },
  SCAN_MARK: { id: 'SCAN_MARK', name: 'Слабое место', durationMs: 6000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: true, desc: '+12% MORE прямого урона по отмеченной цели.' },
  DRONE_MARK: { id: 'DRONE_MARK', name: 'Синхрометка', durationMs: 5000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: true, desc: '+15 точности дронам по этой цели.' },
  CONTROLLED: { id: 'CONTROLLED', name: 'Перехват', durationMs: 4000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: true, desc: 'Цель наносит 40% обычного урона и не даёт лут.' },
  BERSERK: { id: 'BERSERK', name: 'Ярость', durationMs: 999000, snapshotFrom: 'none', maxStacks: 2, refresh: true, independentStacks: false, harmful: false, desc: '+15% MORE урона за стек после гибели союзника.' },
  REGEN_BUFF: { id: 'REGEN_BUFF', name: 'Регенерация', durationMs: 4000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: false, desc: 'Временное усиление регенерации.' },
  EVASION_BUFF: { id: 'EVASION_BUFF', name: 'Предвидение', durationMs: 1000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: false, desc: '+20% уклонения во время телеграфа.' },
  ACC_BUFF: { id: 'ACC_BUFF', name: 'Пристрелка', durationMs: 4000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: false, desc: '+8 точности после серии ударов.' },
  DMG_BUFF: { id: 'DMG_BUFF', name: 'Усиление', durationMs: 5000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: false, desc: 'Временное усиление урона.' },
  SHIELD_REGEN_BUFF: { id: 'SHIELD_REGEN_BUFF', name: 'Щитовой отклик', durationMs: 3000, snapshotFrom: 'none', maxStacks: 1, refresh: true, independentStacks: false, harmful: false, desc: '+10 щита/с.' },
};

export function statusName(id: StatusId): string {
  return STATUS_DEFS[id]?.name ?? id;
}

export const STATUS_RU_SHORT: Record<string, string> = {
  BLEED: 'КРВ', BURN: 'ГОР', VIRUS: 'ВИР', ARMOR_BREAK: 'БРН', JAM: 'ПОМ', SHOCK: 'ШОК',
  DRONE_JAM: 'ДРП', SHIELD_LEAK: 'УТЧ', STUN: 'ОГЛ', MARK: 'МЕТ', SCAN_MARK: 'СЛБ', DRONE_MARK: 'СИН',
  CONTROLLED: 'ПЕР', BERSERK: 'ЯРО', OVERCLOCK: 'ФОР', GUARD: 'ДЕФ',
};
