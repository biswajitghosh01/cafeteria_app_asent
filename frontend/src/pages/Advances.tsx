import { Coins, Plus, Trash2 } from 'lucide-react';
import { FormEvent, useEffect, useState } from 'react';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import { Input, Select } from '../components/ui/Input';
import StatTile from '../components/ui/StatTile';
import Table, { type Column } from '../components/ui/Table';
import { api, apiErrorMessage } from '../lib/api';
import { formatDate, formatINR, todayISO } from '../lib/format';

interface Employee {
  id: number;
  full_name: string;
  emp_code: string;
  basic_salary: string;
  hra: string;
  allowances: string;
}

interface Advance {
  id: number;
  employee_id: number;
  employee_name: string | null;
  amount: string;
  advance_date: string;
  reason: string | null;
  notes: string | null;
  created_by: string | null;
  created_at: string;
}

interface AdvanceBalance {
  employee_id: number;
  employee_name: string;
  total_advances: string;
  total_recovered: string;
  outstanding: string;
}

const emptyForm = {
  employee_id: '',
  amount: '',
  advance_date: todayISO(),
  reason: '',
  notes: '',
};

export default function Advances() {
  const [advances, setAdvances] = useState<Advance[]>([]);
  const [balances, setBalances] = useState<AdvanceBalance[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const load = async () => {
    setError(null);
    try {
      const [advRes, balRes, empRes] = await Promise.all([
        api.get<Advance[]>('/advances'),
        api.get<AdvanceBalance[]>('/advances/balances'),
        api.get<Employee[]>('/employees'),
      ]);
      setAdvances(advRes.data);
      setBalances(balRes.data);
      setEmployees(empRes.data);
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  useEffect(() => {
    load();
  }, []);

  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) =>
    setForm((f) => ({ ...f, [k]: v }));

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);

    const amount = Number(form.amount);
    if (!form.employee_id) {
      setError('Select an employee.');
      return;
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      setError('Advance amount must be greater than zero.');
      return;
    }

    setSubmitting(true);
    try {
      await api.post('/advances', {
        employee_id: Number(form.employee_id),
        amount,
        advance_date: form.advance_date,
        reason: form.reason || null,
        notes: form.notes || null,
      });
      setForm({ ...emptyForm });
      setShowForm(false);
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  const remove = async (row: Advance) => {
    const recovered = balanceFor(row.employee_id)?.total_recovered ?? '0';
    const message =
      Number(recovered) > 0
        ? `${row.employee_name ?? 'This employee'} already has ${formatINR(recovered)} recovered against advances. Deleting this advance will change the outstanding balance. Continue?`
        : `Delete the advance of ${formatINR(row.amount)} to ${row.employee_name ?? 'this employee'}?`;
    if (!confirm(message)) return;

    setError(null);
    try {
      await api.delete(`/advances/${row.id}`);
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  const balanceFor = (employeeId: number): AdvanceBalance | undefined =>
    balances.find((b) => b.employee_id === employeeId);

  const totals = balances.reduce(
    (acc, b) => ({
      given: acc.given + Number(b.total_advances),
      recovered: acc.recovered + Number(b.total_recovered),
      outstanding: acc.outstanding + Number(b.outstanding),
    }),
    { given: 0, recovered: 0, outstanding: 0 },
  );

  const advanceColumns: Column<Advance>[] = [
    {
      key: 'employee',
      header: 'Employee',
      render: (r) => (
        <div>
          <strong>{r.employee_name ?? '—'}</strong>
          <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
            {employees.find((e) => e.id === r.employee_id)?.emp_code ?? ''}
          </div>
        </div>
      ),
    },
    { key: 'date', header: 'Advance Date', render: (r) => formatDate(r.advance_date) },
    {
      key: 'amount',
      header: 'Amount',
      align: 'right',
      render: (r) => <span className="mono">{formatINR(r.amount)}</span>,
    },
    { key: 'reason', header: 'Reason', render: (r) => r.reason || '—' },
    {
      key: 'status',
      header: 'Recovery Status',
      render: (r) => {
        const bal = balanceFor(r.employee_id);
        if (!bal) return <Badge tone="warning">Outstanding</Badge>;
        const outstanding = Number(bal.outstanding);
        if (outstanding <= 0) return <Badge tone="success">Recovered</Badge>;
        if (Number(bal.total_recovered) > 0)
          return <Badge tone="info">Partially recovered</Badge>;
        return <Badge tone="warning">Outstanding</Badge>;
      },
    },
    {
      key: 'actions',
      header: '',
      align: 'right',
      render: (r) => (
        <button
          className="icon-btn"
          onClick={() => remove(r)}
          title="Delete advance"
          aria-label="Delete advance"
        >
          <Trash2 size={16} />
        </button>
      ),
    },
  ];

  const balanceColumns: Column<AdvanceBalance>[] = [
    {
      key: 'employee',
      header: 'Employee',
      render: (r) => (
        <div>
          <strong>{r.employee_name}</strong>
          <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
            {employees.find((e) => e.id === r.employee_id)?.emp_code ?? ''}
          </div>
        </div>
      ),
    },
    {
      key: 'given',
      header: 'Total Advanced',
      align: 'right',
      render: (r) => <span className="mono">{formatINR(r.total_advances)}</span>,
    },
    {
      key: 'recovered',
      header: 'Recovered',
      align: 'right',
      render: (r) => (
        <span className="mono" style={{ color: '#059669' }}>
          {formatINR(r.total_recovered)}
        </span>
      ),
    },
    {
      key: 'outstanding',
      header: 'Outstanding',
      align: 'right',
      render: (r) => {
        const v = Number(r.outstanding);
        return (
          <span className="mono" style={{ fontWeight: 700, color: v > 0 ? '#dc2626' : '#059669' }}>
            {formatINR(r.outstanding)}
          </span>
        );
      },
    },
    {
      key: 'status',
      header: 'Status',
      render: (r) =>
        Number(r.outstanding) <= 0 ? (
          <Badge tone="success">Closed</Badge>
        ) : Number(r.total_recovered) > 0 ? (
          <Badge tone="info">In recovery</Badge>
        ) : (
          <Badge tone="warning">Outstanding</Badge>
        ),
    },
  ];

  const employeesWithAdvance = new Set(advances.map((a) => a.employee_id));

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Salary Advances</h1>
          <p className="page-subtitle">
            Advances and loans given to employees, with recovery tracked against
            payslips
          </p>
        </div>
        <div className="page-actions">
          <Button
            variant={showForm ? 'secondary' : 'primary'}
            icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}
          >
            {showForm ? 'Cancel' : 'Give Advance'}
          </Button>
        </div>
      </div>

      {error && (
        <div className="login-error" style={{ marginBottom: 16 }}>
          {error}
        </div>
      )}

      <div className="grid-stats">
        <StatTile
          label="Total Advanced"
          value={formatINR(totals.given)}
          icon={<Coins size={18} />}
        />
        <StatTile
          label="Total Recovered"
          value={formatINR(totals.recovered)}
          tone="success"
        />
        <StatTile
          label="Outstanding"
          value={formatINR(totals.outstanding)}
          tone={totals.outstanding > 0 ? 'danger' : 'success'}
        />
        <StatTile
          label="Employees with Advances"
          value={String(employeesWithAdvance.size)}
          hint={`${balances.filter((b) => Number(b.outstanding) > 0).length} still outstanding`}
        />
      </div>

      {showForm && (
        <Card title="Record a Salary Advance">
          <form onSubmit={onSubmit}>
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(3, 1fr)',
                gap: 14,
              }}
            >
              <Select
                label="Employee"
                value={form.employee_id}
                onChange={(e) => set('employee_id', e.target.value)}
                required
              >
                <option value="">Select employee…</option>
                {employees.map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.full_name} ({e.emp_code})
                  </option>
                ))}
              </Select>
              <Input
                label="Amount (₹)"
                type="number"
                step="0.01"
                min="0.01"
                value={form.amount}
                onChange={(e) => set('amount', e.target.value)}
                required
              />
              <Input
                label="Advance Date"
                type="date"
                value={form.advance_date}
                onChange={(e) => set('advance_date', e.target.value)}
                required
              />
              <Input
                label="Reason"
                value={form.reason}
                onChange={(e) => set('reason', e.target.value)}
                placeholder="e.g. Medical emergency"
              />
              <Input
                label="Notes"
                value={form.notes}
                onChange={(e) => set('notes', e.target.value)}
              />
            </div>
            <div
              style={{
                marginTop: 18,
                display: 'flex',
                gap: 10,
                justifyContent: 'flex-end',
              }}
            >
              <Button
                variant="secondary"
                type="button"
                onClick={() => setShowForm(false)}
              >
                Cancel
              </Button>
              <Button type="submit" loading={submitting}>
                Save Advance
              </Button>
            </div>
          </form>
        </Card>
      )}

      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card
          title="Advance Ledger"
          subtitle={`${advances.length} record${advances.length === 1 ? '' : 's'}`}
          padded={false}
        >
          <Table
            columns={advanceColumns}
            rows={advances}
            empty="No salary advances recorded yet."
          />
        </Card>
      </div>

      <div style={{ marginTop: 20 }}>
        <Card
          title="Recovery Position by Employee"
          subtitle="Advanced − Recovered = Outstanding"
          padded={false}
        >
          <Table
            columns={balanceColumns}
            rows={balances}
            empty="No employees to show."
          />
        </Card>
      </div>

      <div style={{ marginTop: 20 }}>
        <Card title="How salary advance recovery works" padded>
          <div
            style={{
              fontSize: 13,
              color: 'var(--text-muted)',
              lineHeight: 1.8,
            }}
          >
            <p style={{ margin: '0 0 8px' }}>
              <strong style={{ color: 'var(--text-strong)' }}>
                Outstanding
              </strong>{' '}
              = Total Advanced − Total Recovered
            </p>
            <p style={{ margin: '0 0 8px' }}>
              <strong style={{ color: 'var(--text-strong)' }}>
                Recovered
              </strong>{' '}
              is the sum of the{' '}
              <span className="mono">advance_deduction</span> recorded on each
              payslip. It is updated when salary is processed — not on this page.
            </p>
            <p style={{ margin: '0 0 8px' }}>
              When you create a salary record, the deduction cannot exceed the
              outstanding balance at that time. The payslip then stores the
              balance before and after recovery.
            </p>
            <p style={{ margin: 0 }}>
              Deleting an advance changes the outstanding balance but does not
              undo deductions already recovered through past payslips.
            </p>
          </div>
        </Card>
      </div>
    </>
  );
}