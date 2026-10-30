import { CheckCircle2, Plus, Trash2 } from "lucide-react";
import { FormEvent, useEffect, useState } from "react";
import Badge from "../components/ui/Badge";
import Button from "../components/ui/Button";
import Card from "../components/ui/Card";
import { Input, Select } from "../components/ui/Input";
import Table, { type Column } from "../components/ui/Table";
import { api, apiErrorMessage } from "../lib/api";
import { formatINR } from "../lib/format";

interface Employee {
  id: number;
  full_name: string;
  emp_code: string;
  basic_salary: string;
}

interface Salary {
  id: number;
  employee_id: number;
  employee_name: string | null;
  pay_period: string;
  gross: string;
  pf_employee: string;
  pf_employer: string;
  esi_employee: string;
  esi_employer: string;
  income_tax: string;
  other_deductions: string;
  advance_deduction: string;
  net_pay: string;
  paid: boolean;
}

interface Balance {
  employee_id: number;
  outstanding: string;
}

const emptyForm = {
  employee_id: "",
  pay_period: new Date().toISOString().slice(0, 7),
  gross: "",
  income_tax: "",
  other_deductions: "",
  advance_deduction: "",
  notes: "",
};

export default function Salary() {
  const [rows, setRows] = useState<Salary[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [balances, setBalances] = useState<Record<number, number>>({});
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [preview, setPreview] = useState<{
    pf_employee: string;
    pf_employer: string;
    esi_employee: string;
    esi_employer: string;
  } | null>(null);

  const load = async () => {
    try {
      const [s, e, b] = await Promise.all([
        api.get<Salary[]>("/salary"),
        api.get<Employee[]>("/employees"),
        api.get<Balance[]>("/advances/balances"),
      ]);
      setRows(s.data);
      setEmployees(e.data);

      const map: Record<number, number> = {};
      for (const item of b.data) {
        map[item.employee_id] = Number(item.outstanding);
      }
      setBalances(map);
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  useEffect(() => {
    load();
  }, []);

  const set = (k: keyof typeof form, v: string) =>
    setForm((f) => ({ ...f, [k]: v }));

  const onGrossChange = async (v: string) => {
    set("gross", v);
    const g = Number(v);
    if (g > 0) {
      try {
        const { data } = await api.get("/salary/preview", {
          params: { gross: g },
        });
        setPreview(data);
      } catch {
        setPreview(null);
      }
    } else {
      setPreview(null);
    }
  };

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);

    const empId = Number(form.employee_id);
    const outstanding = balances[empId] ?? 0;
    const advanceDeduction = Number(form.advance_deduction || 0);

    if (advanceDeduction > outstanding) {
      setError(
        `Advance deduction (${advanceDeduction}) exceeds outstanding (${outstanding})`,
      );
      return;
    }

    setSubmitting(true);

    const gross = Number(form.gross || 0);
    const pfEmp = Number(preview?.pf_employee ?? 0);
    const pfEr = Number(preview?.pf_employer ?? 0);
    const esiEmp = Number(preview?.esi_employee ?? 0);
    const esiEr = Number(preview?.esi_employer ?? 0);
    const it = Number(form.income_tax || 0);
    const other = Number(form.other_deductions || 0);
    const net = gross - pfEmp - esiEmp - it - other - advanceDeduction;

    try {
      await api.post("/salary", {
        employee_id: empId,
        pay_period: form.pay_period,
        days_in_month: 0,
        days_present: 0,
        days_absent: 0,
        days_on_leave: 0,
        payable_days: 0,
        daily_rate: 0,
        base_gross: gross,
        gross,
        pf_employee: pfEmp,
        pf_employer: pfEr,
        esi_employee: esiEmp,
        esi_employer: esiEr,
        income_tax: it,
        other_deductions: other,
        advance_deduction: advanceDeduction,
        advance_balance_before: 0,
        advance_balance_after: 0,
        net_pay: net,
        paid: false,
        notes: form.notes || null,
      });
      setForm({ ...emptyForm });
      setPreview(null);
      setShowForm(false);
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  const markPaid = async (id: number) => {
    try {
      await api.patch(`/salary/${id}/paid`);
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  const remove = async (row: Salary) => {
    const label = `${row.employee_name ?? `#${row.employee_id}`} — ${row.pay_period}`;
    if (!confirm(`Delete salary record for ${label}? This cannot be undone.`))
      return;
    try {
      await api.delete(`/salary/${row.id}`);
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  const columns: Column<Salary>[] = [
    {
      key: "period",
      header: "Period",
      render: (r) => <span className="mono">{r.pay_period}</span>,
    },
    {
      key: "emp",
      header: "Employee",
      render: (r) => r.employee_name ?? `#${r.employee_id}`,
    },
    {
      key: "gross",
      header: "Gross",
      align: "right",
      render: (r) => <span className="mono">{formatINR(r.gross)}</span>,
    },
    {
      key: "pf",
      header: "PF (Emp)",
      align: "right",
      render: (r) => <span className="mono">{formatINR(r.pf_employee)}</span>,
    },
    {
      key: "esi",
      header: "ESI (Emp)",
      align: "right",
      render: (r) => <span className="mono">{formatINR(r.esi_employee)}</span>,
    },
    {
      key: "it",
      header: "Income Tax",
      align: "right",
      render: (r) => <span className="mono">{formatINR(r.income_tax)}</span>,
    },
    {
      key: "other",
      header: "Other",
      align: "right",
      render: (r) => (
        <span className="mono">{formatINR(r.other_deductions)}</span>
      ),
    },
    {
      key: "advance",
      header: "Advance",
      align: "right",
      render: (r) => (
        <span
          className="mono"
          style={{
            color:
              Number(r.advance_deduction) > 0
                ? "var(--color-danger)"
                : undefined,
          }}
        >
          {Number(r.advance_deduction) > 0
            ? formatINR(r.advance_deduction)
            : "—"}
        </span>
      ),
    },
    {
      key: "net",
      header: "Net Pay",
      align: "right",
      render: (r) => (
        <strong className="mono" style={{ color: "var(--color-success)" }}>
          {formatINR(r.net_pay)}
        </strong>
      ),
    },
    {
      key: "status",
      header: "Status",
      render: (r) =>
        r.paid ? (
          <Badge tone="success">Paid</Badge>
        ) : (
          <Badge tone="warning">Pending</Badge>
        ),
    },
    {
      key: "actions",
      header: "",
      align: "right",
      render: (r) => (
        <div
          style={{
            display: "flex",
            gap: 4,
            justifyContent: "flex-end",
          }}
        >
          {!r.paid && (
            <button
              className="icon-btn"
              title="Mark as paid"
              onClick={() => markPaid(r.id)}
            >
              <CheckCircle2 size={16} />
            </button>
          )}
          <button
            className="icon-btn"
            title="Delete salary record"
            onClick={() => remove(r)}
          >
            <Trash2 size={15} />
          </button>
        </div>
      ),
    },
  ];

  const selectedOutstanding = form.employee_id
    ? (balances[Number(form.employee_id)] ?? 0)
    : 0;
  const advanceDeduction = Number(form.advance_deduction || 0);

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Salary &amp; Statutory</h1>
          <p className="page-subtitle">
            Manual entry — for attendance-based computation, use Payslips
          </p>
        </div>
        <div className="page-actions">
          <Button
            variant={showForm ? "secondary" : "primary"}
            icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}
          >
            {showForm ? "Cancel" : "New Salary"}
          </Button>
        </div>
      </div>

      {error && (
        <div className="login-error" style={{ marginBottom: 16 }}>
          {error}
        </div>
      )}

      {showForm && (
        <Card title="New Salary Record">
          <form onSubmit={onSubmit}>
            <div className="form-grid-3">
              <Select
                label="Employee"
                value={form.employee_id}
                onChange={(e) => set("employee_id", e.target.value)}
                required
              >
                <option value="">Select employee…</option>
                {employees.map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.emp_code} · {emp.full_name}
                  </option>
                ))}
              </Select>
              <Input
                label="Pay Period (YYYY-MM)"
                value={form.pay_period}
                onChange={(e) => set("pay_period", e.target.value)}
                required
              />
              <Input
                label="Gross"
                type="number"
                step="0.01"
                value={form.gross}
                onChange={(e) => onGrossChange(e.target.value)}
                required
              />
              <Input
                label="Income Tax"
                type="number"
                step="0.01"
                value={form.income_tax}
                onChange={(e) => set("income_tax", e.target.value)}
              />
              <Input
                label="Other Deductions"
                type="number"
                step="0.01"
                value={form.other_deductions}
                onChange={(e) => set("other_deductions", e.target.value)}
              />
              <Input
                label="Advance Recovery"
                type="number"
                step="0.01"
                value={form.advance_deduction}
                onChange={(e) => set("advance_deduction", e.target.value)}
                hint={
                  selectedOutstanding > 0
                    ? `Outstanding: ${formatINR(selectedOutstanding)}`
                    : "No outstanding advance"
                }
                disabled={selectedOutstanding <= 0}
              />
              <Input
                label="Notes"
                value={form.notes}
                onChange={(e) => set("notes", e.target.value)}
              />
            </div>

            {preview && (
              <div className="preview-tile">
                <span className="preview-label">Auto-computed statutory</span>
                <div className="preview-grid">
                  <div>
                    <span className="field-label">PF (Emp)</span>
                    <span className="mono">
                      {formatINR(preview.pf_employee)}
                    </span>
                  </div>
                  <div>
                    <span className="field-label">PF (Er)</span>
                    <span className="mono">
                      {formatINR(preview.pf_employer)}
                    </span>
                  </div>
                  <div>
                    <span className="field-label">ESI (Emp)</span>
                    <span className="mono">
                      {formatINR(preview.esi_employee)}
                    </span>
                  </div>
                  <div>
                    <span className="field-label">ESI (Er)</span>
                    <span className="mono">
                      {formatINR(preview.esi_employer)}
                    </span>
                  </div>
                </div>
              </div>
            )}

            {selectedOutstanding > 0 && (
              <div
                className="preview-tile"
                style={{
                  marginTop: 12,
                  background: "var(--color-warning-soft)",
                }}
              >
                <span className="preview-label">Advance summary</span>
                <div className="preview-grid">
                  <div>
                    <span className="field-label">Outstanding Before</span>
                    <span
                      className="mono"
                      style={{ color: "var(--color-danger)" }}
                    >
                      {formatINR(selectedOutstanding)}
                    </span>
                  </div>
                  <div>
                    <span className="field-label">Recovered This Month</span>
                    <span className="mono">{formatINR(advanceDeduction)}</span>
                  </div>
                  <div>
                    <span className="field-label">Balance After</span>
                    <span className="mono" style={{ fontWeight: 700 }}>
                      {formatINR(
                        Math.max(0, selectedOutstanding - advanceDeduction),
                      )}
                    </span>
                  </div>
                </div>
              </div>
            )}

            <div className="form-actions">
              <Button
                variant="secondary"
                type="button"
                onClick={() => setShowForm(false)}
              >
                Cancel
              </Button>
              <Button type="submit" loading={submitting}>
                Save Salary
              </Button>
            </div>
          </form>
        </Card>
      )}

      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card title="Salary Records" padded={false}>
          <div className="table-scroll">
            <Table columns={columns} rows={rows} empty="No salary records." />
          </div>
        </Card>
      </div>
    </>
  );
}
