import { FormEvent, useEffect, useState } from 'react';
import { CheckCircle2, Plus } from 'lucide-react';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import { Input, Select } from '../components/ui/Input';
import Table, { type Column } from '../components/ui/Table';
import { api, apiErrorMessage } from '../lib/api';
import { formatDate, formatINR, todayISO } from '../lib/format';

type Category = 'rent' | 'electricity' | 'maintenance' | 'other';
interface Expense {
  id: number; category: Category; description: string; amount: string;
  expense_date: string; due_date: string | null; is_paid: boolean; notes: string | null;
}
const LABEL: Record<Category, string> = {
  rent: 'Rent', electricity: 'Electricity', maintenance: 'Maintenance', other: 'Other',
};
const emptyForm = {
  category: 'rent' as Category, description: '', amount: '',
  expense_date: todayISO(), due_date: '', notes: '',
};

export default function Expenses() {
  const [rows, setRows] = useState<Expense[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const load = async () => {
    try { const { data } = await api.get<Expense[]>('/expenses'); setRows(data); }
    catch (err) { setError(apiErrorMessage(err)); }
  };
  useEffect(() => { load(); }, []);
  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) =>
    setForm((f) => ({ ...f, [k]: v }));
  const onSubmit = async (e: FormEvent) => {
    e.preventDefault(); setError(null); setSubmitting(true);
    try {
      await api.post('/expenses', {
        category: form.category, description: form.description,
        amount: Number(form.amount || 0), expense_date: form.expense_date,
        due_date: form.due_date || null, is_paid: false, notes: form.notes || null,
      });
      setForm({ ...emptyForm }); setShowForm(false); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setSubmitting(false); }
  };
  const markPaid = async (id: number) => { await api.patch(`/expenses/${id}/paid`); await load(); };
  const columns: Column<Expense>[] = [
    { key: 'category', header: 'Category', render: (r) => LABEL[r.category] },
    { key: 'description', header: 'Description', render: (r) => r.description },
    { key: 'date', header: 'Date', render: (r) => formatDate(r.expense_date) },
    { key: 'due', header: 'Due', render: (r) => (r.due_date ? formatDate(r.due_date) : '—') },
    { key: 'amount', header: 'Amount', align: 'right', render: (r) => <span className="mono">{formatINR(r.amount)}</span> },
    { key: 'status', header: 'Status',
      render: (r) => (r.is_paid ? <Badge tone="success">Paid</Badge> : <Badge tone="warning">Pending</Badge>) },
    { key: 'actions', header: '', align: 'right',
      render: (r) => r.is_paid ? null :
        <button className="icon-btn" onClick={() => markPaid(r.id)} title="Mark paid"><CheckCircle2 size={16} /></button> },
  ];
  const total = rows.reduce((s, r) => s + Number(r.amount), 0);
  const unpaid = rows.filter((r) => !r.is_paid).reduce((s, r) => s + Number(r.amount), 0);
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Fixed Expenses</h1>
          <p className="page-subtitle">Total: {formatINR(total)} · Outstanding: {formatINR(unpaid)}</p>
        </div>
        <div className="page-actions">
          <Button variant={showForm ? 'secondary' : 'primary'} icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}>
            {showForm ? 'Cancel' : 'Add Expense'}
          </Button>
        </div>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {showForm && (
        <Card title="New Fixed Expense">
          <form onSubmit={onSubmit}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
              <Select label="Category" value={form.category}
                onChange={(e) => set('category', e.target.value as Category)}>
                <option value="rent">Rent</option>
                <option value="electricity">Electricity</option>
                <option value="maintenance">Maintenance</option>
                <option value="other">Other</option>
              </Select>
              <Input label="Description" value={form.description} onChange={(e) => set('description', e.target.value)} required />
              <Input label="Amount" type="number" step="0.01" value={form.amount} onChange={(e) => set('amount', e.target.value)} required />
              <Input label="Expense Date" type="date" value={form.expense_date} onChange={(e) => set('expense_date', e.target.value)} required />
              <Input label="Due Date (optional)" type="date" value={form.due_date} onChange={(e) => set('due_date', e.target.value)} />
              <Input label="Notes" value={form.notes} onChange={(e) => set('notes', e.target.value)} />
            </div>
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setShowForm(false)}>Cancel</Button>
              <Button type="submit" loading={submitting}>Save Expense</Button>
            </div>
          </form>
        </Card>
      )}
      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card title="Expense Records" padded={false}>
          <Table columns={columns} rows={rows} empty="No expenses recorded." />
        </Card>
      </div>
    </>
  );
}
