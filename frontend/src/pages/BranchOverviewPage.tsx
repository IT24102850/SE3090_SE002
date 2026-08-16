import { useMemo, useState, type FormEvent } from 'react';
import { Badge, type BadgeTone } from '../ui/Badge';

type Branch = { name: string; manager: string; items: number; value: number; health: 'Healthy' | 'Needs attention' | 'Critical'; };
type BranchStock = { item: string; sku: string; unit: string; levels: Record<string, number>; reorder: number };
type Transfer = { id: number; item: string; from: string; to: string; quantity: number; requestedBy: string; status: 'Pending' | 'Approved' };

const branches: Branch[] = [
  { name: 'Main branch', manager: 'Kavindu', items: 318, value: 1842200, health: 'Needs attention' },
  { name: 'Colombo outlet', manager: 'Nadeesha', items: 264, value: 1264400, health: 'Needs attention' },
  { name: 'Kandy outlet', manager: 'Dinesh', items: 242, value: 1105800, health: 'Healthy' },
  { name: 'Galle outlet', manager: 'Amaya', items: 198, value: 884600, health: 'Critical' },
];
const stock: BranchStock[] = [
  { item: 'Premium Coffee Beans', sku: 'SKU-00132', unit: 'kg', reorder: 40, levels: { 'Main branch': 6, 'Colombo outlet': 74, 'Kandy outlet': 51, 'Galle outlet': 9 } },
  { item: 'Vanilla Syrup 750ml', sku: 'SKU-00324', unit: 'bottles', reorder: 25, levels: { 'Main branch': 0, 'Colombo outlet': 31, 'Kandy outlet': 18, 'Galle outlet': 11 } },
  { item: 'Packaging Boxes — Medium', sku: 'SKU-00598', unit: 'boxes', reorder: 60, levels: { 'Main branch': 83, 'Colombo outlet': 11, 'Kandy outlet': 92, 'Galle outlet': 48 } },
  { item: 'Whole Milk 1L (Small)', sku: 'SKU-00811', unit: 'cartons', reorder: 80, levels: { 'Main branch': 18, 'Colombo outlet': 132, 'Kandy outlet': 106, 'Galle outlet': 34 } },
];
const healthTone: Record<Branch['health'], BadgeTone> = { Healthy: 'green', 'Needs attention': 'amber', Critical: 'red' };

function TransferModal({ onClose, onSubmit }: { onClose: () => void; onSubmit: (transfer: Omit<Transfer, 'id' | 'status' | 'requestedBy'>) => void }) {
  const [item, setItem] = useState(stock[0].item);
  const [from, setFrom] = useState('Colombo outlet');
  const [to, setTo] = useState('Main branch');
  const [quantity, setQuantity] = useState(20);
  const [error, setError] = useState('');
  const available = stock.find((entry) => entry.item === item)?.levels[from] ?? 0;
  function submit(event: FormEvent) {
    event.preventDefault();
    if (from === to) return setError('Choose two different branches.');
    if (!Number.isFinite(quantity) || quantity <= 0 || quantity > available) return setError(`Enter a quantity between 1 and ${available}.`);
    onSubmit({ item, from, to, quantity });
  }
  return <div className="modal-overlay" onClick={onClose} role="presentation"><div className="modal modal-sm" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="transfer-title"><div className="modal-head"><h2 id="transfer-title">Request stock transfer</h2><button type="button" className="modal-close" onClick={onClose} aria-label="Close">×</button></div><form className="modal-body" onSubmit={submit}>{error && <p className="modal-error">{error}</p>}<div className="form-grid"><label className="form-field form-field-wide">Item<select value={item} onChange={(event) => setItem(event.target.value)}>{stock.map((entry) => <option key={entry.sku}>{entry.item}</option>)}</select></label><label className="form-field">From<select value={from} onChange={(event) => setFrom(event.target.value)}>{branches.map((entry) => <option key={entry.name}>{entry.name}</option>)}</select></label><label className="form-field">To<select value={to} onChange={(event) => setTo(event.target.value)}>{branches.map((entry) => <option key={entry.name}>{entry.name}</option>)}</select></label><label className="form-field form-field-wide">Quantity <span className="field-hint">({available} available at source)</span><input type="number" min="1" max={available} value={quantity} onChange={(event) => setQuantity(Number(event.target.value))} /></label></div><div className="modal-actions"><button type="button" className="btn btn-secondary" onClick={onClose}>Cancel</button><button type="submit" className="btn btn-primary">Submit request</button></div></form></div></div>;
}

export function BranchOverviewPage() {
  const [selectedSku, setSelectedSku] = useState(stock[0].sku);
  const [showModal, setShowModal] = useState(false);
  const [transfers, setTransfers] = useState<Transfer[]>([{ id: 1, item: 'Packaging Boxes — Medium', from: 'Kandy outlet', to: 'Colombo outlet', quantity: 30, requestedBy: 'Nadeesha', status: 'Pending' }]);
  const selected = useMemo(() => stock.find((entry) => entry.sku === selectedSku) ?? stock[0], [selectedSku]);
  function addTransfer(transfer: Omit<Transfer, 'id' | 'status' | 'requestedBy'>) { setTransfers((previous) => [{ ...transfer, id: Date.now(), requestedBy: 'Hasaranga', status: 'Pending' }, ...previous]); setShowModal(false); }
  return <div className="page"><header className="page-head"><div><p className="eyebrow">OPERATIONS / NETWORK</p><h1>Multi-branch overview</h1><p className="page-sub">Compare stock health across locations and rebalance inventory with transfer requests.</p></div><div className="page-actions"><button className="btn btn-primary" type="button" onClick={() => setShowModal(true)}>Request transfer</button></div></header>
    <section className="branch-summary-grid" aria-label="Branch stock summary">{branches.map((branch) => <article className="branch-card" key={branch.name}><div className="branch-card-head"><div><h2>{branch.name}</h2><p>{branch.manager} · {branch.items} items</p></div><Badge tone={healthTone[branch.health]}>{branch.health}</Badge></div><strong>LKR {branch.value.toLocaleString()}</strong><span>Inventory value</span></article>)}</section>
    <div className="branch-layout"><section className="panel"><div className="panel-head"><div><h2>Cross-branch stock comparison</h2><p>Compare availability for a selected item.</p></div><select className="filter-select" value={selectedSku} onChange={(event) => setSelectedSku(event.target.value)} aria-label="Select item">{stock.map((entry) => <option key={entry.sku} value={entry.sku}>{entry.item}</option>)}</select></div><div className="comparison-title"><div><strong>{selected.item}</strong><span>{selected.sku} · Reorder level {selected.reorder} {selected.unit}</span></div></div><div className="branch-levels">{branches.map((branch) => { const level = selected.levels[branch.name]; const pct = Math.min(100, level / selected.reorder * 100); const low = pct < 45; return <div className="branch-level" key={branch.name}><div><strong>{branch.name}</strong><span>{level} {selected.unit}</span></div><div className="stock-level"><div className={`stock-level-fill stock-level-${low ? 'red' : 'green'}`} style={{ width: `${Math.max(4, pct)}%` }} /></div><small>{Math.round(pct)}% of reorder level</small></div>; })}</div></section>
      <section className="panel"><div className="panel-head"><div><h2>Transfer requests</h2><p>Open rebalancing work.</p></div></div><ul className="transfer-list">{transfers.map((transfer) => <li key={transfer.id}><div><strong>{transfer.item}</strong><p>{transfer.from} → {transfer.to} · {transfer.quantity} units</p><span>Requested by {transfer.requestedBy}</span></div><Badge tone={transfer.status === 'Approved' ? 'green' : 'amber'}>{transfer.status}</Badge></li>)}</ul></section></div>
    {showModal && <TransferModal onClose={() => setShowModal(false)} onSubmit={addTransfer} />}
  </div>;
}
