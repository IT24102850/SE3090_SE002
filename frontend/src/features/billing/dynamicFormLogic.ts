import type { JsonSchema, JsonSchemaField } from './billingApi';

/* Dynamic forms: turning a JSON Schema into fields, validating data against
 * it (the same rules the server applies in DynamicFormService, so a form
 * that passes here passes there), and the builder's field list <-> schema
 * round trip. */

export type FormValues = Record<string, unknown>;
export type FieldErrors = Record<string, string>;

const isBlank = (v: unknown) => v === undefined || v === null || (typeof v === 'string' && v.trim() === '');

export function labelFor(name: string, field: JsonSchemaField): string {
  if (field.title) return field.title;
  const spaced = name.replace(/[_-]+/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2');
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

/** The order fields render in: ui:order first, then schema order. */
export function orderedFields(schema: JsonSchema, uiSchema?: Record<string, { 'ui:order'?: number }> | null): [string, JsonSchemaField][] {
  const entries = Object.entries(schema.properties ?? {});
  return entries
    .map((entry, index) => ({ entry, index, order: uiSchema?.[entry[0]]?.['ui:order'] ?? Number.MAX_SAFE_INTEGER }))
    .sort((a, b) => a.order - b.order || a.index - b.index)
    .map((x) => x.entry);
}

/** Converts a raw input value to what the schema type expects. */
export function coerceValue(field: JsonSchemaField, raw: unknown): unknown {
  if (field.type === 'boolean') return raw === true || raw === 'true';
  if (typeof raw !== 'string') return raw;
  if (raw.trim() === '') return undefined;
  if (field.type === 'number') {
    const n = Number(raw);
    return Number.isFinite(n) ? n : raw;
  }
  if (field.type === 'integer') {
    const n = Number(raw);
    return Number.isFinite(n) ? n : raw;
  }
  if (field.type === 'array') return raw.split(',').map((s) => s.trim()).filter(Boolean);
  return raw;
}

export function initialValues(schema: JsonSchema): FormValues {
  const values: FormValues = {};
  for (const [name, field] of Object.entries(schema.properties ?? {})) {
    if (field.default !== undefined) values[name] = field.default;
    else if (field.type === 'boolean') values[name] = false;
  }
  return values;
}

export function validateFormData(schema: JsonSchema, data: FormValues): FieldErrors {
  const errors: FieldErrors = {};
  const properties = schema.properties ?? {};

  for (const name of schema.required ?? []) {
    if (isBlank(data[name])) errors[name] = `${labelFor(name, properties[name] ?? { type: 'string' })} is required.`;
  }

  for (const [name, field] of Object.entries(properties)) {
    if (errors[name]) continue;
    const value = data[name];
    if (isBlank(value)) continue;
    const label = labelFor(name, field);

    switch (field.type) {
      case 'string': {
        if (typeof value !== 'string') { errors[name] = `${label} must be text.`; break; }
        if (field.minLength != null && value.length < field.minLength) errors[name] = `${label} must be at least ${field.minLength} characters.`;
        else if (field.maxLength != null && value.length > field.maxLength) errors[name] = `${label} cannot exceed ${field.maxLength} characters.`;
        else if (field.format === 'email' && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value)) errors[name] = `${label} must be a valid email address.`;
        else if (field.pattern) {
          try {
            if (!new RegExp(field.pattern).test(value)) errors[name] = `${label} is not in the expected format.`;
          } catch {
            // A broken pattern is a form-definition bug, not the user's.
          }
        }
        break;
      }
      case 'number':
      case 'integer': {
        if (typeof value !== 'number' || !Number.isFinite(value)) { errors[name] = `${label} must be a number.`; break; }
        if (field.type === 'integer' && !Number.isInteger(value)) errors[name] = `${label} must be a whole number.`;
        else if (field.minimum != null && value < field.minimum) errors[name] = `${label} must be at least ${field.minimum}.`;
        else if (field.maximum != null && value > field.maximum) errors[name] = `${label} cannot exceed ${field.maximum}.`;
        break;
      }
      case 'boolean':
        if (typeof value !== 'boolean') errors[name] = `${label} must be yes or no.`;
        break;
      case 'array':
        if (!Array.isArray(value)) errors[name] = `${label} must be a list.`;
        break;
      case 'object':
        if (typeof value !== 'object' || Array.isArray(value)) errors[name] = `${label} must be an object.`;
        break;
    }

    if (!errors[name] && field.enum?.length) {
      const matched = field.enum.some((option) => String(option).toLowerCase() === String(value).toLowerCase());
      if (!matched) errors[name] = `${label} must be one of: ${field.enum.join(', ')}.`;
    }
  }

  return errors;
}

// ── Builder ──────────────────────────────────────────────────────────────

export interface BuilderField {
  key: string;
  name: string;
  title: string;
  type: JsonSchemaField['type'];
  required: boolean;
  options: string;      // comma-separated enum values
  min: string;
  max: string;
  pattern: string;
  format: string;
  description: string;
}

let fieldCounter = 0;
export function newBuilderField(partial: Partial<BuilderField> = {}): BuilderField {
  fieldCounter += 1;
  return {
    key: `field-${fieldCounter}`,
    name: `field_${fieldCounter}`,
    title: '',
    type: 'string',
    required: false,
    options: '',
    min: '',
    max: '',
    pattern: '',
    format: '',
    description: '',
    ...partial,
  };
}

export function fieldsToSchema(fields: BuilderField[], title?: string): JsonSchema {
  const properties: Record<string, JsonSchemaField> = {};
  const required: string[] = [];

  for (const f of fields) {
    const name = f.name.trim();
    if (!name) continue;
    const field: JsonSchemaField = { type: f.type };
    if (f.title.trim()) field.title = f.title.trim();
    if (f.description.trim()) field.description = f.description.trim();

    const options = f.options.split(',').map((s) => s.trim()).filter(Boolean);
    if (options.length) field.enum = f.type === 'number' || f.type === 'integer' ? options.map(Number).filter(Number.isFinite) : options;

    const min = f.min.trim() === '' ? undefined : Number(f.min);
    const max = f.max.trim() === '' ? undefined : Number(f.max);
    if (f.type === 'string') {
      if (min !== undefined && Number.isFinite(min)) field.minLength = min;
      if (max !== undefined && Number.isFinite(max)) field.maxLength = max;
      if (f.pattern.trim()) field.pattern = f.pattern.trim();
      if (f.format.trim()) field.format = f.format.trim();
    } else if (f.type === 'number' || f.type === 'integer') {
      if (min !== undefined && Number.isFinite(min)) field.minimum = min;
      if (max !== undefined && Number.isFinite(max)) field.maximum = max;
    }

    properties[name] = field;
    if (f.required) required.push(name);
  }

  return { type: 'object', ...(title ? { title } : {}), properties, ...(required.length ? { required } : {}) };
}

export function schemaToFields(schema: JsonSchema): BuilderField[] {
  const required = new Set(schema.required ?? []);
  return Object.entries(schema.properties ?? {}).map(([name, f]) =>
    newBuilderField({
      name,
      title: f.title ?? '',
      type: f.type,
      required: required.has(name),
      options: (f.enum ?? []).join(', '),
      min: String((f.type === 'string' ? f.minLength : f.minimum) ?? ''),
      max: String((f.type === 'string' ? f.maxLength : f.maximum) ?? ''),
      pattern: f.pattern ?? '',
      format: f.format ?? '',
      description: f.description ?? '',
    }),
  );
}

/** Problems with the form definition itself (the server checks the same). */
export function validateBuilder(formType: string, fields: BuilderField[]): string[] {
  const problems: string[] = [];
  if (!/^[a-z0-9][a-z0-9_-]{1,99}$/.test(formType)) problems.push('The form type must be 2-100 lowercase letters, digits, "-" or "_".');
  if (fields.length === 0) problems.push('Add at least one field.');
  const names = new Set<string>();
  for (const f of fields) {
    const n = f.name.trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(n)) problems.push(`"${n || '(blank)'}" is not a valid field name (letters, digits, "_").`);
    else if (names.has(n)) problems.push(`The field name "${n}" is used twice.`);
    names.add(n);
    if (f.pattern.trim()) {
      try { new RegExp(f.pattern); } catch { problems.push(`The pattern on "${n}" is not a valid regular expression.`); }
    }
  }
  return problems;
}

/** Starting points for the business types the spec lists. */
export const FORM_PRESETS: Record<string, { label: string; schema: JsonSchema }> = {
  'clinic-visit': {
    label: 'Clinic visit billing',
    schema: {
      type: 'object',
      properties: {
        treatment: { type: 'string', title: 'Treatment', enum: ['Consultation', 'Cleaning', 'Filling', 'Extraction', 'X-ray'] },
        tooth: { type: 'string', title: 'Tooth number', pattern: '^[1-8]{2}$' },
        visitFee: { type: 'number', title: 'Visit fee', minimum: 0 },
        insured: { type: 'boolean', title: 'Covered by insurance' },
      },
      required: ['treatment', 'visitFee'],
    },
  },
  'table-bill': {
    label: 'Restaurant table bill',
    schema: {
      type: 'object',
      properties: {
        tableNumber: { type: 'integer', title: 'Table', minimum: 1, maximum: 200 },
        covers: { type: 'integer', title: 'Guests', minimum: 1, maximum: 40 },
        splitWays: { type: 'integer', title: 'Split between', minimum: 1, maximum: 20 },
        couponCode: { type: 'string', title: 'Coupon code', maxLength: 30 },
        serviceCharge: { type: 'boolean', title: 'Add 10% service charge' },
      },
      required: ['tableNumber', 'covers'],
    },
  },
  'tuition-fee': {
    label: 'Tuition fee plan',
    schema: {
      type: 'object',
      properties: {
        student: { type: 'string', title: 'Student name', minLength: 2 },
        grade: { type: 'string', title: 'Grade', enum: ['6', '7', '8', '9', '10', '11', 'A/L'] },
        feeBasis: { type: 'string', title: 'Charged', enum: ['Per class', 'Per month'] },
        installments: { type: 'integer', title: 'Installments', minimum: 1, maximum: 12 },
        guardianEmail: { type: 'string', title: 'Guardian email', format: 'email' },
      },
      required: ['student', 'grade', 'feeBasis'],
    },
  },
  'property-deal': {
    label: 'Real estate deal',
    schema: {
      type: 'object',
      properties: {
        propertyRef: { type: 'string', title: 'Property reference', minLength: 3 },
        dealValue: { type: 'number', title: 'Deal value', minimum: 1 },
        milestones: { type: 'array', title: 'Milestones (comma-separated)' },
        agent: { type: 'string', title: 'Listing agent' },
      },
      required: ['propertyRef', 'dealValue'],
    },
  },
};
