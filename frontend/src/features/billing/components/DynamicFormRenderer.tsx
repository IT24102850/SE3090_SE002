import { useState, type FormEvent } from 'react';
import type { DynamicForm, JsonSchema, JsonSchemaField } from '../billingApi';
import {
  coerceValue,
  initialValues,
  labelFor,
  orderedFields,
  validateFormData,
  type FieldErrors,
  type FormValues,
} from '../dynamicFormLogic';

/* Renders any business-specific form from its JSON Schema: the field types,
 * required markers, enums as selects and client-side validation all come
 * from the schema, so a form built in the Form Builder needs no code. */

interface Props {
  schema: JsonSchema;
  uiSchema?: DynamicForm['uiSchema'];
  submitLabel?: string;
  busy?: boolean;
  /** Server-side errors to show next to fields after a submit. */
  serverErrors?: FieldErrors;
  onSubmit: (values: FormValues) => void | Promise<void>;
}

export default function DynamicFormRenderer({ schema, uiSchema, submitLabel = 'Submit', busy, serverErrors, onSubmit }: Props) {
  const [values, setValues] = useState<FormValues>(() => initialValues(schema));
  const [errors, setErrors] = useState<FieldErrors>({});
  const [touched, setTouched] = useState(false);
  const required = new Set(schema.required ?? []);

  const setValue = (name: string, field: JsonSchemaField, raw: unknown) => {
    const next = { ...values, [name]: coerceValue(field, raw) };
    setValues(next);
    if (touched) setErrors(validateFormData(schema, next));
  };

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setTouched(true);
    const found = validateFormData(schema, values);
    setErrors(found);
    if (Object.keys(found).length > 0) return;
    const clean = Object.fromEntries(Object.entries(values).filter(([, v]) => v !== undefined));
    await onSubmit(clean);
  };

  const shown = { ...serverErrors, ...errors };

  return (
    <form className="bl-form" onSubmit={submit} noValidate aria-label={schema.title ?? 'Dynamic form'}>
      {orderedFields(schema, uiSchema).map(([name, field]) => {
        const id = `df-${name}`;
        const label = labelFor(name, field);
        const error = shown[name];
        const widget = uiSchema?.[name]?.['ui:widget'];
        const placeholder = uiSchema?.[name]?.['ui:placeholder'];
        const value = values[name];
        const common = {
          id,
          name,
          'aria-invalid': error ? true : undefined,
          'aria-describedby': error ? `${id}-error` : undefined,
          'aria-required': required.has(name) || undefined,
        } as const;

        let input: JSX.Element;
        if (field.type === 'boolean') {
          input = (
            <label className="bl-row" style={{ fontWeight: 500 }}>
              <input type="checkbox" {...common} checked={value === true} onChange={(e) => setValue(name, field, e.target.checked)} />
              {label}
            </label>
          );
        } else if (field.enum?.length) {
          input = (
            <select className="input" {...common} value={value === undefined ? '' : String(value)} onChange={(e) => setValue(name, field, e.target.value)}>
              <option value="">Choose…</option>
              {field.enum.map((option) => <option key={String(option)} value={String(option)}>{String(option)}</option>)}
            </select>
          );
        } else if (widget === 'textarea') {
          input = <textarea className="input" rows={3} {...common} placeholder={placeholder} value={(value as string) ?? ''} onChange={(e) => setValue(name, field, e.target.value)} />;
        } else {
          const type = field.type === 'number' || field.type === 'integer' ? 'number' : field.format === 'email' ? 'email' : field.format === 'date' ? 'date' : 'text';
          const display = Array.isArray(value) ? value.join(', ') : value === undefined || value === null ? '' : String(value);
          input = (
            <input
              className="input"
              type={type}
              step={field.type === 'integer' ? 1 : field.type === 'number' ? 'any' : undefined}
              min={field.minimum}
              max={field.maximum}
              maxLength={field.maxLength}
              placeholder={placeholder ?? (field.type === 'array' ? 'Separate items with commas' : undefined)}
              {...common}
              value={display}
              onChange={(e) => setValue(name, field, e.target.value)}
            />
          );
        }

        return (
          <div className="bl-field" key={name}>
            {field.type !== 'boolean' && (
              <label htmlFor={id} className="bl-label">
                {label}{required.has(name) && <span aria-hidden="true" style={{ color: 'var(--color-critical)' }}> *</span>}
              </label>
            )}
            {input}
            {field.description && <span className="bl-field-hint">{field.description}</span>}
            {error && <span className="bl-field-error" id={`${id}-error`} role="alert">{error}</span>}
          </div>
        );
      })}
      <div>
        <button className="btn btn-primary" type="submit" disabled={busy}>{busy ? 'Working…' : submitLabel}</button>
      </div>
    </form>
  );
}
