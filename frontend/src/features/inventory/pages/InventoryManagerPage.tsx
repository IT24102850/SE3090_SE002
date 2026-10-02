import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { QRCodeSVG } from 'qrcode.react';
import { RootState } from '../../../store/store';
import { Badge, type BadgeTone } from '../ui/Badge';
import { useToast } from '../ui/ToastContext';
import { Icon } from '../ui/Icon';
import { getStoredToken } from '../authToken';
import ConfirmDialog from '../../../shared/components/ConfirmDialog';

type StockStatus = 'In stock' | 'Low stock' | 'Out of stock';

type StockRow = {
  id?: string;
  categoryId?: string;
  unitId?: string;
  branchId?: string;
  supplierId?: string;
  sku: string;
  item: string;
  category: string;
  unit: string;
  costPrice: number | null;
  sellingPrice: number | null;
  qty: number;
  reorder: number;
  owner: string;
};

type StockForm = Omit<StockRow, 'sku'> & {
  branchStocks?: Array<{ branchId: string; quantity: number }>;
};
type SupplierOption = { id: string; name: string; leadTimeDays: number | null };
type InventoryCategoryOption = { id: string; name: string };
type InventoryBranchOption = { id: string; name: string };

const PAGE_SIZE = 5;

const categoryOptions = ['Office essentials', 'Technology', 'Provisions', 'Print & marketing', 'Other items'];
const categories = ['All categories', ...categoryOptions];
const statusFilters = ['All statuses', 'In stock', 'Low stock', 'Out of stock'] as const;
type StatusFilter = (typeof statusFilters)[number];

const statusTone: Record<StockStatus, BadgeTone> = {
  'In stock': 'green',
  'Low stock': 'amber',
  'Out of stock': 'red',
};

const emptyForm: StockForm = {
  item: '',
  category: categoryOptions[0],
  unit: '',
  costPrice: null,
  sellingPrice: null,
  qty: 0,
  reorder: 10,
  owner: '',
  supplierId: undefined,
};

function deriveStatus(qty: number, reorder: number): StockStatus {
  if (qty <= 0) return 'Out of stock';
  if (reorder > 0 && qty <= reorder) return 'Low stock';
  return 'In stock';
}

function formatPrice(amount: number) {
  return `LKR ${amount.toLocaleString()}`;
}

function parseCsvRow(line: string): string[] {
  const values: string[] = [];
  let value = '';
  let quoted = false;
  for (let index = 0; index < line.length; index++) {
    const character = line[index];
    if (character === '"' && quoted && line[index + 1] === '"') {
      value += '"';
      index++;
    } else if (character === '"') {
      quoted = !quoted;
    } else if (character === ',' && !quoted) {
      values.push(value.trim());
      value = '';
    } else {
      value += character;
    }
  }
  values.push(value.trim());
  return values;
}

function displayCategory(category: string | null | undefined, itemName: string, availableCategories: InventoryCategoryOption[] = []) {
  const storedCategory = category?.trim();
  const genericCategory = storedCategory && /^(other|other items|general|uncategorized|supplies)$/i.test(storedCategory);
  if (storedCategory && !genericCategory) return storedCategory;
  const normalized = itemName.toLowerCase();
  const healthcareRules: Array<[RegExp, RegExp, RegExp]> = [
    [/\b(pharmaceutical|medicine|medication|tablet|capsule|drug|pharma|vaccine|antibiotic|paracetamol|syrup|ointment)\b/i, /pharma|medicine|medication|drug/i, /suppl|general|other/i],
    [/\b(glove|mask|gown|apron|face shield|respirator|protective equipment|ppe)\b/i, /ppe|protective/i, /suppl|general|other/i],
    [/\b(syringe|needle|bandage|gauze|cotton|thermometer|stethoscope|iv set|surgical|wound|medical|first aid|test kit|specimen)\b/i, /medical|clinical/i, /suppl|equipment|general|other/i],
    [/\b(paper|pen|stationery|office|folder|printer)\b/i, /office|stationery|admin/i, /suppl|general|other/i],
  ];
  for (const [itemPattern, categoryPattern, fallbackPattern] of healthcareRules) {
    if (itemPattern.test(normalized)) {
      const match = availableCategories.find((option) => categoryPattern.test(option.name))
        ?? availableCategories.find((option) => fallbackPattern.test(option.name));
      if (match) return match.name;
    }
  }
  if (storedCategory) return storedCategory;
  if (availableCategories.length) {
    return availableCategories.find((option) => /other|general|misc/i.test(option.name))?.name ?? 'Uncategorized';
  }
  if (/(laptop|computer|usb|printer|electronic|tech)/.test(normalized)) return 'Technology';
  if (/(paper|cabinet|marker|stationery|office|desk|chair)/.test(normalized)) return 'Office essentials';
  if (/(water|rice|food|beverage|coffee|sugar|milk|provision)/.test(normalized)) return 'Provisions';
  if (/(toner|card|print|marketing|brochure)/.test(normalized)) return 'Print & marketing';
  return 'Other items';
}

function nextSku(items: StockRow[]) {
  const max = items.reduce((acc, row) => {
    const num = parseInt(row.sku.replace(/\D/g, ''), 10);
    return Number.isFinite(num) ? Math.max(acc, num) : acc;
  }, 0);
  return `SKU-${String(max + 1).padStart(5, '0')}`;
}

function Stars({ rating }: { rating: number }) {
  return (
    <span className="stars" aria-label={`${rating} out of 5`}>
      {[1, 2, 3, 4, 5].map((star) => (
        <span key={star} className={star <= rating ? 'star-on' : 'star-off'}>★</span>
      ))}
    </span>
  );
}

void Stars;

function ItemModal({
  title,
  isEditing,
  initial,
  onClose,
  onSave,
  saving,
  suppliers,
  categories: inventoryCategories,
  branches,
  defaultBranchId,
}: {
  title: string;
  isEditing: boolean;
  initial: StockForm;
  onClose: () => void;
  onSave: (form: StockForm) => void;
  saving: boolean;
  suppliers: SupplierOption[];
  categories: InventoryCategoryOption[];
  branches: InventoryBranchOption[];
  defaultBranchId?: string;
}) {
  const [form, setForm] = useState(initial);
  const [error, setError] = useState('');
  const [confirmOpen, setConfirmOpen] = useState(false);
  const defaultSelectedBranchId = initial.branchId ?? defaultBranchId ?? branches[0]?.id;
  const [selectedBranchIds, setSelectedBranchIds] = useState<string[]>(() =>
    initial.branchStocks?.map((stock) => stock.branchId) ??
      (defaultSelectedBranchId ? [defaultSelectedBranchId] : []),
  );
  const [branchQuantities, setBranchQuantities] = useState<Record<string, number>>(() =>
    Object.fromEntries(
      initial.branchStocks?.map((stock) => [stock.branchId, stock.quantity]) ??
        (defaultSelectedBranchId ? [[defaultSelectedBranchId, initial.qty]] : []),
    ),
  );

  function update<K extends keyof StockForm>(key: K, value: StockForm[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (!form.item.trim()) {
      setError('Item name is required.');
      return;
    }
    if (!isEditing && inventoryCategories.length && !form.categoryId) {
      setError('Choose a category for this inventory item.');
      return;
    }
    if (!form.unit.trim()) {
      setError('Unit is required.');
      return;
    }
    if (selectedBranchIds.length === 0) {
      setError('Select at least one branch to update or add this item.');
      return;
    }
    if ((form.costPrice ?? 0) < 0 ||
        (form.sellingPrice ?? 0) < 0 ||
        form.qty < 0 ||
        form.reorder < 0) {
      setError('Prices, quantity, and reorder level must be zero or greater.');
      return;
    }
    if (selectedBranchIds.some((branchId) => (branchQuantities[branchId] ?? 0) < 0)) {
      setError('Branch stock quantities cannot be negative.');
      return;
    }
    if (form.costPrice != null &&
        form.sellingPrice != null &&
        form.sellingPrice <= form.costPrice) {
      setError('Selling price must be greater than unit cost to make a profit.');
      return;
    }
    setConfirmOpen(true);
  }

  function confirmSave() {
    setConfirmOpen(false);
    onSave({
      ...form,
      branchStocks: selectedBranchIds.map((branchId) => ({
        branchId,
        quantity: Number(branchQuantities[branchId] ?? 0),
      })),
    });
  }

  return (
    <div className="modal-overlay" onClick={onClose} role="presentation">
      <div className="modal" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="item-modal-title">
        <div className="modal-head">
          <h2 id="item-modal-title">{title}</h2>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close">×</button>
        </div>
        <form className="modal-body" onSubmit={handleSubmit}>
          {error && <p className="modal-error" role="alert">{error}</p>}
          <div className="form-grid">
            <label className="form-field form-field-wide">
              Item name
              <input value={form.item} onChange={(event) => update('item', event.target.value)} placeholder="e.g. Premium Coffee Beans" />
            </label>
            <fieldset className="form-field form-field-wide inventory-branch-stock-field">
                <legend>{isEditing ? 'Branches and stock' : 'Branches and starting stock'}</legend>
                <p>
                  {isEditing
                    ? 'Selected branches will be updated. Selecting another branch adds this item there; unselected branches stay unchanged.'
                    : 'Choose where this item should be tracked. Each branch keeps its own stock quantity.'}
                </p>
                {branches.length === 0 ? (
                  <p role="status">No branches are available for your account.</p>
                ) : (
                  <div className="inventory-branch-stock-list">
                    {branches.map((branch) => {
                      const selected = selectedBranchIds.includes(branch.id);
                      return (
                        <div className="inventory-branch-stock-row" key={branch.id}>
                          <label>
                            <input
                              type="checkbox"
                              checked={selected}
                              onChange={(event) => {
                                setSelectedBranchIds((current) =>
                                  event.target.checked
                                    ? [...current, branch.id]
                                    : current.filter((id) => id !== branch.id),
                                );
                              }}
                            />
                            {branch.name}
                          </label>
                          {selected && (
                            <label>
                              {isEditing ? 'On-hand stock' : 'Starting stock'}
                              <input
                                aria-label={`${isEditing ? 'On-hand stock' : 'Starting stock'} for ${branch.name}`}
                                type="number"
                                min={0}
                                step="0.001"
                                value={branchQuantities[branch.id] ?? 0}
                                onChange={(event) =>
                                  setBranchQuantities((current) => ({
                                    ...current,
                                    [branch.id]: Number(event.target.value),
                                  }))
                                }
                              />
                            </label>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
            </fieldset>
            <label className="form-field">
              Category
              <select
                value={inventoryCategories.length ? (form.categoryId ?? '') : form.category}
                onChange={(event) => {
                  const selected = inventoryCategories.find((option) => option.id === event.target.value);
                  setForm((previous) => ({
                    ...previous,
                    category: selected?.name ?? event.target.value,
                    categoryId: selected?.id,
                  }));
                }}
              >
                {inventoryCategories.length
                  ? <>
                    <option value="">Uncategorized — choose a category</option>
                    {inventoryCategories.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}
                  </>
                  : categoryOptions.map((option) => <option key={option}>{option}</option>)}
              </select>
            </label>
            <label className="form-field">
              Unit
              <input value={form.unit} onChange={(event) => update('unit', event.target.value)} placeholder="e.g. kg, bag, pack" />
            </label>
            <label className="form-field">
              Unit cost (LKR)
              <input type="number" min={0} step="0.01" value={form.costPrice ?? ''} onChange={(event) => update('costPrice', event.target.value === '' ? null : Number(event.target.value))} />
            </label>
            <label className="form-field">
              Selling price (LKR)
              <input type="number" min={0} step="0.01" value={form.sellingPrice ?? ''} onChange={(event) => update('sellingPrice', event.target.value === '' ? null : Number(event.target.value))} />
            </label>
            <label className="form-field">
              Reorder level
              <input type="number" min={0} step={1} value={form.reorder || ''} onChange={(event) => update('reorder', Number(event.target.value))} />
            </label>
            <label className="form-field form-field-wide">
              Preferred supplier for AI planning
              <select value={form.supplierId ?? ''} onChange={(event) => update('supplierId', event.target.value || undefined)}>
                <option value="">No supplier assigned</option>
                {suppliers.map((supplier) => <option key={supplier.id} value={supplier.id}>{supplier.name}{supplier.leadTimeDays ? ` (${supplier.leadTimeDays} days)` : ' (lead time not set)'}</option>)}
              </select>
            </label>
          </div>
          {form.costPrice != null &&
            form.sellingPrice != null &&
            form.sellingPrice > form.costPrice && (
              <p className="modal-hint" aria-live="polite">
                Gross profit per unit: {formatPrice(form.sellingPrice - form.costPrice)}
              </p>
            )}
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Saving…' : 'Save item'}</button>
          </div>
        </form>
      </div>
      {confirmOpen && (
        <ConfirmDialog
          title={title.startsWith('Add') ? 'Add this item to inventory?' : 'Save inventory changes?'}
          message={title.startsWith('Add')
            ? `Create "${form.item}" for ${selectedBranchIds.length} ${selectedBranchIds.length === 1 ? 'branch' : 'branches'} with separate starting stock?`
            : `Update "${form.item}" in ${selectedBranchIds.length} selected ${selectedBranchIds.length === 1 ? 'branch' : 'branches'}? Other branches will stay unchanged.`}
          confirmLabel={title.startsWith('Add') ? 'Add item' : 'Save changes'}
          onConfirm={confirmSave}
          onCancel={() => setConfirmOpen(false)}
        />
      )}
    </div>
  );
}

export function InventoryManagerPage() {
  const { notify } = useToast();
  const token = getStoredToken();
  const { user } = useSelector((state: RootState) => state.auth);
  const isAdmin = user?.role === 'Admin';
  const canManageCatalog = isAdmin || user?.role === 'Manager';
  const assignedBranchId = isAdmin ? undefined : user?.branchId;
  const [searchParams] = useSearchParams();
  const [items, setItems] = useState<StockRow[]>([]);
  const [suppliers, setSuppliers] = useState<SupplierOption[]>([]);
  const [inventoryCategories, setInventoryCategories] = useState<InventoryCategoryOption[]>([]);
  const [branches, setBranches] = useState<InventoryBranchOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [query, setQuery] = useState(() => searchParams.get('search') ?? '');
  const [category, setCategory] = useState(categories[0]);
  const [status, setStatus] = useState<StatusFilter>(statusFilters[0]);
  const [branchFilter, setBranchFilter] = useState(isAdmin ? 'All branches' : assignedBranchId ?? '');
  const [page, setPage] = useState(1);
  const [modal, setModal] = useState<{ mode: 'add' } | { mode: 'edit'; id: string } | null>(null);
  const [qrItem, setQrItem] = useState<StockRow | null>(null);
  const [deleteItemId, setDeleteItemId] = useState<string | null>(null);
  const [importing, setImporting] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const categoryFilterOptions = useMemo(() => [
    categories[0],
    ...Array.from(new Set([
      ...(inventoryCategories.length ? inventoryCategories.map((option) => option.name) : categoryOptions),
      ...items.map((row) => row.category),
    ].filter((value) => value && value !== categories[0]))).sort((a, b) => a.localeCompare(b)),
  ], [inventoryCategories, items]);

  const filtered = useMemo(() => {
    const queryLower = query.trim().toLowerCase();
    return items.filter((row) => {
      const rowStatus = deriveStatus(row.qty, row.reorder);
      const matchesQuery =
        queryLower === '' ||
        row.item.toLowerCase().includes(queryLower) ||
        row.sku.toLowerCase().includes(queryLower) ||
        row.owner.toLowerCase().includes(queryLower) ||
        row.category.toLowerCase().includes(queryLower) ||
        row.unit.toLowerCase().includes(queryLower);
      const matchesCategory = category === 'All categories' || row.category === category;
      const matchesStatus = status === 'All statuses' || rowStatus === status;
      const matchesBranch = isAdmin
        ? branchFilter === 'All branches' || row.branchId === branchFilter
        : Boolean(assignedBranchId) && row.branchId === assignedBranchId;
      return matchesQuery && matchesCategory && matchesStatus && matchesBranch;
    });
  }, [assignedBranchId, branchFilter, category, isAdmin, items, query, status]);

  const groupedFiltered = useMemo(() => {
    const groups = new Map<string, StockRow[]>();
    filtered.forEach((row) => {
      const key = row.sku.trim().toLowerCase();
      const rows = groups.get(key) ?? [];
      rows.push(row);
      groups.set(key, rows);
    });
    return Array.from(groups, ([key, rows]) => ({
      key,
      rows: rows.sort((first, second) => first.owner.localeCompare(second.owner)),
      primary: rows[0],
      totalQuantity: rows.reduce((total, row) => total + row.qty, 0),
    }));
  }, [filtered]);

  const totalPages = Math.max(1, Math.ceil(groupedFiltered.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);

  const paged = useMemo(() => {
    const start = (safePage - 1) * PAGE_SIZE;
    return groupedFiltered.slice(start, start + PAGE_SIZE);
  }, [groupedFiltered, safePage]);

  useEffect(() => {
    setPage(1);
  }, [query, category, status, branchFilter]);

  useEffect(() => {
    if (page > totalPages) setPage(totalPages);
  }, [page, totalPages]);

  const stats = useMemo(() => {
    const total = items.reduce((sum, row) => sum + row.qty, 0);
    const productGroups = new Map<string, StockRow[]>();
    items.forEach((row) => {
      const key = row.sku.trim().toLowerCase();
      const rows = productGroups.get(key) ?? [];
      rows.push(row);
      productGroups.set(key, rows);
    });
    const productRows = Array.from(productGroups.values());
    const low = productRows.filter((rows) =>
      rows.some((row) => deriveStatus(row.qty, row.reorder) === 'Low stock') &&
      !rows.every((row) => deriveStatus(row.qty, row.reorder) === 'Out of stock'),
    ).length;
    const out = productRows.filter((rows) =>
      rows.every((row) => deriveStatus(row.qty, row.reorder) === 'Out of stock'),
    ).length;
    const value = items.reduce((sum, row) => sum + row.qty * (row.costPrice ?? 0), 0);
    const categories = new Set(items.map((row) => row.category).filter(Boolean)).size;
    return { items: productRows.length, total, low, out, value, categories };
  }, [items]);

  const editingItem = modal?.mode === 'edit' ? items.find((row) => row.id === modal.id) : undefined;

  async function loadInventory(categoryOptionsForItems = inventoryCategories): Promise<boolean> {
    setLoading(true);
    setLoadError('');
    try {
      if (!isAdmin && !assignedBranchId) {
        throw new Error('Your account has no assigned branch. Inventory is unavailable until one is assigned.');
      }
      const headers = { Accept: 'application/json', Authorization: token ? 'Bearer ' + token : '' };
      const params = new URLSearchParams({ page: '1', pageSize: '100' });
      if (assignedBranchId) params.set('branchId', assignedBranchId);
      const firstResponse = await fetch(`/api/inventory?${params}`, { headers });
      if (!firstResponse.ok) {
        const errorBody = await firstResponse.json().catch(() => null);
        throw new Error(errorBody?.message || errorBody?.title || `Inventory request failed (${firstResponse.status})`);
      }
      const firstPage = await firstResponse.json();
      const totalPages = Math.max(1, Number(firstPage.totalPages) || 1);
      const remainingPages = await Promise.all(
        Array.from({ length: totalPages - 1 }, async (_, index) => {
          const pageParams = new URLSearchParams({ page: String(index + 2), pageSize: '100' });
          if (assignedBranchId) pageParams.set('branchId', assignedBranchId);
          const response = await fetch(`/api/inventory?${pageParams}`, { headers });
          if (!response.ok) throw new Error(`Inventory page ${index + 2} failed (${response.status})`);
          return response.json();
        }),
      );
      const allRows = [firstPage, ...remainingPages].flatMap((pageData) => pageData.items ?? []);
      const scopedRows = isAdmin
        ? allRows
        : allRows.filter((item: any) => item.branchId === assignedBranchId);
      setItems(scopedRows.map((item: any): StockRow => ({
        id: item.id,
        sku: item.sku,
        item: item.name,
        category: displayCategory(item.category, item.name, categoryOptionsForItems),
        unit: item.unit ?? 'unit',
        categoryId: item.categoryId ?? undefined,
        unitId: item.unitId ?? undefined,
        branchId: item.branchId ?? undefined,
        supplierId: item.supplierId ?? undefined,
        costPrice: item.unitCost == null ? null : Number(item.unitCost),
        sellingPrice: item.sellingPrice == null ? null : Number(item.sellingPrice),
        qty: Number(item.quantity ?? 0),
        reorder: Number(item.reorderLevel ?? 0),
        owner: item.branch ?? 'Inventory Admin',
      })));
    } catch (error) {
      console.error(error);
      const message = error instanceof Error ? error.message : 'Unable to load inventory from the database.';
      setLoadError(`${message} Refresh and try again.`);
      notify(message, 'error');
      return false;
    } finally {
      setLoading(false);
    }
    return true;
  }

  function exportInventoryCsv() {
    if (!items.length) {
      notify('No inventory items to export.', 'warning');
      return;
    }
    const header = 'Item,SKU,Category,On Hand,Unit,Reorder Level,Unit Cost (LKR),Selling Price (LKR),Owner';
    const lines = items.map(r =>
      [r.item, r.sku, r.category, r.qty, r.unit, r.reorder, r.costPrice ?? '', r.sellingPrice ?? '', r.owner]
        .map(v => `"${String(v).replace(/"/g, '""')}"`)
        .join(',')
    );
    const blob = new Blob([[header, ...lines].join('\n')], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `inventory-catalog-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    notify(`Exported ${items.length} inventory items to CSV.`, 'success');
  }

  async function handleCsvImport(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (!canManageCatalog || (!isAdmin && !assignedBranchId)) return;
    setImporting(true);
    try {
      const text = await file.text();
      const lines = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
      if (lines.length < 2) {
        throw new Error('CSV file is empty or missing headers.');
      }
      // Simple parse: skip header
      let createdCount = 0;
      let failedCount = 0;
      const stagedItems = [...items];
      for (let i = 1; i < lines.length; i++) {
        const cols = parseCsvRow(lines[i]);
        if (!cols[0]) continue;
        const name = cols[0];
        const category = cols[2] || inventoryCategories[0]?.name || categoryOptions[0];
        const categoryId = inventoryCategories.find((option) => option.name.toLowerCase() === category.toLowerCase())?.id;
        const qty = Number(cols[3]) || 0;
        const unit = cols[4] || 'unit';
        const reorder = Number(cols[5]) || 10;
        const costPrice = Number(cols[6]) || 0;
        const importedSellingPrice = Number(cols[7]);
        const sellingPrice = cols[7] && Number.isFinite(importedSellingPrice)
          ? importedSellingPrice
          : null;
        const sku = nextSku(stagedItems);
        const res = await fetch('/api/inventory', {
          method: 'POST',
          headers: { Accept: 'application/json', 'Content-Type': 'application/json', Authorization: token ? 'Bearer ' + token : '' },
          body: JSON.stringify({
            name,
            sku,
            description: `${category} (${unit})`,
            categoryId: categoryId ?? null,
            category,
            quantity: qty,
            reorderLevel: reorder,
            unitCost: costPrice,
            sellingPrice,
            branchId: user?.branchId ?? null,
          }),
        });
        if (res.ok) {
          createdCount++;
          stagedItems.push({ sku, item: name, category, unit, costPrice, sellingPrice, qty, reorder, owner: 'Inventory Admin' });
        } else {
          failedCount++;
        }
      }
      await loadInventory();
      notify(
        failedCount
          ? `Imported ${createdCount} items. ${failedCount} rows could not be imported.`
          : `Successfully imported ${createdCount} items from CSV.`,
        failedCount ? 'warning' : 'success',
      );
    } catch (err: any) {
      notify(err?.message || 'Failed to import CSV.', 'error');
    } finally {
      setImporting(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  }

  useEffect(() => {
    let active = true;
    async function loadCategoriesAndInventory() {
      let options: InventoryCategoryOption[] = [];
      try {
        const response = await fetch('/api/inventory/categories', {
          headers: { Accept: 'application/json', Authorization: token ? `Bearer ${token}` : '' },
        });
        if (!response.ok) throw new Error(`Inventory categories request failed (${response.status})`);
        const result = await response.json();
        options = Array.isArray(result) ? result : [];
        if (active) setInventoryCategories(options);
      } catch (error) {
        console.error(error);
      }
      if (active) await loadInventory(options);
    }
    void loadCategoriesAndInventory();
    return () => { active = false; };
  }, [token, assignedBranchId, isAdmin]);

  useEffect(() => {
    let active = true;
    void fetch('/api/inventory/branches', {
      headers: { Accept: 'application/json', Authorization: token ? `Bearer ${token}` : '' },
    })
      .then(async (response) => {
        if (!response.ok) throw new Error(`Branch request failed (${response.status})`);
        return response.json();
      })
      .then((result) => {
        if (active) setBranches(Array.isArray(result) ? result : []);
      })
      .catch((error) => {
        console.error(error);
        if (active) {
          const message = error instanceof Error ? error.message : 'Unable to load branches.';
          notify(message, 'error');
        }
      });
    return () => { active = false; };
  }, [notify, token]);

  useEffect(() => {
    let active = true;
    void fetch('/api/suppliers', { headers: { Accept: 'application/json', Authorization: token ? `Bearer ${token}` : '' } })
      .then(async (response) => {
        if (!response.ok) throw new Error(`Supplier request failed (${response.status})`);
        return response.json();
      })
      .then((result) => { if (active) setSuppliers(Array.isArray(result.items) ? result.items : []); })
      .catch((error) => { console.error(error); });
    return () => { active = false; };
  }, [token, assignedBranchId, isAdmin]);

  async function handleRefresh() {
    if (await loadInventory()) {
      notify('Inventory refreshed.', 'success');
    }
  }

  async function handleSave(form: StockForm) {
    setSaving(true);
    try {
      const existing = modal?.mode === 'edit' ? items.find((row) => row.id === modal.id) : undefined;
      const path = existing?.id ? `/api/inventory/${existing.id}` : '/api/inventory';
      const method = existing?.id ? 'PUT' : 'POST';
      const response = await fetch(path, {
        method,
        headers: { Accept: 'application/json', 'Content-Type': 'application/json', Authorization: token ? 'Bearer ' + token : '' },
        body: JSON.stringify({
          name: form.item,
          sku: existing?.sku ?? nextSku(items),
          description: null,
          categoryId: form.categoryId ?? existing?.categoryId ?? null,
          category: existing && !form.categoryId ? null : form.category,
          unitId: existing?.unitId ?? null,
          branchId: null,
          branchStocks: form.branchStocks,
          reorderLevel: form.reorder,
          unitCost: form.costPrice,
          sellingPrice: form.sellingPrice,
          supplierId: form.supplierId ?? null,
          ...(existing ? { clearSupplier: !form.supplierId } : {}),
        }),
      });
      if (!response.ok) {
        const errJson = await response.json().catch(() => null);
        const validationErrors = errJson?.errors;
        const fieldErrors = validationErrors && typeof validationErrors === 'object'
          ? Object.values(validationErrors).flat().filter((message): message is string => typeof message === 'string')
          : [];
        const errDetail = fieldErrors.length
          ? fieldErrors.join(' ')
          : errJson?.message || errJson?.title || `Save failed (${response.status})`;
        throw new Error(errDetail);
      }
      await loadInventory();
      setModal(null);
      notify(`${form.item} was successfully ${existing ? 'updated' : 'added'} in inventory.`, 'success');
    } catch (error: any) {
      console.error(error);
      notify(error?.message || 'Inventory could not be saved. Check your connection and permissions.', 'error');
    } finally {
      setSaving(false);
    }
  }

  async function confirmDelete() {
    if (!deleteItemId) return;
    const item = items.find((row) => row.id === deleteItemId);
    if (!item?.id) {
      setDeleteItemId(null);
      notify('This inventory item is missing its database ID. Refresh and try again.', 'warning');
      return;
    }
    try {
      const response = await fetch(`/api/inventory/${item.id}`, {
        method: 'DELETE',
        headers: { Accept: 'application/json', Authorization: token ? 'Bearer ' + token : '' },
      });
      if (!response.ok) {
        const errJson = await response.json().catch(() => null);
        throw new Error(errJson?.message || `Delete failed (${response.status})`);
      }
      await loadInventory();
      setDeleteItemId(null);
      notify(`${item.item} was successfully deleted from inventory.`, 'success');
    } catch (error: any) {
      console.error(error);
      notify(error?.message || 'Inventory item could not be deleted.', 'error');
    }
  }

  const rangeStart = groupedFiltered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1;
  const rangeEnd = Math.min(safePage * PAGE_SIZE, groupedFiltered.length);
  const hasActiveFilters = Boolean(query.trim()) ||
    category !== categories[0] ||
    status !== statusFilters[0] ||
    branchFilter !== 'All branches';

  return (
    <div className="page inventory-manager-page">
      <header className="inventory-manager-hero">
        <span className="inventory-hero-sheen" aria-hidden="true" />
        <span className="inventory-hero-ambient" aria-hidden="true"><i /></span>
        <div className="inventory-manager-hero-copy">
          <p className="inventory-manager-eyebrow"><span aria-hidden="true">◆</span> INVENTORY CONTROL CENTER</p>
          <h1>Inventory manager</h1>
          <p>One clear view of your stock, item health, and inventory value.</p>
          <div className="inventory-manager-health" aria-live="polite">
            <span className={`inventory-manager-health-dot${loading ? ' is-loading' : ''}`} aria-hidden="true" />
            {loading ? 'Updating live inventory…' : `${stats.items} ${stats.items === 1 ? 'product' : 'products'} tracked`}
            <span className="inventory-manager-health-separator">·</span>
            {stats.low + stats.out === 0 ? 'All stock levels look healthy' : `${stats.low + stats.out} items need attention`}
          </div>
        </div>
        <div className="inventory-manager-hero-art" aria-hidden="true">
          <span className="inventory-manager-orbit inventory-manager-orbit-one" />
          <span className="inventory-manager-orbit inventory-manager-orbit-two" />
          <span className="inventory-manager-cube">▦</span>
          <span className="inventory-manager-art-label">STOCK<br />VISIBILITY</span>
        </div>
        <div className="page-actions">
          <input
            type="file"
            ref={fileInputRef}
            accept=".csv"
            style={{ display: 'none' }}
            onChange={handleCsvImport}
          />
          <button className="btn btn-secondary inventory-manager-refresh" type="button" onClick={() => void handleRefresh()} disabled={loading}><span aria-hidden="true">↻</span> {loading ? 'Refreshing…' : 'Refresh data'}</button>
          {canManageCatalog && <button className="btn btn-secondary" type="button" onClick={() => fileInputRef.current?.click()} disabled={importing || loading} title="Import items from CSV file"><span aria-hidden="true">⇧</span> {importing ? 'Importing…' : 'Import CSV'}</button>}
          <button className="btn btn-secondary" type="button" onClick={exportInventoryCsv} title="Export inventory catalogue as CSV"><span aria-hidden="true">⇩</span> Export CSV</button>
          {canManageCatalog && <Link className="btn btn-secondary inventory-manager-suppliers-link" to="/suppliers"><span aria-hidden="true">♧</span> Suppliers</Link>}
          {canManageCatalog && <button className="btn btn-primary inventory-manager-add" type="button" onClick={() => setModal({ mode: 'add' })}><span aria-hidden="true">＋</span> Add item</button>}
        </div>
      </header>
      {loadError && <p className="page-notice">{loadError}</p>}
      {loading && <div className="inventory-manager-loading" role="status"><span className="inventory-manager-loading-dot" />{items.length ? 'Refreshing inventory data…' : 'Loading inventory data…'}</div>}

      <section className="stat-strip" aria-label="Inventory summary">
        <article className="stat metric-card inventory-manager-metric inventory-manager-metric-items"><div className="inventory-manager-metric-main"><span className="inventory-manager-metric-icon" aria-hidden="true"><Icon name="inventory" size={20} /></span><div className="metric-info"><span className="inventory-manager-metric-kicker">CATALOGUE</span><strong className="inventory-manager-metric-value">{stats.items}</strong><span className="inventory-manager-metric-label">Items tracked</span></div><span className="inventory-manager-metric-symbol" aria-hidden="true">01</span></div><div className="inventory-manager-metric-detail">Organized across {stats.categories} {stats.categories === 1 ? 'category' : 'categories'}</div></article>
        <article className="stat metric-card inventory-manager-metric inventory-manager-metric-units"><div className="inventory-manager-metric-main"><span className="inventory-manager-metric-icon" aria-hidden="true"><Icon name="box" size={20} /></span><div className="metric-info"><span className="inventory-manager-metric-kicker">AVAILABLE STOCK</span><strong className="inventory-manager-metric-value">{stats.total.toLocaleString()}</strong><span className="inventory-manager-metric-label">Units on hand</span></div><span className="inventory-manager-metric-symbol" aria-hidden="true">02</span></div>        <div className="inventory-manager-metric-detail">Total quantity across all branch stocks</div></article>
        <article className="stat metric-card inventory-manager-metric inventory-manager-metric-attention"><div className="inventory-manager-metric-main"><span className="inventory-manager-metric-icon" aria-hidden="true"><Icon name="alert" size={20} /></span><div className="metric-info"><span className="inventory-manager-metric-kicker">STOCK HEALTH</span><strong className="inventory-manager-metric-value">{stats.low + stats.out}</strong><span className="inventory-manager-metric-label">Need attention</span></div><span className="inventory-manager-metric-symbol" aria-hidden="true">03</span></div>        <div className="inventory-manager-metric-detail">{stats.out} products out of stock · {stats.low} with low stock</div></article>
        <article className="stat metric-card inventory-manager-metric inventory-manager-metric-valuation"><div className="inventory-manager-metric-main"><span className="inventory-manager-metric-icon" aria-hidden="true"><Icon name="chart" size={20} /></span><div className="metric-info"><span className="inventory-manager-metric-kicker">VALUATION</span><strong className="inventory-manager-metric-value-number">LKR {stats.value.toLocaleString()}</strong><span className="inventory-manager-metric-label">Stock value</span></div><span className="inventory-manager-metric-symbol" aria-hidden="true">04</span></div><div className="inventory-manager-metric-detail">Calculated using recorded unit costs</div></article>
      </section>

      <div className="inventory-layout inventory-manager-layout">
        <section className="panel inventory-panel inventory-manager-table-panel">
          <div className="inventory-manager-panel-heading">
            <div className="inventory-manager-panel-icon" aria-hidden="true"><Icon name="inventory" size={19} /></div>
            <div><h2>Stock catalogue</h2><p>One row per product, with each branch's stock shown separately.</p></div>
            <span className="inventory-manager-total-pill">{stats.items} {stats.items === 1 ? 'product' : 'products'}</span>
          </div>
          <div className="toolbar">
            <div className="search-field">
              <span className="search-icon" aria-hidden="true">⌕</span>
              <input
                type="search"
                placeholder="Search items, SKUs, owners…"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                aria-label="Search stock"
              />
            </div>
            <select className="filter-select" value={category} onChange={(event) => setCategory(event.target.value)} aria-label="Filter by category">
              {categoryFilterOptions.map((option) => <option key={option}>{option}</option>)}
            </select>
            <select className="filter-select" value={status} onChange={(event) => setStatus(event.target.value as StatusFilter)} aria-label="Filter by status">
              {statusFilters.map((option) => <option key={option}>{option}</option>)}
            </select>
            {branches.length > 1 && (
              isAdmin ? <select
                className="filter-select"
                value={branchFilter}
                onChange={(event) => setBranchFilter(event.target.value)}
                aria-label="Filter by branch"
              >
                <option>All branches</option>
                {branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}
              </select> : <span className="filter-select" aria-label="Assigned branch">
                {branches.find((branch) => branch.id === assignedBranchId)?.name ?? (assignedBranchId ? 'Assigned branch' : 'No assigned branch')}
              </span>
            )}
            {hasActiveFilters && (
              <button
                type="button"
                className="btn btn-ghost inventory-clear-filters"
                onClick={() => { setQuery(''); setCategory(categories[0]); setStatus(statusFilters[0]); setBranchFilter('All branches'); }}
              >
                Clear filters
              </button>
            )}
          </div>
          <div className="inventory-quick-filters" role="group" aria-label="Quick stock status filters">
            <button
              type="button"
              className={`inventory-chip${status === 'All statuses' ? ' is-active' : ''}`}
              aria-pressed={status === 'All statuses'}
              onClick={() => setStatus('All statuses')}
            >
              All Products <strong>({stats.items})</strong>
            </button>
            <button
              type="button"
              className={`inventory-chip chip-green${status === 'In stock' ? ' is-active' : ''}`}
              aria-pressed={status === 'In stock'}
              onClick={() => setStatus('In stock')}
            >
              In Stock <strong>({Math.max(0, stats.items - stats.low - stats.out)})</strong>
            </button>
            <button
              type="button"
              className={`inventory-chip chip-amber${status === 'Low stock' ? ' is-active' : ''}`}
              aria-pressed={status === 'Low stock'}
              onClick={() => setStatus('Low stock')}
            >
              Low Stock <strong>({stats.low})</strong>
            </button>
            <button
              type="button"
              className={`inventory-chip chip-red${status === 'Out of stock' ? ' is-active' : ''}`}
              aria-pressed={status === 'Out of stock'}
              onClick={() => setStatus('Out of stock')}
            >
              Out of Stock <strong>({stats.out})</strong>
            </button>
          </div>

          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr><th>Item</th><th>Category</th><th>Branch stock</th><th>Total on hand</th><th>Unit cost</th><th>Selling price</th><th>Actions</th></tr>
              </thead>
              <tbody>
                {paged.map(({ key, rows, primary, totalQuantity }) => {
                  return (
                    <tr key={key}>
                      <td>
                        <p className="cell-title">{primary.item}</p>
                        <div className="inventory-manager-item-meta">
                          <code className="inventory-manager-item-sku">{primary.sku}</code>
                          <span className="inventory-manager-item-branch-count">
                            <span aria-hidden="true">⌖</span>
                            {rows.length} {rows.length === 1 ? 'branch' : 'branches'}
                          </span>
                        </div>
                      </td>
                      <td><span className="category-pill">{primary.category}</span></td>
                      <td>
                        <div className="inventory-product-branch-list">
                          {rows.map((branchRow) => {
                            const branchStatus = deriveStatus(branchRow.qty, branchRow.reorder);
                            return (
                              <div className="inventory-product-branch" key={branchRow.id ?? branchRow.branchId}>
                                <span className="inventory-product-branch-name">{branchRow.owner}</span>
                                <span className="inventory-product-branch-quantity">{branchRow.qty} {branchRow.unit}</span>
                                <Badge tone={statusTone[branchStatus]}>{branchStatus}</Badge>
                                {canManageCatalog && <button
                                  type="button"
                                  className="row-action row-action-danger inventory-product-branch-delete"
                                  aria-label={`Remove ${branchRow.item} from ${branchRow.owner}`}
                                  title={`Remove from ${branchRow.owner}`}
                                  onClick={() => branchRow.id && setDeleteItemId(branchRow.id)}
                                >🗑</button>}
                              </div>
                            );
                          })}
                        </div>
                      </td>
                      <td><span className="qty">{totalQuantity}</span> <span className="cell-sub inventory-manager-unit-label">{primary.unit}</span></td>
                      <td className="amount">{primary.costPrice == null ? 'Not set' : formatPrice(primary.costPrice)}</td>
                      <td className="amount">{primary.sellingPrice == null ? 'Not set' : formatPrice(primary.sellingPrice)}</td>
                      <td>
                        <div className="row-actions">
                          <button type="button" className="row-action" aria-label={`Show QR for ${primary.item}`} title="Show item QR" onClick={() => setQrItem(primary)}><QRCodeSVG value={primary.sku} size={18} level="M" bgColor="#fff" fgColor="#111" /></button>
                          {canManageCatalog && <button type="button" className="row-action" aria-label={`Edit ${primary.item} across branches`} onClick={() => primary.id && setModal({ mode: 'edit', id: primary.id })}>✎</button>}
                        </div>
                      </td>
                    </tr>
                  );
                })}
                {paged.length === 0 && (
                  <tr><td colSpan={7} className="empty-state"><div className="inventory-manager-empty"><strong>{items.length === 0 ? 'Your catalogue is ready for its first item' : 'No items match these filters'}</strong><span>{items.length === 0 ? 'Add an item to start tracking quantity, reorder levels, and stock value.' : 'Try another search or clear the active filters.'}</span>{items.length === 0 && canManageCatalog ? <button type="button" className="btn btn-primary" onClick={() => setModal({ mode: 'add' })}>Add first item</button> : hasActiveFilters ? <button type="button" className="btn btn-secondary" onClick={() => { setQuery(''); setCategory(categories[0]); setStatus(statusFilters[0]); setBranchFilter(isAdmin ? 'All branches' : assignedBranchId ?? ''); }}>Clear filters</button> : null}</div></td></tr>
                )}
              </tbody>
            </table>
          </div>

          <div className="table-footer">
            <p className="table-caption">
              {groupedFiltered.length === 0
                ? `No items · ${items.length} total in inventory`
                : `Showing ${rangeStart}–${rangeEnd} of ${groupedFiltered.length} products · ${items.length} branch stocks in inventory`}
            </p>
            {groupedFiltered.length > PAGE_SIZE && (
              <nav className="pagination" aria-label="Inventory pagination">
                <button
                  type="button"
                  className="pagination-btn"
                  disabled={safePage <= 1}
                  onClick={() => setPage((p) => p - 1)}
                >
                  Previous
                </button>
                {Array.from({ length: totalPages }, (_, index) => index + 1).map((pageNum) => (
                  <button
                    key={pageNum}
                    type="button"
                    className={`pagination-btn${pageNum === safePage ? ' pagination-btn-active' : ''}`}
                    aria-current={pageNum === safePage ? 'page' : undefined}
                    onClick={() => setPage(pageNum)}
                  >
                    {pageNum}
                  </button>
                ))}
                <button
                  type="button"
                  className="pagination-btn"
                  disabled={safePage >= totalPages}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Next
                </button>
              </nav>
            )}
          </div>
        </section>

      </div>

      {modal && (
        <ItemModal
          title={modal.mode === 'add' ? 'Add inventory item' : 'Edit inventory item'}
          isEditing={modal.mode === 'edit'}
          initial={modal.mode === 'edit' && editingItem
            ? {
                item: editingItem.item,
                category: editingItem.category,
                categoryId: editingItem.categoryId,
                unit: editingItem.unit,
                costPrice: editingItem.costPrice,
                sellingPrice: editingItem.sellingPrice,
                qty: editingItem.qty,
                reorder: editingItem.reorder,
                owner: editingItem.owner,
                supplierId: editingItem.supplierId,
                branchId: editingItem.branchId,
                branchStocks: items.flatMap((row) =>
                  row.sku === editingItem.sku && row.branchId
                    ? [{ branchId: row.branchId, quantity: row.qty }]
                    : [],
                ),
              }
            : { ...emptyForm, category: inventoryCategories[0]?.name ?? categoryOptions[0], categoryId: inventoryCategories[0]?.id }}
          onClose={() => setModal(null)}
          onSave={handleSave}
          saving={saving}
          suppliers={suppliers}
          categories={inventoryCategories}
          branches={isAdmin ? branches : branches.filter((branch) => branch.id === assignedBranchId)}
          defaultBranchId={assignedBranchId ?? branches[0]?.id}
        />
      )}

      {qrItem && (
        <div className="modal-overlay" onClick={() => setQrItem(null)} role="presentation">
          <div className="modal modal-sm" onClick={(event) => event.stopPropagation()} role="dialog" aria-modal="true" aria-labelledby="inventory-qr-title">
            <div className="modal-head">
              <h2 id="inventory-qr-title">Item QR label</h2>
              <button type="button" className="modal-close" onClick={() => setQrItem(null)} aria-label="Close">×</button>
            </div>
            <div className="modal-body" style={{ textAlign: 'center' }}>
              <p className="cell-title">{qrItem.item}</p>
              <div style={{ display: 'inline-block', padding: 16, background: '#fff', borderRadius: 12 }}>
                <QRCodeSVG value={qrItem.sku} size={240} level="M" title={`QR code for SKU ${qrItem.sku}`} />
              </div>
              <p className="cell-title" style={{ marginTop: 12 }}><code>{qrItem.sku}</code></p>
              <p className="modal-hint">This QR encodes only the item SKU. Scan it from Physical Counts &amp; Activity or the mobile Physical Stock Count screen.</p>
              <div className="modal-actions">
                <button type="button" className="btn btn-secondary" onClick={() => setQrItem(null)}>Close</button>
                <button
                  type="button"
                  className="btn btn-primary"
                  onClick={() => {
                    if (!navigator.clipboard) {
                      notify('Clipboard access is not available in this browser.', 'warning');
                      return;
                    }
                    void navigator.clipboard.writeText(qrItem.sku)
                      .then(() => notify('SKU copied.', 'success'))
                      .catch(() => notify('Could not copy the SKU in this browser.', 'warning'));
                  }}
                >Copy SKU</button>
              </div>
            </div>
          </div>
        </div>
      )}

      {deleteItemId && (
        <div className="modal-overlay" onClick={() => setDeleteItemId(null)} role="presentation">
          <div className="modal modal-sm" onClick={(event) => event.stopPropagation()} role="alertdialog" aria-modal="true" aria-labelledby="delete-title">
            <div className="modal-head">
              <h2 id="delete-title">Delete item?</h2>
              <button type="button" className="modal-close" onClick={() => setDeleteItemId(null)} aria-label="Close">×</button>
            </div>
            <div className="modal-body">
              <p className="delete-copy">
                Remove <strong>{items.find((row) => row.id === deleteItemId)?.item}</strong> ({items.find((row) => row.id === deleteItemId)?.sku}) from this branch’s inventory? This cannot be undone.
              </p>
              <div className="modal-actions">
                <button type="button" className="btn btn-secondary" onClick={() => setDeleteItemId(null)}>Cancel</button>
                <button type="button" className="btn btn-danger" onClick={confirmDelete}>Delete</button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
