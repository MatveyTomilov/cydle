import type { GameEventDef } from './types';

/** Раздел 20.1 — 24 одношаговых события, каждое является реальным выбором. */
export const EVENTS: GameEventDef[] = [
  {
    id: 'EV01', name: 'Разобранный дрон', text: 'На обочине лежит остов боевого дрона. Питание ещё живо.',
    choices: [
      { id: 'A', label: 'Восстановить (−5 лома)', desc: 'Потратить 5 лома и получить дрона «Оса» в незакреплённый груз.', cost: { SCRAP: 5 }, grantItem: { templateId: 'DR_GUN', rarity: 'COMMON' } },
      { id: 'B', label: 'Разобрать', desc: '+8 лома.', gains: { SCRAP: 8 }, scaled: true },
    ],
  },
  {
    id: 'EV02', name: 'Блокпост', text: 'Корпоративный блокпост требует пропуск или данные.',
    choices: [
      { id: 'A', label: 'Взломать', desc: '+12 данных, +10 розыска, F_ECHO +5.', gains: { DATA: 12 }, scaled: true, wanted: 10, reputation: { F_ECHO: 5 } },
      { id: 'B', label: 'Оплатить проход (−10 кредитов)', desc: '−10 кредитов, −5 розыска.', cost: { CREDITS: 10 }, wanted: -5 },
    ],
  },
  {
    id: 'EV03', name: 'Тихая заправка', text: 'Автоматическая заправка ещё работает, но принимает только кредиты.',
    choices: [
      { id: 'A', label: 'Заправиться (−10 кредитов)', desc: '+5 топлива за 10 кредитов.', cost: { CREDITS: 10 }, fuel: 5 },
      { id: 'B', label: 'Забрать без оплаты', desc: '+5 топлива, +12 розыска.', fuel: 5, wanted: 12 },
    ],
  },
  {
    id: 'EV04', name: 'Полевой хирург', text: 'Подпольный хирург предлагает стабилизацию.',
    choices: [
      { id: 'A', label: 'Лечение (−12 кредитов)', desc: 'Восстановить 50% потерянного HP.', cost: { CREDITS: 12 }, healMissingFraction: 0.5 },
      { id: 'B', label: 'Обобрать кабинет', desc: '+8 лома, +5 розыска.', gains: { SCRAP: 8 }, scaled: true, wanted: 5 },
    ],
  },
  {
    id: 'EV05', name: 'Контракт крови', text: 'Кто-то платит за голову местной элиты.',
    choices: [
      { id: 'A', label: 'Взять контракт', desc: 'Следующий ELITE-узел даёт дополнительный RARE-предмет.', flag: 'huntElite', nextCombat: { extraRareRoll: true } },
      { id: 'B', label: 'Отказаться', desc: '+5 данных разведки.', gains: { DATA: 5 }, scaled: true },
    ],
  },
  {
    id: 'EV06', name: 'Слепой терминал', text: 'Терминал хранит карту ближайших узлов.',
    choices: [
      { id: 'A', label: 'Скачать карту (−5 данных)', desc: 'Раскрыть 3 следующих узла, F_ECHO +4.', cost: { DATA: 5 }, reveal: 3, reputation: { F_ECHO: 4 } },
      { id: 'B', label: 'Вскрыть и продать', desc: '+18 кредитов, F_ECHO −4.', gains: { CREDITS: 18 }, scaled: true, reputation: { F_ECHO: -4 } },
    ],
  },
  {
    id: 'EV07', name: 'Сгоревшая мастерская', text: 'Обугленный бокс с инструментом и остатками корпуса.',
    choices: [
      { id: 'A', label: 'Вынести лом', desc: '+12 лома, −10% корпуса.', gains: { SCRAP: 12 }, scaled: true, hull: -10 },
      { id: 'B', label: 'Починить корпус (−8 лома)', desc: '+25 корпуса за 8 лома.', cost: { SCRAP: 8 }, hull: 25 },
    ],
  },
  {
    id: 'EV08', name: 'Контрабандист', text: 'Контрабандист предлагает долю за молчание.',
    choices: [
      { id: 'A', label: 'Взять долю', desc: '+20 кредитов, +6 розыска, F_RUST +3.', gains: { CREDITS: 20 }, scaled: true, wanted: 6, reputation: { F_RUST: 3 } },
      { id: 'B', label: 'Сдать груз VANTA', desc: '+12 кредитов, F_VANTA +5.', gains: { CREDITS: 12 }, scaled: true, reputation: { F_VANTA: 5 } },
    ],
  },
  {
    id: 'EV09', name: 'Сторожевой ИИ', text: 'Автономный ИИ предлагает сделку: модуль или данные.',
    choices: [
      { id: 'A', label: 'Взять модуль', desc: 'Цифровой предмет редкости RARE, F_CHOIR +5, +5 розыска.', grantItem: { tag: 'digital', rarity: 'RARE' }, reputation: { F_CHOIR: 5 }, wanted: 5 },
      { id: 'B', label: 'Выкачать данные', desc: '+15 данных, F_CHOIR −5.', gains: { DATA: 15 }, scaled: true, reputation: { F_CHOIR: -5 } },
    ],
  },
  {
    id: 'EV10', name: 'Вражеский сканер', text: 'Работающий сканер следит за дорогой.',
    choices: [
      { id: 'A', label: 'Отключить (−4 данных)', desc: '−8 розыска.', cost: { DATA: 4 }, wanted: -8 },
      { id: 'B', label: 'Использовать', desc: 'Раскрыть слабую метку босса биома, +4 розыска.', flag: 'bossWeakness', wanted: 4 },
    ],
  },
  {
    id: 'EV11', name: 'Потерянная вакцина', text: 'Медицинский контейнер с ремонтной сывороткой.',
    choices: [
      { id: 'A', label: 'Применить', desc: 'Восстановить 35% потерянного HP, F_RUST +3.', healMissingFraction: 0.35, reputation: { F_RUST: 3 } },
      { id: 'B', label: 'Продать', desc: '+20 кредитов, F_RUST −5.', gains: { CREDITS: 20 }, scaled: true, reputation: { F_RUST: -5 } },
    ],
  },
  {
    id: 'EV12', name: 'Брошенные аккумуляторы', text: 'Батареи ещё держат заряд, но корпус придётся повредить.',
    choices: [
      { id: 'A', label: 'Подключить', desc: 'Полностью восполнить энергию перед боем, −5 корпуса.', refillEnergy: true, hull: -5 },
      { id: 'B', label: 'Сдать в лом', desc: '+10 лома, +2 розыска.', gains: { SCRAP: 10 }, scaled: true, wanted: 2 },
    ],
  },
  {
    id: 'EV13', name: 'Серый дилер', text: 'Дилер предлагает редкий предмет со скидкой или обмен данных.',
    choices: [
      { id: 'A', label: 'Купить RARE (60% цены)', desc: 'Случайный совместимый RARE-предмет за 60% магазинной цены.', special: 'greyDealer' },
      { id: 'B', label: 'Обменять данные', desc: '10×R(d) данных → 30×R(d) кредитов.', special: 'dataForCredits' },
    ],
  },
  {
    id: 'EV14', name: 'Сеть камер', text: 'Патрульная сеть заметила транспорт.',
    choices: [
      { id: 'A', label: 'Обойти патруль', desc: '−2 топлива, −10 розыска.', fuel: -2, wanted: -10 },
      { id: 'B', label: 'Принять бой охотника', desc: 'Следующий узел — BOUNTY с +25% кредитов.', nextCombat: { forceBounty: true, bountyCredits: 0.25 } },
    ],
  },
  {
    id: 'EV15', name: 'Уличный архив', text: 'Публичный архив с обрывкамиenemy-досье.',
    choices: [
      { id: 'A', label: 'Скачать досье', desc: '+12 данных и запись в кодекс врагов.', gains: { DATA: 12 }, scaled: true, flag: 'codexEntry' },
      { id: 'B', label: 'Продать доступ', desc: '+16 кредитов, F_ECHO −3.', gains: { CREDITS: 16 }, scaled: true, reputation: { F_ECHO: -3 } },
    ],
  },
  {
    id: 'EV16', name: 'Плата за проход', text: 'Банда предлагает пропустить вас за плату.',
    choices: [
      { id: 'A', label: 'Заплатить (−12 кредитов)', desc: 'Пропустить следующий обычный бой без XP и лута.', cost: { CREDITS: 12 }, nextCombat: { skip: true } },
      { id: 'B', label: 'Прорваться', desc: 'Следующий узел — ELITE с дополнительным роллом предмета.', nextCombat: { forceElite: true, extraRareRoll: true } },
    ],
  },
  {
    id: 'EV17', name: 'Дефектный конденсатор', text: 'Энергетический модуль с трещиной в корпусе.',
    choices: [
      { id: 'A', label: 'Забрать модуль', desc: 'ENERGY-предмет MODIFIED, +10 нагрева в следующем бою.', grantItem: { tag: 'energy', rarity: 'MODIFIED' }, nextCombat: { extraHeat: 10 } },
      { id: 'B', label: 'Разобрать', desc: '+13 лома.', gains: { SCRAP: 13 }, scaled: true },
    ],
  },
  {
    id: 'EV18', name: 'Взломанная турель', text: 'Турель признаёт ваш сигнал как дружественный.',
    choices: [
      { id: 'A', label: 'Взять с собой', desc: 'В следующем бою союзная турель E08 с 50% силы, F_CHOIR +2.', nextCombat: { alliedTurret: true }, reputation: { F_CHOIR: 2 } },
      { id: 'B', label: 'Разобрать', desc: '+10 лома, +4 данных.', gains: { SCRAP: 10, DATA: 4 }, scaled: true },
    ],
  },
  {
    id: 'EV19', name: 'Гражданская колонна', text: 'Колонна гражданских просит сопровождения.',
    choices: [
      { id: 'A', label: 'Сопроводить', desc: 'Следующий переезд +15 с, F_RUST +8.', travelDelta: 15000, reputation: { F_RUST: 8 } },
      { id: 'B', label: 'Продать маршрут', desc: '+22 кредита, F_RUST −8.', gains: { CREDITS: 22 }, scaled: true, reputation: { F_RUST: -8 } },
    ],
  },
  {
    id: 'EV20', name: 'Аварийный ремонт', text: 'Ремонтный дрон предлагает услуги за данные.',
    choices: [
      { id: 'A', label: 'Заплатить данными (−10)', desc: '+35 корпуса.', cost: { DATA: 10 }, hull: 35 },
      { id: 'B', label: 'Продать запчасти', desc: '+20 кредитов, −15 корпуса.', gains: { CREDITS: 20 }, scaled: true, hull: -15 },
    ],
  },
  {
    id: 'EV21', name: 'Служба взыскания', text: 'Взыскатели требуют долг или предлагают цель.',
    choices: [
      { id: 'A', label: 'Заплатить (−15 кредитов)', desc: '−12 розыска.', cost: { CREDITS: 15 }, wanted: -12 },
      { id: 'B', label: 'Взять цель', desc: 'Следующий узел — BOUNTY E21 с дополнительным RARE-роллом.', nextCombat: { forceBounty: true, extraRareRoll: true }, flag: 'bountyE21' },
    ],
  },
  {
    id: 'EV22', name: 'Машинное эхо', text: 'Осколок ИИ предлагает встроиться в нейросеть.',
    choices: [
      { id: 'A', label: 'Принять мутацию', desc: 'Получить MUT_REGEN, если есть свободный слот, F_CHOIR +4.', grantMutation: 'MUT_REGEN', reputation: { F_CHOIR: 4 } },
      { id: 'B', label: 'Скачать и уйти', desc: '+14 данных, F_CHOIR −3.', gains: { DATA: 14 }, scaled: true, reputation: { F_CHOIR: -3 } },
    ],
  },
  {
    id: 'EV23', name: 'Топливный коллектор', text: 'Коллектор топлива требует лом за доступ.',
    choices: [
      { id: 'A', label: 'Заправить (−10 лома)', desc: '+8 топлива.', cost: { SCRAP: 10 }, fuel: 8 },
      { id: 'B', label: 'Слить и продать', desc: '+15 кредитов, +5 розыска.', gains: { CREDITS: 15 }, scaled: true, wanted: 5 },
    ],
  },
  {
    id: 'EV24', name: 'Мост без хозяина', text: 'Разрушенный мост: короткий risky путь или длинный обход.',
    choices: [
      { id: 'A', label: 'Короткий путь', desc: 'Следующий переезд −15 с, +10 розыска.', travelDelta: -15000, wanted: 10 },
      { id: 'B', label: 'Длинный обход', desc: 'Следующий переезд +20 с, +20 временных щитов в следующем бою.', travelDelta: 20000, nextCombat: { shieldBonus: 20 } },
    ],
  },
];

export const EVENT_BY_ID: Record<string, GameEventDef> = Object.fromEntries(EVENTS.map((e) => [e.id, e]));
