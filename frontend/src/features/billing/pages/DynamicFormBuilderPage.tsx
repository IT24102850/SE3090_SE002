import { useMemo, useState } from 'react';
import { useSelector } from 'react-redux';
import type { RootState } from '../../../store/store';
import { useToast } from '../../../shared/components/Toast';
import { billingApi, errorMessage, type DynamicForm, type JsonSchema, type JsonSchemaField } from '../billingApi';
import { useAsync } from '../useAsync';
import {
  FORM_PRESETS,
  fieldsToSchema,
  newBuilderField,
  schemaToFields,
  validateBuilder,
  type BuilderField,
  type FieldErrors,
} from '../dynamicFormLogic';
import DynamicFormRenderer from '../components/DynamicFormRenderer';
import '../billing.css';

type Mode = 'visual' | 'json';
const TYPES: JsonSchemaField['type'][] = ['string', 'number', 'integer', 'boolean', 'array'];

export default function DynamicFormBuilderPage() {
  const { user } = useSelector((s: RootState) => s.auth);
  const canEdit = user?.role === 'Admin' || user?.role === 'Manager';
  const toast = useToast();
  const { data: forms, reload } = useAsync(() => billingApi.listForms(), []);

  const [formType, setFormType] = useState('');
  const [existing, setExisting] = useState<DynamicForm | null>(null);
  const [fields, setFields] = useState<BuilderField[]>(() => schemaToFields(FORM_PRESETS['table-bill'].schema));
  const [mode, setMode] = useState<Mode>('visual');
  const [json, setJson] = useState('');
  const [jsonError, setJsonError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [previewKey, setPreviewKey] = useState(0);
  const [serverErrors, setServerErrors] = useState<FieldErrors>({});
  const [testResult, setTestResult] = useState<string | null>(null);

  const schema: JsonSchema = useMemo(() => fieldsToSchema(fields), [fields]);
  const problems = validateBuilder(formType, fields);

  const load = (f: DynamicForm) => {
    setExisting(f);
    setFormType(f.formType);
    setFields(schemaToFields(f.schema));
    setMode('visual');
    setServerErrors({});
    setTestResult(null);
    setPreviewKey((k) => k + 1);
  };

  const startNew = (presetKey?: string) => {
    setExisting(null);
    setFormType(presetKey ?? '');
    setFields(presetKey ? schemaToFields(FORM_PRESETS[presetKey].schema) : [newBuilderField({ name: 'reference', title: 'Reference', required: true })]);
    setMode('visual');
    setServerErrors({});
    setTestResult(null);
    setPreviewKey((k) => k + 1);
  };

  const switchMode = (next: Mode) => {
    if (next === mode) return;
    if (next === 'json') {
      setJson(JSON.stringify(schema, null, 2));
      setJsonError(null);
    } else {
      try {
        const parsed = JSON.parse(json) as JsonSchema;
        if (!parsed || typeof parsed !== 'object' || typeof parsed.properties !== 'object') throw new Error('The schema needs a "properties" object.');
        setFields(schemaToFields(parsed));
        setPreviewKey((k) => k + 1);
      } catch (e) {
        setJsonError(e instanceof Error ? e.message : 'Invalid JSON.');
        return;
      }
    }
    setMode(next);
  };

  const applyJson = (text: string) => {
    setJson(text);
    try {
      const parsed = JSON.parse(text) as JsonSchema;
      if (typeof parsed?.properties !== 'object') throw new Error('The schema needs a "properties" object.');
      setFields(schemaToFields(parsed));
      setJsonError(null);
      setPreviewKey((k) => k + 1);
    } catch (e) {
      setJsonError(e instanceof Error ? e.message : 'Invalid JSON.');
    }
  };

  const update = (key: string, patch: Partial<BuilderField>) => {
    setFields(fields.map((f) => (f.key === key ? { ...f, ...patch } : f)));
    setPreviewKey((k) => k + 1);
  };

  const save = async () => {
    setSaving(true);
    try {
      const saved = await billingApi.saveForm(formType, { schema });
      load(saved);
      reload();
      toast.show(`Form "${saved.formType}" saved.`, 'success');
    } catch (err) {
      toast.show(errorMessage(err, 'The form could not be saved.'), 'error');
    } finally {
      setSaving(false);
    }
  };

  const remove = async () => {
    if (!existing || !window.confirm(`Delete the "${existing.formType}" form? Past submissions are kept.`)) return;
    try {
      await billingApi.deleteForm(existing.formType);
      startNew();
      reload();
    } catch (err) {
      toast.show(errorMessage(err, 'The form could not be deleted.'), 'error');
    }
  };

  /** Runs the preview's values past the server's validator too. */
  const testOnServer = async (values: Record<string, unknown>) => {
    setServerErrors({});
    if (!existing || existing.formType !== formType) {
      setTestResult('Checked in the browser. Save the form to also check it against the server.');
      return;
    }
    try {
      const result = await billingApi.validateForm(formType, values);
      setServerErrors(Object.fromEntries(result.errors.map((e) => [e.field, e.message])));
      setTestResult(result.isValid ? 'Valid - the server accepts this submission.' : `The server found ${result.errors.length} problem(s).`);
    } catch (err) {
      setTestResult(errorMessage(err, 'The server check failed.'));
    }
  };

  return (
    <div className="bl-page">
      <div className="page-header">
        <div>
          <h1 className="page-title">Dynamic form builder</h1>
          <p className="page-subtitle">Business-specific billing forms as JSON Schema: clinic visits, table bills, tuition plans, property deals…</p>
        </div>
        <div className="bl-row">
          <select className="input" aria-label="Saved forms" value={existing?.formType ?? ''}
            onChange={(e) => { const f = forms?.find((x) => x.formType === e.target.value); if (f) load(f); else startNew(); }}>
            <option value="">+ New form</option>
            {forms?.map((f) => <option key={f.id} value={f.formType}>{f.formType} ({f.submissionCount} submissions)</option>)}
          </select>
        </div>
      </div>

      {!existing && (
        <div className="bl-row">
          <span className="bl-label">Start from:</span>
          {Object.entries(FORM_PRESETS).map(([key, p]) => <button key={key} className="btn btn-ghost btn-sm" onClick={() => startNew(key)}>{p.label}</button>)}
        </div>
      )}

      <div className="bl-grid-2" style={{ alignItems: 'start' }}>
        <div className="card bl-stack" style={{ padding: 16 }}>
          <label className="bl-field"><span>Form type (its URL name)</span>
            <input className="input bl-mono" value={formType} disabled={!!existing || !canEdit} placeholder="table-bill"
              onChange={(e) => setFormType(e.target.value.toLowerCase())} />
          </label>

          <div className="bl-tabs" role="tablist" aria-label="Editor">
            <button role="tab" className="bl-tab" aria-selected={mode === 'visual'} onClick={() => switchMode('visual')}>Fields</button>
            <button role="tab" className="bl-tab" aria-selected={mode === 'json'} onClick={() => switchMode('json')}>JSON Schema</button>
          </div>

          {mode === 'visual' ? (
            <div className="bl-stack">
              {fields.map((f, index) => (
                <fieldset key={f.key} className="bl-list-item" style={{ margin: 0 }} disabled={!canEdit}>
                  <legend className="bl-small bl-muted">Field {index + 1}</legend>
                  <div className="bl-grid-3">
                    <input className="input bl-mono" aria-label="Field name" value={f.name} onChange={(e) => update(f.key, { name: e.target.value })} />
                    <input className="input" aria-label="Label" placeholder="Label" value={f.title} onChange={(e) => update(f.key, { title: e.target.value })} />
                    <select className="input" aria-label="Type" value={f.type} onChange={(e) => update(f.key, { type: e.target.value as BuilderField['type'] })}>
                      {TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
                    </select>
                  </div>
                  {f.type !== 'boolean' && f.type !== 'array' && (
                    <div className="bl-grid-3">
                      <input className="input" aria-label="Minimum" placeholder={f.type === 'string' ? 'Min length' : 'Minimum'} value={f.min} onChange={(e) => update(f.key, { min: e.target.value })} />
                      <input className="input" aria-label="Maximum" placeholder={f.type === 'string' ? 'Max length' : 'Maximum'} value={f.max} onChange={(e) => update(f.key, { max: e.target.value })} />
                      <input className="input" aria-label="Options" placeholder="Options: a, b, c" value={f.options} onChange={(e) => update(f.key, { options: e.target.value })} />
                    </div>
                  )}
                  {f.type === 'string' && (
                    <div className="bl-grid-2">
                      <input className="input bl-mono" aria-label="Pattern" placeholder="Pattern (regex)" value={f.pattern} onChange={(e) => update(f.key, { pattern: e.target.value })} />
                      <select className="input" aria-label="Format" value={f.format} onChange={(e) => update(f.key, { format: e.target.value })}>
                        <option value="">Plain text</option>
                        <option value="email">Email</option>
                        <option value="date">Date</option>
                      </select>
                    </div>
                  )}
                  <div className="bl-spread">
                    <label className="bl-row"><input type="checkbox" checked={f.required} onChange={(e) => update(f.key, { required: e.target.checked })} /> Required</label>
                    <div className="bl-row">
                      <button type="button" className="btn btn-ghost btn-sm" disabled={index === 0} aria-label="Move field up"
                        onClick={() => { const n = [...fields]; [n[index - 1], n[index]] = [n[index], n[index - 1]]; setFields(n); setPreviewKey((k) => k + 1); }}>↑</button>
                      <button type="button" className="btn btn-ghost btn-sm" aria-label="Remove field" onClick={() => { setFields(fields.filter((x) => x.key !== f.key)); setPreviewKey((k) => k + 1); }}>Remove</button>
                    </div>
                  </div>
                </fieldset>
              ))}
              {canEdit && <div><button className="btn btn-secondary btn-sm" onClick={() => { setFields([...fields, newBuilderField()]); setPreviewKey((k) => k + 1); }}>+ Add field</button></div>}
            </div>
          ) : (
            <div className="bl-stack">
              <textarea className="bl-json" aria-label="JSON Schema" spellCheck={false} value={json} readOnly={!canEdit} onChange={(e) => applyJson(e.target.value)} />
              {jsonError && <span className="bl-field-error" role="alert">{jsonError}</span>}
            </div>
          )}

          {problems.length > 0 && (
            <div className="bl-notice bl-notice-warning bl-small"><ul>{problems.map((p) => <li key={p}>{p}</li>)}</ul></div>
          )}

          {canEdit && (
            <div className="bl-row">
              <button className="btn btn-primary" disabled={saving || problems.length > 0 || !!jsonError} onClick={save}>{saving ? 'Saving…' : 'Save form'}</button>
              {existing && <button className="btn btn-ghost" onClick={remove}>Delete</button>}
            </div>
          )}
        </div>

        <div className="card bl-stack" style={{ padding: 16 }}>
          <span className="bl-label">Live preview</span>
          {Object.keys(schema.properties).length === 0 ? (
            <div className="bl-empty">Add a field to see the form.</div>
          ) : (
            <DynamicFormRenderer key={previewKey} schema={schema} submitLabel="Test submission" serverErrors={serverErrors} onSubmit={testOnServer} />
          )}
          {testResult && <div className="bl-notice bl-small" role="status">{testResult}</div>}
        </div>
      </div>
    </div>
  );
}
