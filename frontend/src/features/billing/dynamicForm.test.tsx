import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import DynamicFormRenderer from './components/DynamicFormRenderer';
import {
  FORM_PRESETS,
  coerceValue,
  fieldsToSchema,
  newBuilderField,
  orderedFields,
  schemaToFields,
  validateBuilder,
  validateFormData,
} from './dynamicFormLogic';
import type { JsonSchema } from './billingApi';

const tableBill = FORM_PRESETS['table-bill'].schema;

describe('dynamic forms - validation (mirrors the server)', () => {
  it('requires required fields', () => {
    expect(validateFormData(tableBill, {})).toEqual({ tableNumber: 'Table is required.', covers: 'Guests is required.' });
  });

  it('checks types, ranges, lengths, patterns and enums', () => {
    const schema: JsonSchema = {
      type: 'object',
      properties: {
        guests: { type: 'integer', minimum: 1, maximum: 10 },
        fee: { type: 'number', minimum: 0 },
        code: { type: 'string', pattern: '^[A-Z]{4}$' },
        email: { type: 'string', format: 'email' },
        name: { type: 'string', minLength: 2, maxLength: 5 },
        plan: { type: 'string', enum: ['Basic', 'Premium'] },
      },
    };
    const errors = validateFormData(schema, { guests: 2.5, fee: -1, code: 'abcd', email: 'nope', name: 'Bartholomew', plan: 'Gold' });
    expect(Object.keys(errors).sort()).toEqual(['code', 'email', 'fee', 'guests', 'name', 'plan']);
    expect(errors.guests).toMatch(/whole number/);
    expect(errors.plan).toMatch(/one of: Basic, Premium/);
    expect(validateFormData(schema, { guests: 3, fee: 10, code: 'ABCD', email: 'a@b.lk', name: 'Anu', plan: 'premium' })).toEqual({});
  });

  it('coerces raw input to the schema type', () => {
    expect(coerceValue({ type: 'integer' }, '4')).toBe(4);
    expect(coerceValue({ type: 'number' }, '')).toBeUndefined();
    expect(coerceValue({ type: 'boolean' }, 'true')).toBe(true);
    expect(coerceValue({ type: 'array' }, 'a, b ,,c')).toEqual(['a', 'b', 'c']);
  });

  it('orders fields by ui:order, then schema order', () => {
    const order = orderedFields(tableBill, { couponCode: { 'ui:order': 1 } }).map(([name]) => name);
    expect(order[0]).toBe('couponCode');
    expect(order.slice(1)).toEqual(['tableNumber', 'covers', 'splitWays', 'serviceCharge']);
  });
});

describe('dynamic forms - builder', () => {
  it('round-trips between builder fields and JSON Schema', () => {
    for (const preset of Object.values(FORM_PRESETS)) {
      expect(fieldsToSchema(schemaToFields(preset.schema))).toEqual({ ...preset.schema, type: 'object' });
    }
  });

  it('turns builder options into typed constraints', () => {
    const schema = fieldsToSchema([
      newBuilderField({ name: 'seats', type: 'integer', min: '1', max: '8', options: '2, 4, 6', required: true }),
      newBuilderField({ name: 'ref', type: 'string', min: '3', pattern: '^R' }),
    ]);
    expect(schema.properties.seats).toEqual({ type: 'integer', minimum: 1, maximum: 8, enum: [2, 4, 6] });
    expect(schema.properties.ref).toEqual({ type: 'string', minLength: 3, pattern: '^R' });
    expect(schema.required).toEqual(['seats']);
  });

  it('catches definition problems before saving', () => {
    const problems = validateBuilder('Table Bill', [
      newBuilderField({ name: 'a' }),
      newBuilderField({ name: 'a' }),
      newBuilderField({ name: '9lives' }),
      newBuilderField({ name: 'ok', pattern: '([' }),
    ]);
    expect(problems.join(' ')).toMatch(/lowercase/);
    expect(problems.join(' ')).toMatch(/used twice/);
    expect(problems.join(' ')).toMatch(/"9lives" is not a valid field name/);
    expect(problems.join(' ')).toMatch(/not a valid regular expression/);
    expect(validateBuilder('table-bill', [newBuilderField({ name: 'table' })])).toEqual([]);
  });
});

describe('<DynamicFormRenderer />', () => {
  it('renders the right control for each field type', () => {
    render(<DynamicFormRenderer schema={FORM_PRESETS['tuition-fee'].schema} onSubmit={() => {}} />);

    expect(screen.getByLabelText(/Student name/)).toHaveAttribute('type', 'text');
    expect(screen.getByLabelText(/Guardian email/)).toHaveAttribute('type', 'email');
    expect(screen.getByLabelText(/Installments/)).toHaveAttribute('type', 'number');
    const grade = screen.getByLabelText(/Grade/);
    expect(grade.tagName).toBe('SELECT');
    expect(Array.from((grade as HTMLSelectElement).options).map((o) => o.value)).toContain('A/L');
  });

  it('renders booleans as checkboxes and marks required fields', () => {
    render(<DynamicFormRenderer schema={tableBill} onSubmit={() => {}} />);
    expect(screen.getByRole('checkbox', { name: /service charge/ })).not.toBeChecked();
    expect(screen.getByLabelText(/Table/)).toHaveAttribute('aria-required', 'true');
    expect(screen.getByLabelText(/Coupon code/)).not.toHaveAttribute('aria-required');
  });

  it('shows errors instead of submitting invalid data', async () => {
    const onSubmit = vi.fn();
    render(<DynamicFormRenderer schema={tableBill} onSubmit={onSubmit} />);

    fireEvent.change(screen.getByLabelText(/Table/), { target: { value: '500' } });
    fireEvent.click(screen.getByRole('button', { name: 'Submit' }));

    expect(await screen.findByText('Table cannot exceed 200.')).toBeInTheDocument();
    expect(screen.getByText('Guests is required.')).toBeInTheDocument();
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it('submits typed values once the form is valid', async () => {
    const onSubmit = vi.fn();
    render(<DynamicFormRenderer schema={tableBill} onSubmit={onSubmit} submitLabel="Save bill" />);

    fireEvent.change(screen.getByLabelText(/Table/), { target: { value: '12' } });
    fireEvent.change(screen.getByLabelText(/Guests/), { target: { value: '4' } });
    fireEvent.click(screen.getByRole('checkbox', { name: /service charge/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Save bill' }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledWith({ tableNumber: 12, covers: 4, serviceCharge: true }));
  });

  it('clears an error as soon as the field is fixed', async () => {
    render(<DynamicFormRenderer schema={tableBill} onSubmit={() => {}} />);
    fireEvent.click(screen.getByRole('button', { name: 'Submit' }));
    expect(await screen.findByText('Guests is required.')).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText(/Guests/), { target: { value: '2' } });
    expect(screen.queryByText('Guests is required.')).not.toBeInTheDocument();
  });

  it('shows errors returned by the server next to the field', () => {
    render(<DynamicFormRenderer schema={tableBill} onSubmit={() => {}} serverErrors={{ couponCode: 'This coupon has expired.' }} />);
    expect(screen.getByRole('alert')).toHaveTextContent('This coupon has expired.');
  });
});
