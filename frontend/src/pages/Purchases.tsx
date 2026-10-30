import { FormEvent, useEffect, useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import { Input } from '../components/ui/Input';
import Table, { type Column } from '../components/ui/Table';
import { api, apiErrorMessage } from '../lib/api';
import { formatDate, formatINR, todayISO } from '../lib/format';

interface Purchase {
  id: number; bill_no: string; purchase_date: string; vendor: string;
  amount: string; gst: string; total: string; notes: string | null;
}
const emptyForm = { bill_no: '', purchase_date: todayISO(), vendor: '', amount: '', gst: '', notes: '' };

export default function Purchases() {
  const [rows, setRows] = useState<Purchase[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const load = async () => {
    try { const { data } = await api.get<Purchase[]>('/purchases'); setRows(data); }
    catch (err) { setError(apiErrorMessage(err)); }
  };
  useEffect(() => { load(); }, []);
  const set = (k: keyof typeof form, v: string) => setForm((f) => ({ ...f, [k]: v }));
  const onSubmit = async (e: FormEvent) => {
    e.preventDefault(); setError(null); setSubmitting(true);
    const amount = Number(form.amount || 0);
    const gst = Number(form.gst || 0);
    try {
      await api.post('/purchases', {
        bill_no: form.bill_no, purchase_date: form.purchase_date, vendor: form.vendor,
        amount, gst, total: amount + gst, notes: form.notes || null,
      });
      setForm({ ...emptyForm }); setShowForm(false); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setSubmitting(false); }
  };
  const remove = async (id: number) => {
    if (!confirm('Delete this purchase?')) return;
    await api.delete(`/purchases/${id}`); await load();
  };
  const columns: Column<Purchase>[] = [
    { key: 'date', header: 'Date', render: (r) => formatDate(r.purchase_date) },
    { key: 'bill', header: 'Bill', render: (r) => <span className="mono">{r.bill_no}</span> },
    { key: 'vendor', header: 'Vendor', render: (r) => r.vendor },
    { key: 'amount', header: 'Amount', align: 'right', render: (r) => <span className="mono">{formatINR(r.amount)}</span> },
    { key: 'gst', header: 'GST', align: 'right', render: (r) => <span className="mono">{formatINR(r.gst)}</span> },
    { key: 'total', header: 'Total', align: 'right', render: (r) => <strong className="mono">{formatINR(r.total)}</strong> },
    { key: 'actions', header: '', align: 'right',
      render: (r) => <button className="icon-btn" onClick={() => remove(r.id)}><Trash2 size={15} /></button> },
  ];
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Purchases</h1>
          <p className="page-subtitle">Vendor bills and inward GST</p>
        </div>
        <div className="page-actions">
          <Button variant={showForm ? 'secondary' : 'primary'} icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}>
            {showForm ? 'Cancel' : 'New Purchase'}
          </Button>
        </div>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {showForm && (
        <Card title="New Purchase">
          <form onSubmit={onSubmit}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
              <Input label="Bill No." value={form.bill_no} onChange={(e) => set('bill_no', e.target.value)} required />
              <Input label="Purchase Date" type="date" value={form.purchase_date} onChange={(e) => set('purchase_date', e.target.value)} required />
              <Input label="Vendor" value={form.vendor} onChange={(e) => set('vendor', e.target.value)} required />
              <Input label="Amount (excl. GST)" type="number" step="0.01" value={form.amount} onChange={(e) => set('amount', e.target.value)} required />
              <Input label="GST" type="number" step="0.01" value={form.gst} onChange={(e) => set('gst', e.target.value)} />
              <Input label="Notes" value={form.notes} onChange={(e) => set('notes', e.target.value)} />
            </div>
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setShowForm(false)}>Cancel</Button>
              <Button type="submit" loading={submitting}>Save Purchase</Button>
            </div>
          </form>
        </Card>
      )}
      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card title="Purchase Records" padded={false}>
          <Table columns={columns} rows={rows} empty="No purchases yet." />
        </Card>
      </div>
    </>
  );
}
