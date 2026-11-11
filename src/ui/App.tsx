import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { resolveBuild } from '../core/build/build';
import { ITEM_BY_ID } from '../data/items';
import { createInitialSave } from '../core/save/initial';
import { commitSave, exportSaveText, importSaveText, loadSave, type LoadSaveResult } from '../core/save/storage';
import type { SaveGame } from '../core/save/schema';
import { validateCatalog } from '../data/validate';

type Screen = 'garage' | 'build';
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
        </nav>
        <div className="rail-bottom"><span className="signal-dot" /> АРХИВ СИНХРОНИЗИРОВАН <small>ЛОКАЛЬНЫЙ ПРОФИЛЬ · V1</small></div>
      </aside>

      <main className="main-area">
        <header className="topbar"><div><span className="eyebrow">СЕКТОР 01 <i>·</i> ФОРПОСТ 00</span><span className="topbar-title">НУЛЕВОЙ ТРАКТ</span></div><div className="top-actions">
          {save ? <><span className="save-state"><span className="signal-dot" /> СОХРАНЕНО · R{save.revision}</span><button className="icon-button" title="Экспорт сохранения" onClick={downloadSave}>↥</button></> : <span className="save-state">НЕТ СОХРАНЕНИЯ</span>}
          <button className="icon-button" title="Импорт сохранения" onClick={() => fileRef.current?.click()}>↧</button>
          <input ref={fileRef} className="visually-hidden" type="file" accept="application/json,.json" onChange={(event) => void handleFile(event.target.files?.[0])} />
        </div></header>

        {notice && <div className="notice" role="status">{notice}<button aria-label="Закрыть уведомление" onClick={() => setNotice('')}>×</button></div>}
        {boot.kind === 'loaded' && boot.recovered && <div className="notice notice-warn" role="status">Последний снимок был повреждён. Загружена предыдущая проверенная ревизия; повреждённая запись сохранена.</div>}

        {!save ? <WelcomeState boot={boot} busy={busy} onCreate={() => void createGame()} onImport={() => fileRef.current?.click()} /> : (
          screen === 'garage' ? <GarageScreen save={save} buildValid={!!build?.valid} /> : <BuildScreen save={save} buildValid={!!build?.valid} />
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

function GarageScreen({ save, buildValid }: { save: SaveGame; buildValid: boolean }) {
  const items = new Map(save.meta.inventory.map((item) => [item.itemId, item]));
  const equipment = Object.entries(save.meta.equipment).map(([slot, id]) => ({ slot, item: items.get(id)! })).filter((x) => x.item);
  return <div className="screen-content">
    <section className="hero-row"><div><span className="eyebrow">ФОРПОСТ 00 <i>·</i> ЗАПИСЬ {save.saveId.slice(0, 8).toUpperCase()}</span><h1>Гараж оператора</h1><p>Сборка готова к выезду. Сектор 01 открыт.</p></div><div className="operator-chip"><span className="operator-emblem">{String(save.meta.operator.level).padStart(2, '0')}</span><div><small>ОПЕРАТОР</small><strong>УРОВЕНЬ {save.meta.operator.level}</strong></div><span className={buildValid ? 'valid-badge' : 'invalid-badge'}>{buildValid ? 'СБОРКА ДОПУЩЕНА' : 'ПРОВЕРЬТЕ СБОРКУ'}</span></div></section>
    <section className="wallet-grid" aria-label="Ресурсы и транспорт"><WalletCard symbol="₡" label="КРЕДИТЫ" value={save.meta.protectedBank.CREDITS} detail="ЗАЩИЩЕНО" tone="gold"/><WalletCard symbol="▧" label="МЕТАЛЛОЛОМ" value={save.meta.protectedBank.SCRAP} detail="ЗАЩИЩЕНО" tone="blue"/><WalletCard symbol="⌘" label="ДАННЫЕ" value={save.meta.protectedBank.DATA} detail="ЗАЩИЩЕНО" tone="violet"/><WalletCard symbol="↗" label="ТОПЛИВО" value={save.meta.transport.fuel} detail={`КОРПУС ${save.meta.transport.hull}%`} tone="green"/></section>
    <section className="content-grid"><div className="panel loadout-panel"><div className="panel-head"><div><span className="eyebrow">АКТИВНАЯ ЭКИПИРОВКА</span><h2>Комплект · T1</h2></div><span className="count-chip">{equipment.length} ПРЕДМЕТОВ</span></div><div className="equipment-list">{equipment.map(({ slot, item }) => <div className="equipment-row" key={slot}><span className="slot-code">{slot.replace('_', ' ')}</span><span className={`rarity-line rarity-${item.rarity.toLowerCase()}`} /><div className="equipment-name"><strong>{itemName(item.templateId)}</strong><small>{item.templateId} · прочность {item.durability}%</small></div><span className="tech-label">T{item.techLevel}</span></div>)}</div></div>
      <div className="side-stack"><div className="panel objective-card"><span className="eyebrow">ТЕКУЩИЙ ПРИОРИТЕТ</span><div className="objective-number">01<span>/12</span></div><h2>Прорваться через первый сектор</h2><p>Подготовка завершена. Первая дорога откроется в следующем этапе протокола.</p><div className="progress-track"><span style={{ width: '8.3%' }}/></div><small className="progress-caption">СЕКТОР 1 ИЗ 12 · ФОРПОСТ 00</small></div>
        <div className="panel protocol-card"><div className="panel-head"><div><span className="eyebrow">ТАКТИЧЕСКИЙ ПРОФИЛЬ</span><h2>{save.meta.tactics.find((p) => p.id === save.meta.activeTacticId)?.name ?? 'Не выбран'}</h2></div><span className="signal-dot"/></div><div className="protocol-summary"><span>РЕАКЦИЯ</span><strong>щит при HP &lt; 45% · EMP по касту</strong><span>ОСНОВНОЙ КАНАЛ</span><strong>очередь при 2+ целях · иначе автоатака</strong></div></div></div></section>
  </div>;
}

function WalletCard({ symbol, label, value, detail, tone }: { symbol: string; label: string; value: number; detail: string; tone: string }) {
  return <div className={`wallet-card tone-${tone}`}><span className="wallet-symbol">{symbol}</span><div><span className="eyebrow">{label}</span><strong>{value.toLocaleString('ru-RU')}</strong><small>{detail}</small></div><span className="wallet-corner">+</span></div>;
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
