import { useEffect, useState } from 'react';
import { useSelector } from 'react-redux';
import type { RootState } from '../../../store/store';
import { useToast } from '../../../shared/components/Toast';
import { billingApi, errorMessage, type InvoiceTemplate, type TemplateBlock } from '../billingApi';
import { useAsync } from '../useAsync';
import InvoicePaper, { DEFAULT_BLOCKS, SAMPLE_PAPER } from '../components/InvoicePaper';
import '../billing.css';

interface Draft {
  id: string | null;
  name: string;
  isDefault: boolean;
  layout: TemplateBlock[];
  accentColor: string;
  headerText: string;
  footerText: string;
}

const blank = (): Draft => ({
  id: null,
  name: 'New template',
  isDefault: false,
  layout: DEFAULT_BLOCKS.map((b) => ({ ...b })),
  accentColor: '#2563eb',
  headerText: '',
  footerText: 'Thank you for your business.',
});

/** Fills in any block type a saved layout is missing, hidden, at the end. */
function withAllBlocks(layout: TemplateBlock[]): TemplateBlock[] {
  const present = new Set(layout.map((b) => b.type));
  return [...layout, ...DEFAULT_BLOCKS.filter((b) => !present.has(b.type)).map((b) => ({ ...b, visible: false }))];
}

export function moveBlock(layout: TemplateBlock[], from: number, to: number): TemplateBlock[] {
  if (from === to || from < 0 || to < 0 || from >= layout.length || to >= layout.length) return layout;
  const next = [...layout];
  const [item] = next.splice(from, 1);
  next.splice(to, 0, item);
  return next;
}

export default function InvoiceDesignerPage() {
  const { user } = useSelector((s: RootState) => s.auth);
  const canEdit = user?.role === 'Admin' || user?.role === 'Manager';
  const toast = useToast();
  const { data: templates, reload } = useAsync(() => billingApi.listTemplates(), []);
  const [draft, setDraft] = useState<Draft>(blank);
  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const [overIndex, setOverIndex] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);

  // Open the default template once they load.
  useEffect(() => {
    if (templates && templates.length > 0 && draft.id === null && draft.name === 'New template') open(templates.find((t) => t.isDefault) ?? templates[0]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [templates]);

  const open = (t: InvoiceTemplate) =>
    setDraft({
      id: t.id,
      name: t.name,
      isDefault: t.isDefault,
      layout: withAllBlocks(t.layout?.length ? t.layout : DEFAULT_BLOCKS),
      accentColor: t.accentColor,
      headerText: t.headerText ?? '',
      footerText: t.footerText ?? '',
    });

  const save = async () => {
    setSaving(true);
    try {
      const saved = await billingApi.saveTemplate(draft.id, {
        name: draft.name.trim(),
        isDefault: draft.isDefault,
        layout: draft.layout,
        accentColor: draft.accentColor,
        headerText: draft.headerText || null,
        footerText: draft.footerText || null,
      });
      open(saved);
      reload();
      toast.show('Template saved - new PDFs and receipts use it.', 'success');
    } catch (err) {
      toast.show(errorMessage(err, 'The template could not be saved.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  const remove = async () => {
    if (!draft.id || !window.confirm(`Delete "${draft.name}"?`)) return;
    try {
      await billingApi.deleteTemplate(draft.id);
      setDraft(blank());
      reload();
    } catch (err) {
      toast.show(errorMessage(err, 'The template could not be deleted.'), 'error');
    }
  };

  const setLayout = (layout: TemplateBlock[]) => setDraft({ ...draft, layout });

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Invoice designer</h1>
          <p className="page-subtitle">Drag the sections into order and switch them on or off. PDFs, emailed invoices and receipts follow the default template.</p>
        </div>
        <div className="bl-row">
          <select className="input" style={{ minWidth: 200 }} aria-label="Template" value={draft.id ?? ''}
            onChange={(e) => { const t = templates?.find((x) => x.id === e.target.value); if (t) open(t); else setDraft(blank()); }}>
            <option value="">+ New template</option>
            {templates?.map((t) => <option key={t.id} value={t.id}>{t.name}{t.isDefault ? ' (default)' : ''}</option>)}
          </select>
        </div>
      </div>

      <div className="bl-designer">
        <div className="card bl-stack" style={{ padding: 16 }}>
          <label className="bl-field"><span>Template name</span>
            <input className="input" value={draft.name} maxLength={100} disabled={!canEdit} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
          </label>

          <div className="bl-stack">
            <span className="bl-label">Sections</span>
            <ol className="bl-blocks" aria-label="Invoice sections" style={{ listStyle: 'none', margin: 0, padding: 0 }}>
              {draft.layout.map((block, index) => (
                <li
                  key={block.id}
                  className={`bl-block${dragIndex === index ? ' bl-dragging' : ''}${overIndex === index && dragIndex !== index ? ' bl-drop-target' : ''}${block.visible ? '' : ' bl-hidden'}`}
                  draggable={canEdit}
                  onDragStart={(e) => { setDragIndex(index); e.dataTransfer.effectAllowed = 'move'; }}
                  onDragOver={(e) => { e.preventDefault(); setOverIndex(index); }}
                  onDrop={(e) => { e.preventDefault(); if (dragIndex !== null) setLayout(moveBlock(draft.layout, dragIndex, index)); setDragIndex(null); setOverIndex(null); }}
                  onDragEnd={() => { setDragIndex(null); setOverIndex(null); }}
                >
                  <span className="bl-grip" aria-hidden="true">⋮⋮</span>
                  <span className="bl-block-name">{block.label}</span>
                  <button type="button" className="btn btn-ghost btn-sm" aria-label={`Move ${block.label} up`} disabled={!canEdit || index === 0}
                    onClick={() => setLayout(moveBlock(draft.layout, index, index - 1))}>↑</button>
                  <button type="button" className="btn btn-ghost btn-sm" aria-label={`Move ${block.label} down`} disabled={!canEdit || index === draft.layout.length - 1}
                    onClick={() => setLayout(moveBlock(draft.layout, index, index + 1))}>↓</button>
                  <input type="checkbox" aria-label={`Show ${block.label}`} checked={block.visible} disabled={!canEdit}
                    onChange={(e) => setLayout(draft.layout.map((b) => (b.id === block.id ? { ...b, visible: e.target.checked } : b)))} />
                </li>
              ))}
            </ol>
          </div>

          <label className="bl-field"><span>Accent colour</span>
            <div className="bl-row" style={{ flexWrap: 'nowrap' }}>
              <input type="color" value={draft.accentColor} disabled={!canEdit} aria-label="Accent colour picker"
                onChange={(e) => setDraft({ ...draft, accentColor: e.target.value })} style={{ width: 44, height: 36, border: 'none', background: 'none' }} />
              <input className="input" value={draft.accentColor} maxLength={20} disabled={!canEdit} onChange={(e) => setDraft({ ...draft, accentColor: e.target.value })} />
            </div>
          </label>
          <label className="bl-field"><span>Header line</span>
            <input className="input" value={draft.headerText} maxLength={500} disabled={!canEdit} placeholder="12 Galle Road, Colombo 03 · VAT 1234567" onChange={(e) => setDraft({ ...draft, headerText: e.target.value })} />
          </label>
          <label className="bl-field"><span>Footer</span>
            <textarea className="input" rows={2} value={draft.footerText} maxLength={1000} disabled={!canEdit} onChange={(e) => setDraft({ ...draft, footerText: e.target.value })} />
          </label>
          <label className="bl-row"><input type="checkbox" checked={draft.isDefault} disabled={!canEdit} onChange={(e) => setDraft({ ...draft, isDefault: e.target.checked })} /> Use as the default template</label>

          {canEdit ? (
            <div className="bl-row">
              <button className="btn btn-primary" disabled={saving || !draft.name.trim()} onClick={save}>{saving ? 'Saving…' : 'Save template'}</button>
              {draft.id && <button className="btn btn-ghost" onClick={remove}>Delete</button>}
              <button className="btn btn-ghost" onClick={() => setLayout(DEFAULT_BLOCKS.map((b) => ({ ...b })))}>Reset layout</button>
            </div>
          ) : (
            <div className="bl-notice bl-small">Only Admins and Managers can change templates.</div>
          )}
        </div>

        <div className="bl-stack">
          <span className="bl-label">Preview (sample data)</span>
          <InvoicePaper
            data={SAMPLE_PAPER}
            blocks={draft.layout}
            accentColor={draft.accentColor}
            headerText={draft.headerText}
            footerText={draft.footerText}
          />
        </div>
      </div>
    </div>
  );
}
