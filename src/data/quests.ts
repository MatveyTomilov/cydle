import type { ContractDef, QuestDef } from './types';

/** Раздел 20.2 — шесть трёхстадийных цепочек. */
export const QUESTS: QuestDef[] = [
  {
    id: 'Q01', name: 'Потерянный сигнал', faction: 'F_CHOIR', biome: 'B04', minDepth: 3,
    desc: 'Автономный ИИ у перевёрнутого транспорта ищет, кому довериться.',
    stages: [
      {
        stage: 1, name: 'Находка', text: 'У перевёрнутого транспорта мигает автономный ИИ.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Установить в сервис', desc: 'F_CHOIR +5, F_VANTA −5. Цепочка продолжается.', reputation: { F_CHOIR: 5, F_VANTA: -5 }, questAdvance: true },
          { id: 'B', label: 'Продать VANTA', desc: 'F_VANTA +5, +20 кредитов. Альтернативное завершение.', reputation: { F_VANTA: 5 }, gains: { CREDITS: 20 }, scaled: true, special: 'questAltComplete' },
        ],
      },
      {
        stage: 2, name: 'Повреждённый ретранслятор', text: 'В слепой сети нужно открыть повреждённый ретранслятор.', biome: 'B04', requirement: { kind: 'visitBiome', biome: 'B04' },
        choices: [
          { id: 'A', label: 'Открыть (−10 данных)', desc: 'Чертёж OFF_CORE_D, +8 розыска.', cost: { DATA: 10 }, wanted: 8, special: 'schematic:OFF_CORE_D', questAdvance: true },
          { id: 'B', label: 'Отключить ИИ', desc: '+10 лома. Квест завершается.', gains: { SCRAP: 10 }, scaled: true, special: 'questAltComplete' },
        ],
      },
      {
        stage: 3, name: 'Кому достанется ИИ', text: 'Последнее решение: спрятать или выдать.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Спрятать ИИ', desc: 'F_CHOIR +15, открывается целевой контракт U09.', reputation: { F_CHOIR: 15 }, special: 'signalContract:U09' },
          { id: 'B', label: 'Выдать корпорации', desc: 'F_VANTA +15, открывается целевой контракт U04.', reputation: { F_VANTA: 15 }, special: 'signalContract:U04' },
        ],
      },
    ],
  },
  {
    id: 'Q02', name: 'Мёртвый курьер', faction: 'F_ECHO', biome: 'B01', minDepth: 2,
    desc: 'Контейнер мёртвого курьера нужно доставить в ржавые верфи за ≤3 новых сектора.',
    stages: [
      {
        stage: 1, name: 'Контейнер', text: 'В кабине курьера запечатанный контейнер.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Взять контейнер', desc: '+5 розыска. Доставка в B03 за ≤3 сектора.', wanted: 5, questAdvance: true },
          { id: 'B', label: 'Отказаться', desc: '+8 кредитов. Квест завершается.', gains: { CREDITS: 8 }, scaled: true, special: 'questAltComplete' },
        ],
      },
      {
        stage: 2, name: 'Доставка', text: 'Верфи принимают контейнер, но можно и вскрыть его.', biome: 'B03', requirement: { kind: 'visitBiome', biome: 'B03' }, deadlineSectors: 3,
        choices: [
          { id: 'A', label: 'Доставить', desc: 'F_ECHO +10.', reputation: { F_ECHO: 10 }, questAdvance: true },
          { id: 'B', label: 'Вскрыть', desc: '+20 данных, F_ECHO −10. Квест завершается.', gains: { DATA: 20 }, scaled: true, reputation: { F_ECHO: -10 }, special: 'questAltComplete' },
        ],
      },
      {
        stage: 3, name: 'Судьба данных', text: 'Данные курьера можно очистить или продать.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Очистить (−8 данных)', desc: 'Чертёж OFF_TARGET.', cost: { DATA: 8 }, special: 'schematic:OFF_TARGET' },
          { id: 'B', label: 'Продать', desc: '+35 кредитов, F_ECHO −5.', gains: { CREDITS: 35 }, scaled: true, reputation: { F_ECHO: -5 } },
        ],
      },
    ],
  },
  {
    id: 'Q03', name: 'Долг механика', faction: 'F_RUST', biome: 'B03', minDepth: 2,
    desc: 'Мастер верфей просит помощь с долгом и техником-перебежчиком.',
    stages: [
      {
        stage: 1, name: 'Долг', text: 'Мастер просит 10 лома в счёт долга.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Дать 10 лома', desc: 'F_RUST +6.', cost: { SCRAP: 10 }, reputation: { F_RUST: 6 }, questAdvance: true },
          { id: 'B', label: 'Выкупить инструмент', desc: '+10 кредитов. Квест завершается.', gains: { CREDITS: 10 }, scaled: true, special: 'questAltComplete' },
        ],
      },
      {
        stage: 2, name: 'Техник-перебежчик', text: 'Элитный техник E09 держит склад запчастей.', biome: 'B03', requirement: { kind: 'killElite', enemyId: 'E09' },
        choices: [
          { id: 'A', label: 'Устранить техника', desc: 'Гарантированный RARE-дрон текущего T и F_RUST +6.', reputation: { F_RUST: 6 }, grantItem: { category: 'DRONE', rarity: 'RARE' }, questAdvance: true },
          { id: 'B', label: 'Купить двигатель', desc: 'Запасной двигатель за 20×R(d) кредитов.', special: 'buyEngine', questAdvance: true },
        ],
      },
      {
        stage: 3, name: 'Расплата', text: 'Мастер предлагает выбор благодарности.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Доступ к сервису', desc: 'Открывает +15% ремонта корпуса на checkpoint.', special: 'serviceUpgrade' },
          { id: 'B', label: 'Калибровочное ядро', desc: '+1 ядро текущей группы.', special: 'grantCore' },
        ],
      },
    ],
  },
  {
    id: 'Q04', name: 'Чужая броня', faction: 'F_VANTA', biome: 'B02', minDepth: 3,
    desc: 'Корпоративный код доступа к броне гражданского форпоста.',
    stages: [
      {
        stage: 1, name: 'Код доступа', text: 'На блокпосте лежит корпоративный код доступа.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Захватить код', desc: '+10 розыска, +10 данных.', wanted: 10, gains: { DATA: 10 }, scaled: true, questAdvance: true },
          { id: 'B', label: 'Передать VANTA', desc: 'F_VANTA +8. Квест завершается.', reputation: { F_VANTA: 8 }, special: 'questAltComplete' },
        ],
      },
      {
        stage: 2, name: 'Щитовик', text: 'Элитный корпоративный щитовик E12 охраняет склад брони.', biome: 'B02', requirement: { kind: 'killElite', enemyId: 'E12' },
        choices: [
          { id: 'A', label: 'Устранить щитовика', desc: 'Редкий бронекостюм текущего T.', grantItem: { category: 'ARMOR', rarity: 'RARE' }, questAdvance: true },
          { id: 'B', label: 'Заплатить 25 кредитов', desc: 'Купить оборудование.', cost: { CREDITS: 25 }, grantItem: { category: 'ARMOR', rarity: 'MODIFIED' }, questAdvance: true },
        ],
      },
      {
        stage: 3, name: 'Кому защита', text: 'Протокол брони можно отдать форпосту или продать.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Защитить форпост', desc: 'F_RUST +10, чертёж ARM_MID.', reputation: { F_RUST: 10 }, special: 'schematic:ARM_MID' },
          { id: 'B', label: 'Продать протокол', desc: 'F_VANTA +10, +35 кредитов.', reputation: { F_VANTA: 10 }, gains: { CREDITS: 35 }, scaled: true },
        ],
      },
    ],
  },
  {
    id: 'Q05', name: 'Термальный шрам', faction: 'F_CHOIR', biome: 'B05', minDepth: 6,
    desc: 'Реактор термического пояса оставляет шрам на сети.',
    stages: [
      {
        stage: 1, name: 'Реактор', text: 'Повреждённый реактор ещё излучает данные.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Исследовать', desc: '−10 корпуса, +12 данных.', hull: -10, gains: { DATA: 12 }, scaled: true, questAdvance: true },
          { id: 'B', label: 'Уничтожить', desc: '+12 лома. Квест завершается.', gains: { SCRAP: 12 }, scaled: true, special: 'questAltComplete' },
        ],
      },
      {
        stage: 2, name: 'Тепловая проверка', text: 'Победить элитный реактор E19 или пережить три боя в B05.', biome: 'B05', requirement: { kind: 'killElite', enemyId: 'E19' },
        choices: [
          { id: 'A', label: 'Забрать термо-модуль', desc: '+1 ENERGY-предмет текущего T.', grantItem: { tag: 'energy', rarity: 'MODIFIED' }, questAdvance: true },
          { id: 'B', label: 'Взять кредиты', desc: '+10 кредитов.', gains: { CREDITS: 10 }, scaled: true, questAdvance: true },
        ],
      },
      {
        stage: 3, name: 'Кому данные', text: 'Термо-данные ценны и для Хора, и для VANTA.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Передать F_CHOIR', desc: '+12 репутации, целевой контракт U14.', reputation: { F_CHOIR: 12 }, special: 'signalContract:U14' },
          { id: 'B', label: 'Передать VANTA', desc: '+12 репутации, целевой контракт U07.', reputation: { F_VANTA: 12 }, special: 'signalContract:U07' },
        ],
      },
    ],
  },
  {
    id: 'Q06', name: 'Забытая граница', faction: 'F_ECHO', biome: 'B06', minDepth: 9,
    desc: 'Старый сенсор нулевой зоны хранит карту аномалий.',
    stages: [
      {
        stage: 1, name: 'Сенсор', text: 'Сенсор можно снять за 15 данных.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Снять сенсор (−15 данных)', desc: 'Ранний доступ к аномальному модификатору.', cost: { DATA: 15 }, flag: 'earlyAnomaly', questAdvance: true },
          { id: 'B', label: 'Отказаться', desc: '+10 кредитов. Квест завершается.', gains: { CREDITS: 10 }, scaled: true, special: 'questAltComplete' },
        ],
      },
      {
        stage: 2, name: 'Аномальный маршрут', text: 'Провести аномальный маршрут с дополнительной угрозой.', biome: 'B06', requirement: { kind: 'anomaly' },
        choices: [
          { id: 'A', label: 'Пройти маршрут', desc: '−5 розыска, если выжили.', wanted: -5, questAdvance: true },
          { id: 'B', label: 'Эвакуироваться', desc: 'Квест приостанавливается до следующего раза.', special: 'questPause' },
        ],
      },
      {
        stage: 3, name: 'Карта границы', text: 'Карту можно отдать Эхо или оставить себе.', requirement: { kind: 'none' },
        choices: [
          { id: 'A', label: 'Отдать F_ECHO', desc: '+12 репутации, целевой контракт U18.', reputation: { F_ECHO: 12 }, special: 'signalContract:U18' },
          { id: 'B', label: 'Оставить гаражу', desc: '+1 дополнительный предпросмотр аномалий в B06.', special: 'anomalyPreview' },
        ],
      },
    ],
  },
];

export const QUEST_BY_ID: Record<string, QuestDef> = Object.fromEntries(QUESTS.map((q) => [q.id, q]));

/** Раздел 21 — контракты. */
export const CONTRACT_TEMPLATES: ContractDef[] = [
  { id: 'CT_HUNT', kind: 'HUNT', name: 'Охота на элиту', desc: 'Победить указанную элиту в целевом биоме.', targetBiome: 'B01', rewardCredits: 30, rewardItem: { rarity: 'RARE' } },
  { id: 'CT_TECH', kind: 'TECH', name: 'Технический сигнал', desc: 'Найти CACHE или ANOMALY в целевом биоме и завершить его выбор.', targetBiome: 'B04', rewardData: 15, rewardItem: { rarity: 'MODIFIED', tag: 'tech' } },
  { id: 'CT_ESCORT', kind: 'ESCORT', name: 'Сопровождение', desc: 'Завершить ≥2 боя, Wanted≤40 и добраться до checkpoint с топливом ≥3.', targetBiome: 'B03', rewardCredits: 50, rewardReputation: { F_RUST: 8 } },
];

export const CONTRACT_BY_ID: Record<string, ContractDef> = Object.fromEntries(CONTRACT_TEMPLATES.map((c) => [c.id, c]));
