import type { BiomeDef } from './types';

/** Раздел 16.2 — шесть биомов с реальными механическими условиями. */
export const BIOMES: BiomeDef[] = [
  {
    id: 'B01', name: 'Неоновая магистраль', desc: '+10% шанс сервисного узла, обычная погода.',
    enemies: ['E01', 'E02', 'E04', 'E05', 'E11', 'E22'], lootTags: ['weapon', 'speed'], uniques: ['U06', 'U13', 'U15'],
    serviceBonus: 0.1,
  },
  {
    id: 'B02', name: 'Корпоративный периметр', desc: '+4 розыска за ELITE, +10% кредитных наград.',
    enemies: ['E03', 'E04', 'E08', 'E12', 'E16', 'E09'], lootTags: ['armor', 'shield'], uniques: ['U04', 'U10', 'U11'],
    wantedElite: 4, creditsBonus: 0.1,
  },
  {
    id: 'B03', name: 'Ржавые верфи', desc: '−20% стоимости ремонта, +10% шанс турельной встречи.',
    enemies: ['E01', 'E06', 'E08', 'E09', 'E10', 'E15', 'E20'], lootTags: ['drone', 'craft'], uniques: ['U05', 'U16'],
    repairCostMult: 0.8, turretBonus: 0.1,
  },
  {
    id: 'B04', name: 'Слепая сеть', desc: 'Цифровой урон врагов +10%, награды данными +20%.',
    enemies: ['E10', 'E13', 'E14', 'E15', 'E21', 'E24'], lootTags: ['digital', 'virus'], uniques: ['U03', 'U08', 'U09', 'U12', 'U17'],
    enemyDigitalBonus: 0.1, dataBonus: 0.2,
  },
  {
    id: 'B05', name: 'Термический пояс', desc: 'Охлаждение всех участников −2/с (минимум 0), вес ENERGY-предметов +20%.',
    enemies: ['E17', 'E18', 'E19', 'E23'], lootTags: ['heat', 'energy'], uniques: ['U01', 'U07', 'U14'],
    coolingPenalty: 2, energyWeightBonus: 0.2,
  },
  {
    id: 'B06', name: 'Нулевая зона', desc: 'Аномальный модификатор встречи, разведка раскрывает на слой меньше.',
    enemies: ['E20', 'E21', 'E22', 'E23', 'E24', 'E13'], lootTags: ['unique', 'conversion'], uniques: ['U02', 'U18'],
    anomaly: true, revealPenalty: 1,
  },
];

export const BIOME_BY_ID: Record<string, BiomeDef> = Object.fromEntries(BIOMES.map((b) => [b.id, b]));

/** Кампания: жёстко заданные биомы d1..d12 (раздел 16.2). */
export const CAMPAIGN_BIOMES: Record<number, string> = {
  1: 'B01', 2: 'B03', 3: 'B02', 4: 'B01',
  5: 'B04', 6: 'B03', 7: 'B05', 8: 'B04',
  9: 'B06', 10: 'B02', 11: 'B05', 12: 'B06',
};

export const CAMPAIGN_ACTS = [
  { act: 1, name: 'Прорыв', from: 1, to: 4, desc: 'Обучение, первая сборка, устранение координатора блокпостов.' },
  { act: 2, name: 'Перехват', from: 5, to: 8, desc: 'Развитые фракции и дроны, новая логистика, перехват второй подсети.' },
  { act: 3, name: 'Сердце', from: 9, to: 12, desc: 'Угроза автономного управления, сложные контрмеханики, CORE_12.' },
];

export function campaignBiome(depth: number, roll: number): string {
  if (CAMPAIGN_BIOMES[depth]) return CAMPAIGN_BIOMES[depth]!;
  const idx = Math.floor(roll * BIOMES.length) % BIOMES.length;
  return BIOMES[idx]!.id;
}
