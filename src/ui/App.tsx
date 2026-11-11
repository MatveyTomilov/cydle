import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { resolveBuild } from '../core/build/build';
import { ITEM_BY_ID } from '../data/items';
import { createInitialSave } from '../core/save/initial';
import { commitSave, exportSaveText, importSaveText, loadSave, type LoadSaveResult } from '../core/save/storage';
import type { SaveGame } from '../core/save/schema';
import { validateCatalog } from '../data/validate';
import { createInitialRun } from '../core/run/run';
import { chooseRunNode } from '../core/run/commands';
import { resolveCurrentCombat } from '../core/run/combat';
import { resolveRunCache, resolveRunService } from '../core/run/nodes';
import { resolveRunCheckpoint } from '../core/run/checkpoint';
import type { RunCommandResult, RunState } from '../core/run/types';
import { NODE_TYPE_RU } from '../core/types';

type Screen = 'garage' | 'build' | 'road';
type BootState = { kind: 'loading' } | LoadSaveResult | { kind: 'error'; message: string };

function itemName(templateId: string): string {
  return ITEM_BY_ID[templateId]?.name ?? templateId;
}

export function App() {
  const [boot, setBoot] = useState<BootState>({ kind: 'loading' });
  const [screen, setScreen] = useState<Screen>('garage');
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let live = true;
    const catalogIssues = validateCatalog();
    if (catalogIssues.length) {
      setBoot({ kind: 'error', message: `Каталог данных не прошёл проверку: ${catalogIssues.join(' ')}` });
      return () => { live = false; };
    }
    loadSave().then((result) => { if (live) setBoot(result); })
      .catch((error: unknown) => { if (live) setBoot({ kind: 'error', message: error instanceof Error ? error.message : 'Не удалось открыть IndexedDB.' }); });
    return () => { live = false; };
  }, []);

  const save = boot.kind === 'loaded' ? boot.save : null;
  const build = useMemo(() => {
    if (!save) return null;
    const itemsById = new Map(save.meta.inventory.map((item) => [item.itemId, item]));
    const equipment = Object.fromEntries(Object.entries(save.meta.equipment).map(([slot, id]) => [slot, itemsById.get(id)]));
    return resolveBuild({
      attributes: save.meta.operator.attributes,
      equipment,
      skillIds: save.meta.skillIds,
      passiveIds: save.meta.passiveIds,
      treeNodeIds: save.meta.treeNodeIds,
      attributePointsEarned: save.meta.operator.attributePoints,
      treePointsEarned: save.meta.operator.treePoints,
      unlockedImplantSlots: save.meta.unlockedImplantSlots,
      unlockedDroneSlots: save.meta.unlockedDroneSlots,
    });
  }, [save]);

  async function createGame() {
    setBusy(true);
    setNotice('');
    try {
      const created = await commitSave(createInitialSave());
      setBoot({ kind: 'loaded', save: created, recovered: false });
      setScreen('garage');
      setNotice('Оператор создан. Начальный комплект и ресурсы сохранены.');
    } catch (error) {
      setNotice(error instanceof Error ? error.message : 'Не удалось создать сохранение.');
    } finally { setBusy(false); }
  }

  async function applyRunResult(result: RunCommandResult) {
    if (!result.ok) {
      setNotice(result.reason);
      return;
    }
    if (!result.events.length) return;
    setBusy(true);
    setNotice('');
    try {
      const saved = await commitSave(result.save);
      setBoot({ kind: 'loaded', save: saved, recovered: false });
      setNotice(result.events.map((event) => event.text).join(' '));
    } catch (error) {
      setNotice(error instanceof Error ? error.message : 'Не удалось сохранить действие. Текущее состояние выезда не изменено.');
    } finally { setBusy(false); }
  }

  async function startRun() {
    if (!save || (save.run && save.run.phase !== 'EXTRACTED' && save.run.phase !== 'DEFEATED') || busy) return;
    setBusy(true);
    setNotice('');
    try {
      const base = save.run ? { ...save, run: null } : save;
      const run = createInitialRun(base, globalThis.crypto.randomUUID());
      const saved = await commitSave({ ...base, run });
      setBoot({ kind: 'loaded', save: saved, recovered: false });
      setScreen('road');
      setNotice(`Выезд начат. Сектор ${run.depth} · ${run.biome}.`);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : 'Не удалось начать выезд.');
    } finally { setBusy(false); }
  }

  function commandId() { return globalThis.crypto.randomUUID(); }

  function downloadSave() {
    if (!save) return;
    const blob = new Blob([exportSaveText(save)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `cydle-${save.saveId}.json`;
    anchor.click();
    URL.revokeObjectURL(url);
    setNotice('Экспортирована проверенная копия текущего сохранения.');
  }

  async function handleFile(file?: File) {
    if (!file) return;
    setBusy(true);
    setNotice('');
    try {
      const imported = await importSaveText(await file.text());
      setBoot({ kind: 'loaded', save: imported, recovered: false });
      setScreen('garage');
      setNotice('Сохранение проверено и импортировано.');
    } catch (error) {
      setNotice(error instanceof Error ? error.message : 'Импорт не выполнен. Существующее сохранение не изменено.');
    } finally {
      setBusy(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  if (boot.kind === 'loading') return <div className="boot-screen" role="status">Открываем архив оператора…</div>;
  if (boot.kind === 'error') return <div className="boot-screen"><h1>Архив недоступен</h1><p>{boot.message}</p><button onClick={() => location.reload()}>Повторить</button></div>;

  return (
    <div className="app-shell">
      <aside className="rail">
        <a className="brand" href="#garage" onClick={() => setScreen('garage')} aria-label="CYDLE, гараж"><span className="brand-mark">C</span><span>CYDLE<small>НУЛЕВОЙ ТРАКТ</small></span></a>
        <div className="rail-label">ПРОТОКОЛ</div>
        <nav className="nav-list" aria-label="Разделы">
          <button className={screen === 'garage' ? 'nav-item active' : 'nav-item'} onClick={() => setScreen('garage')}><span className="nav-icon">⌂</span><span>Гараж</span><b>01</b></button>
          <button className={screen === 'build' ? 'nav-item active' : 'nav-item'} onClick={() => setScreen('build')}><span className="nav-icon">◇</span><span>Сборка</span><b>02</b></button>
          {save?.run && <button className={screen === 'road' ? 'nav-item active' : 'nav-item'} onClick={() => setScreen('road')}><span className="nav-icon">⌁</span><span>Дорога</span><b>{String(save.run.depth).padStart(2, '0')}</b></button>}
        </nav>
        <div className="rail-bottom"><span className="signal-dot" /> АРХИВ СИНХРОНИЗИРОВАН <small>ЛОКАЛЬНЫЙ ПРОФИЛЬ · V1</small></div>
      </aside>

      <main className="main-area">
        <header className="topbar"><div><span className="eyebrow">{save?.run ? `СЕКТОР ${String(save.run.depth).padStart(2, '0')} · ${save.run.biome}` : `СЕКТОР ${String(Math.max(1, (save?.meta.unlockedForpost ?? 0) + 1)).padStart(2, '0')} · ФОРПОСТ ${String(save?.meta.unlockedForpost ?? 0).padStart(2, '0')}`}</span><span className="topbar-title">НУЛЕВОЙ ТРАКТ</span></div><div className="top-actions">
          {save ? <><span className="save-state"><span className="signal-dot" /> СОХРАНЕНО · R{save.revision}</span><button className="icon-button" title="Экспорт сохранения" onClick={downloadSave}>↥</button></> : <span className="save-state">НЕТ СОХРАНЕНИЯ</span>}
          <button className="icon-button" title="Импорт сохранения" onClick={() => fileRef.current?.click()}>↧</button>
          <input ref={fileRef} className="visually-hidden" type="file" accept="application/json,.json" onChange={(event) => void handleFile(event.target.files?.[0])} />
        </div></header>

        {notice && <div className="notice" role="status">{notice}<button aria-label="Закрыть уведомление" onClick={() => setNotice('')}>×</button></div>}
        {boot.kind === 'loaded' && boot.recovered && <div className="notice notice-warn" role="status">Последний снимок был повреждён. Загружена предыдущая проверенная ревизия; повреждённая запись сохранена.</div>}

        {!save ? <WelcomeState boot={boot} busy={busy} onCreate={() => void createGame()} onImport={() => fileRef.current?.click()} /> : (
          screen === 'garage' ? <GarageScreen save={save} buildValid={!!build?.valid} busy={busy} onStartRun={() => void startRun()} onOpenRoad={() => setScreen('road')} />
            : screen === 'build' ? <BuildScreen save={save} buildValid={!!build?.valid} />
              : save.run ? <RoadScreen save={save} busy={busy} onResult={(result) => void applyRunResult(result)} onReturn={() => setScreen('garage')} onNewRun={() => void startRun()} commandId={commandId} />
                : <GarageScreen save={save} buildValid={!!build?.valid} busy={busy} onStartRun={() => void startRun()} onOpenRoad={() => setScreen('road')} />
        )}
        <footer className="footer"><span>CYDLE 1.0 <i>·</i> ПРОТОКОЛ ЗАПУЩЕН</span><span>СХЕМА СОХРАНЕНИЯ {save?.schemaVersion ?? '—'} <i>·</i> BALANCE {save?.balanceVersion ?? '—'}</span></footer>
      </main>
    </div>
  );
}

function WelcomeState({ boot, busy, onCreate, onImport }: { boot: LoadSaveResult; busy: boolean; onCreate: () => void; onImport: () => void }) {
  const corrupted = boot.kind === 'corrupt';
  return <section className="welcome panel">
    <div className="welcome-copy"><span className="eyebrow">СИСТЕМА ВОССТАНОВЛЕНА <i>·</i> 01/12</span><h1>{corrupted ? 'Архив требует решения' : 'Нулевой тракт ждёт оператора'}</h1>
      <p>{corrupted ? boot.reason : 'Создайте профиль, чтобы получить стартовый комплект, открыть гараж и подготовить первый выезд.'}</p>
      {corrupted && <p className="muted">Новый профиль не удалит повреждённые снимки. Перед созданием можно импортировать исправную резервную копию.</p>}
      <div className="welcome-actions"><button className="primary-button" disabled={busy} onClick={onCreate}>{busy ? 'СОЗДАНИЕ…' : 'СОЗДАТЬ ОПЕРАТОРА'} <span>→</span></button><button className="secondary-button" disabled={busy} onClick={onImport}>ИМПОРТ СОХРАНЕНИЯ</button></div>
    </div><div className="welcome-visual" aria-hidden="true"><div className="orb orb-a"/><div className="orb orb-b"/><div className="grid-mark">CY<br/>01</div><span className="visual-caption">СИГНАЛ ФОРПОСТА 00<br/>СТАБИЛЬНОСТЬ 98.4%</span></div>
  </section>;
}

function GarageScreen({ save, buildValid, busy, onStartRun, onOpenRoad }: { save: SaveGame; buildValid: boolean; busy: boolean; onStartRun: () => void; onOpenRoad: () => void }) {
  const items = new Map(save.meta.inventory.map((item) => [item.itemId, item]));
  const equipment = Object.entries(save.meta.equipment).map(([slot, id]) => ({ slot, item: items.get(id)! })).filter((x) => x.item);
  return <div className="screen-content">
    <section className="hero-row"><div><span className="eyebrow">ФОРПОСТ 00 <i>·</i> ЗАПИСЬ {save.saveId.slice(0, 8).toUpperCase()}</span><h1>Гараж оператора</h1><p>Сборка готова к выезду. Сектор 01 открыт.</p></div><div className="operator-chip"><span className="operator-emblem">{String(save.meta.operator.level).padStart(2, '0')}</span><div><small>ОПЕРАТОР</small><strong>УРОВЕНЬ {save.meta.operator.level}</strong></div><span className={buildValid ? 'valid-badge' : 'invalid-badge'}>{buildValid ? 'СБОРКА ДОПУЩЕНА' : 'ПРОВЕРЬТЕ СБОРКУ'}</span></div></section>
    <section className="wallet-grid" aria-label="Ресурсы и транспорт"><WalletCard symbol="₡" label="КРЕДИТЫ" value={save.meta.protectedBank.CREDITS} detail="ЗАЩИЩЕНО" tone="gold"/><WalletCard symbol="▧" label="МЕТАЛЛОЛОМ" value={save.meta.protectedBank.SCRAP} detail="ЗАЩИЩЕНО" tone="blue"/><WalletCard symbol="⌘" label="ДАННЫЕ" value={save.meta.protectedBank.DATA} detail="ЗАЩИЩЕНО" tone="violet"/><WalletCard symbol="↗" label="ТОПЛИВО" value={save.meta.transport.fuel} detail={`КОРПУС ${save.meta.transport.hull}%`} tone="green"/></section>
    <section className="content-grid"><div className="panel loadout-panel"><div className="panel-head"><div><span className="eyebrow">АКТИВНАЯ ЭКИПИРОВКА</span><h2>Комплект · T1</h2></div><span className="count-chip">{equipment.length} ПРЕДМЕТОВ</span></div><div className="equipment-list">{equipment.map(({ slot, item }) => <div className="equipment-row" key={slot}><span className="slot-code">{slot.replace('_', ' ')}</span><span className={`rarity-line rarity-${item.rarity.toLowerCase()}`} /><div className="equipment-name"><strong>{itemName(item.templateId)}</strong><small>{item.templateId} · прочность {item.durability}%</small></div><span className="tech-label">T{item.techLevel}</span></div>)}</div></div>
      <div className="side-stack"><div className="panel objective-card"><span className="eyebrow">ТЕКУЩИЙ ПРИОРИТЕТ</span><div className="objective-number">{String(save.run?.depth ?? (save.meta.unlockedForpost + 1)).padStart(2, '0')}<span>/12</span></div><h2>{save.run ? `Выезд · ${runPhaseName(save.run.phase)}` : 'Прорваться через первый сектор'}</h2><p>{save.run ? `Топливо ${save.run.resources.fuel}/${save.run.resources.maxFuel} · груз ${save.run.unsecuredCargo.length} предметов · розыск ${Math.round(save.run.wanted)}` : 'Подготовка завершена. Первый выезд уже доступен.'}</p>
          <button className="primary-button garage-run-button" disabled={busy || (!!save.run && save.run.phase !== 'EXTRACTED' && save.run.phase !== 'DEFEATED') || !buildValid} onClick={save.run && save.run.phase !== 'EXTRACTED' && save.run.phase !== 'DEFEATED' ? onOpenRoad : onStartRun}>{save.run && save.run.phase !== 'EXTRACTED' && save.run.phase !== 'DEFEATED' ? 'ПРОДОЛЖИТЬ ВЫЕЗД' : 'НАЧАТЬ ВЫЕЗД'} <span>→</span></button>
          <div className="progress-track"><span style={{ width: `${Math.min(100, ((save.meta.maxSectorCleared ?? 0) / 12) * 100)}%` }}/></div><small className="progress-caption">ПРОЙДЕНО СЕКТОРОВ · {save.meta.maxSectorCleared ?? 0} / 12</small></div>
        <div className="panel protocol-card"><div className="panel-head"><div><span className="eyebrow">ТАКТИЧЕСКИЙ ПРОФИЛЬ</span><h2>{save.meta.tactics.find((p) => p.id === save.meta.activeTacticId)?.name ?? 'Не выбран'}</h2></div><span className="signal-dot"/></div><div className="protocol-summary"><span>РЕАКЦИЯ</span><strong>щит при HP &lt; 45% · EMP по касту</strong><span>ОСНОВНОЙ КАНАЛ</span><strong>очередь при 2+ целях · иначе автоатака</strong></div></div></div></section>
  </div>;
}

function WalletCard({ symbol, label, value, detail, tone }: { symbol: string; label: string; value: number; detail: string; tone: string }) {
  return <div className={`wallet-card tone-${tone}`}><span className="wallet-symbol">{symbol}</span><div><span className="eyebrow">{label}</span><strong>{value.toLocaleString('ru-RU')}</strong><small>{detail}</small></div><span className="wallet-corner">+</span></div>;
}

function runPhaseName(phase: RunState['phase']): string {
  return ({ ROUTE: 'выбор маршрута', NODE: 'узел дороги', CHECKPOINT: 'контрольная точка', EXTRACTED: 'выезд завершён', DEFEATED: 'оператор потерян', SAFE_ERROR_STOP: 'безопасная остановка' })[phase];
}

function RoadScreen({ save, busy, onResult, onReturn, onNewRun, commandId }: {
  save: SaveGame;
  busy: boolean;
  onResult: (result: RunCommandResult) => void;
  onReturn: () => void;
  onNewRun: () => void;
  commandId: () => string;
}) {
  const run = save.run!;
  const [cargoSelection, setCargoSelection] = useState<string[]>([]);
  const [currencyShare, setCurrencyShare] = useState(0.5);
  const [spendProtected, setSpendProtected] = useState(false);
  const nodes = run.graph.layers.flat();
  const current = nodes.find((node) => node.id === run.currentNodeId);
  const choices = run.graph.edges.filter((edge) => edge.from === run.currentNodeId).map((edge) => ({ edge, node: nodes.find((node) => node.id === edge.to)! })).filter(({ node }) => !!node);
  const terminal = run.phase === 'EXTRACTED' || run.phase === 'DEFEATED';
  const combat = run.combatResult;

  function dispatch(result: RunCommandResult) {
    onResult(result);
    if (result.ok && result.events.length) setCargoSelection([]);
  }

  function actionButton(label: string, onClick: () => void, secondary = false) {
    return <button className={secondary ? 'secondary-button road-action-secondary' : 'primary-button road-action'} disabled={busy} onClick={onClick}>{label}</button>;
  }

  return <div className="screen-content road-screen">
    <section className="hero-row"><div><span className="eyebrow">ДОРОГА <i>·</i> {run.biome} <i>·</i> SEED {run.seed.slice(0, 8).toUpperCase()}</span><h1>{terminal ? run.phase === 'EXTRACTED' ? 'Груз доставлен' : 'Выезд завершён' : `Сектор ${String(run.depth).padStart(2, '0')}`}</h1><p>{terminal ? run.phase === 'EXTRACTED' ? 'Защищённый груз и ресурсы доступны в гараже.' : 'Незакреплённый груз потерян; предыдущие отправки сохранены.' : `${runPhaseName(run.phase)} · ${run.graph.layers.flat().length} точек на карте сектора.`}</p></div>
      <div className="operator-chip road-resources"><span><small>ОПЕРАТОР</small><strong>{Math.ceil(run.resources.hp)} / {run.resources.maxHP} HP</strong></span><span><small>ЩИТ</small><strong>{Math.ceil(run.resources.shield)} / {run.resources.maxShield}</strong></span><span><small>ТОПЛИВО</small><strong>{run.resources.fuel} / {run.resources.maxFuel}</strong></span></div>
    </section>

    {combat && <section className={`panel combat-report combat-${combat.outcome.toLowerCase()}`} aria-live="polite"><div className="panel-head"><div><span className="eyebrow">ПОСЛЕДНИЙ БОЙ · {combat.durationMs / 1000 | 0} СЕК</span><h2>{combat.outcome === 'VICTORY' ? 'Победа' : combat.outcome === 'DEFEAT' ? 'Поражение' : 'Лимит симуляции'}</h2></div><span className="count-chip">УБИЙСТВ {combat.metrics.kills} · УРОН {Math.round(combat.metrics.damageDealt)}</span></div><p>Получено урона: {Math.round(combat.metrics.damageTaken)} · прерываний: {combat.metrics.interrupts} · потрачено энергии: {Math.round(combat.metrics.energySpent)}.</p>
      <details><summary>Журнал боя · {combat.log.length} событий</summary><ol className="combat-log">{combat.log.slice(-30).map((event) => <li key={event.eventId}><time>{(event.timestamp / 1000).toFixed(1)}с</time><span>{event.text}</span></li>)}</ol></details></section>}

    <section className="road-layout"><div className="panel road-map"><div className="panel-head"><div><span className="eyebrow">МАРШРУТ</span><h2>Секторная карта</h2></div><span className="count-chip">ШАГ {run.visitedNodeIds.length} / 6</span></div><div className="route-trail"><span className="trail-origin">ФОРПОСТ</span>{run.visitedNodeIds.map((id, index) => { const node = nodes.find((candidate) => candidate.id === id); return <span className={id === run.currentNodeId ? 'trail-node current' : 'trail-node'} key={id}><i>{String(index + 1).padStart(2, '0')}</i>{node ? NODE_TYPE_RU[node.type] : 'узел'}</span>; })}</div>
      {run.phase === 'ROUTE' && choices.length > 0 && <div className="route-choices"><h3>ДОСТУПНЫЕ ПЕРЕХОДЫ</h3>{choices.map(({ edge, node }) => <button className="route-card" key={node.id} disabled={busy || run.resources.fuel < edge.fuelCost} onClick={() => dispatch(chooseRunNode(save, commandId(), node.id))}><span className="route-card-type">{NODE_TYPE_RU[node.type]}</span><strong>{node.threat.toUpperCase()} {node.type === 'COMBAT' ? `· ${node.enemies.length} противник(а)` : ''}</strong><small>{node.lootHint} · топливо {edge.fuelCost} · слой {node.layer + 1}/6</small><b>ВЫБРАТЬ →</b></button>)}</div>}
      {run.phase === 'ROUTE' && choices.length === 0 && <p className="muted">Маршрут не найден. Состояние сохранено для диагностики.</p>}
      {run.phase === 'NODE' && current && <div className="current-node"><span className="eyebrow">ТЕКУЩИЙ УЗЕЛ · СЛОЙ {current.layer + 1}</span><h3>{NODE_TYPE_RU[current.type]}</h3><p>{current.lootHint}</p>
        {['COMBAT', 'ELITE', 'BOUNTY', 'BOSS'].includes(current.type) && actionButton('РАЗРЕШИТЬ БОЙ', () => dispatch(resolveCurrentCombat(save, commandId())))}
        {current.type === 'CACHE' && <div className="prototype-grid">{(current.prototypeChoices ?? []).map((templateId) => <button className="route-card prototype-card" key={templateId} disabled={busy} onClick={() => dispatch(resolveRunCache(save, commandId(), templateId))}><strong>{itemName(templateId)}</strong><small>{templateId} · выбор закрепится при отправке или эвакуации</small></button>)}</div>}
        {current.type === 'REPAIR' && <div className="action-row">{actionButton('ВОССТАНОВИТЬ КОРПУС', () => dispatch(resolveRunService(save, { id: commandId(), choice: 'REPAIR_HULL', spendProtected })))}{actionButton('ВОССТАНОВИТЬ HP', () => dispatch(resolveRunService(save, { id: commandId(), choice: 'REPAIR_HP', spendProtected })), true)}</div>}
        {current.type === 'FUEL' && actionButton('КУПИТЬ 1 ЕД. ТОПЛИВА · КРЕДИТЫ', () => dispatch(resolveRunService(save, { id: commandId(), choice: 'BUY_FUEL', currency: 'CREDITS', spendProtected })))}
        {(current.type === 'REPAIR' || current.type === 'FUEL') && <label className="protected-spend"><input type="checkbox" checked={spendProtected} onChange={(event) => setSpendProtected(event.target.checked)} /> разрешить оплату из защищённого банка</label>}
      </div>}
      {run.phase === 'CHECKPOINT' && <div className="checkpoint-panel"><span className="eyebrow">КОНТРОЛЬНЫЙ УЗЕЛ</span><h3>Добыча сектора под защитой решения</h3><p>Эвакуация защищает всё. Отправка стоит {Math.ceil(10 * (1 + 0.06 * (run.depth - 1)) ** 1.4)} кредитов и сохраняет выезд активным. Продолжение открывает следующий сектор.</p>
        <details className="ship-details"><summary>Выбрать отправку груза</summary><div className="cargo-list">{run.unsecuredCargo.map((item) => <label key={item.itemId}><input type="checkbox" checked={cargoSelection.includes(item.itemId)} onChange={(event) => setCargoSelection((ids) => event.target.checked ? [...ids, item.itemId] : ids.filter((id) => id !== item.itemId))}/><span><strong>{itemName(item.templateId)}</strong><small>{item.rarity} · T{item.techLevel}</small></span></label>)}</div><label className="share-label">Доля валюты <select value={currencyShare} onChange={(event) => setCurrencyShare(Number(event.target.value))}><option value={0}>0%</option><option value={0.25}>25%</option><option value={0.5}>50%</option></select></label><label className="protected-spend"><input type="checkbox" checked={spendProtected} onChange={(event) => setSpendProtected(event.target.checked)}/> разрешить оплату доставки из защищённого банка</label>{actionButton('ОТПРАВИТЬ ВЫБРАННОЕ', () => dispatch(resolveRunCheckpoint(save, { id: commandId(), choice: 'SHIP', cargoItemIds: cargoSelection, currencyShare, spendProtected })), true)}</details>
        <div className="action-row">{actionButton('ЭВАКУИРОВАТЬ ВСЁ', () => dispatch(resolveRunCheckpoint(save, { id: commandId(), choice: 'EXIT' })))}{actionButton('ПРОДОЛЖИТЬ ВЫЕЗД', () => dispatch(resolveRunCheckpoint(save, { id: commandId(), choice: 'CONTINUE' })), true)}</div>
      </div>}
      {terminal && <div className="terminal-actions">{actionButton('В ГАРАЖ', onReturn, true)}{actionButton('НОВЫЙ ВЫЕЗД', onNewRun)}</div>}
      {run.phase === 'SAFE_ERROR_STOP' && <div className="checkpoint-panel"><h3>Симуляция остановлена безопасно</h3><p>Награды не выданы. Текущее состояние и журнал боя сохранены.</p>{actionButton('В ГАРАЖ', onReturn, true)}</div>}
    </div>

    <aside className="road-side"><div className="panel road-wallet"><span className="eyebrow">НЕЗАКРЕПЛЁННОЕ</span><div className="run-currencies"><span>₡ <b>{Math.floor(run.runWallet.CREDITS)}</b></span><span>▧ <b>{Math.floor(run.runWallet.SCRAP)}</b></span><span>⌘ <b>{Math.floor(run.runWallet.DATA)}</b></span></div><div className="run-cargo-count">ГРУЗ · {run.unsecuredCargo.length} предметов <small>+ {run.shippedCargo.length} уже отправлено</small></div></div><div className="panel road-wallet"><span className="eyebrow">СОХРАНЕНИЕ</span><p>Каждое принятое действие записывается атомарным снимком. Seed: <code>{run.seed.slice(0, 14)}</code></p><p>Игровое время: {Math.floor(run.resources.gameTimeMs / 1000)} с · корпус: {Math.ceil(run.resources.hull)}%</p></div></aside></section>
  </div>;
}

function BuildScreen({ save, buildValid }: { save: SaveGame; buildValid: boolean }) {
  const { attributes } = save.meta.operator;
  return <div className="screen-content"><section className="hero-row"><div><span className="eyebrow">BUILD LAB <i>·</i> ОПЕРАТОР {save.saveId.slice(0, 8).toUpperCase()}</span><h1>Сборка оператора</h1><p>Начальные характеристики и установленные протоколы.</p></div><span className={buildValid ? 'valid-badge' : 'invalid-badge'}>{buildValid ? 'ПРОВЕРКА СБОРКИ ПРОЙДЕНА' : 'ОШИБКА СБОРКИ'}</span></section>
    <section className="content-grid build-grid"><div className="panel"><div className="panel-head"><div><span className="eyebrow">АТРИБУТЫ</span><h2>Уровень {save.meta.operator.level} <small>· {save.meta.operator.xp} XP</small></h2></div><span className="count-chip">ОЧКИ {save.meta.operator.attributePoints}</span></div><div className="attribute-grid">{Object.entries(attributes).map(([id, value]) => <div className="attribute" key={id}><span>{id}</span><strong>{value}</strong><small>{attributeName(id)}</small></div>)}</div><div className="tree-summary"><div><span className="eyebrow">ДЕРЕВО СПЕЦИАЛИЗАЦИИ</span><strong>{save.meta.operator.treePoints} свободных очков</strong></div><small>ПОЛУЧЕНО УЗЛОВ · {save.meta.treeNodeIds.length}</small></div></div>
      <div className="panel"><div className="panel-head"><div><span className="eyebrow">УСТАНОВЛЕННЫЕ ПРОТОКОЛЫ</span><h2>Активные и пассивные</h2></div></div><div className="protocol-summary">{save.meta.skillIds.map((id) => <Fragment key={id}><span>УМЕНИЕ</span><strong>{id}</strong></Fragment>)}{save.meta.passiveIds.map((id) => <Fragment key={id}><span>ПАССИВ</span><strong>{id}</strong></Fragment>)}</div><div className="build-footnote">Нейроёмкость: 100 · имплантных слотов: {save.meta.unlockedImplantSlots} · слот дрона: {save.meta.unlockedDroneSlots}</div></div></section>
  </div>;
}

function attributeName(id: string) {
  return ({ POW: 'Мощность', REF: 'Реакция', INT: 'Интеллект', ENG: 'Инженерия', SYN: 'Синхронизация' } as Record<string, string>)[id] ?? id;
}
