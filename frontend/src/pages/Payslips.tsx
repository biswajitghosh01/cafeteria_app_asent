import { Download, Plus, RefreshCw } from "lucide-react";
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
  days_in_month: number;
  days_present: number;
  days_absent: number;
  days_on_leave: number;
  payable_days: number;
  daily_rate: string;
  base_gross: string;
  gross: string;
  pf_employee: string;
  pf_employer: string;
  esi_employee: string;
  esi_employer: string;
  income_tax: string;
  other_deductions: string;
  advance_deduction: string;
  advance_balance_before: string;
  advance_balance_after: string;
  net_pay: string;
  paid: boolean;
}

interface AttendancePreview {
  days_in_month: number;
  days_present: number;
  days_absent: number;
  days_on_leave: number;
  payable_days: number;
  base_gross: string;
  daily_rate: string;
  adjusted_gross: string;
  pf_employee: string;
  pf_employer: string;
  esi_employee: string;
  esi_employer: string;
  advance_outstanding: string;
}

const emptyForm = {
  employee_id: "",
  pay_period: new Date().toISOString().slice(0, 7),
  income_tax: "",
  other_deductions: "",
  advance_deduction: "",
  notes: "",
};

export default function Payslips() {
  const [rows, setRows] = useState<Salary[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [preview, setPreview] = useState<AttendancePreview | null>(null);
  const [loadingPreview, setLoadingPreview] = useState(false);

  const load = async () => {
    try {
      const [s, e] = await Promise.all([
        api.get<Salary[]>("/salary"),
        api.get<Employee[]>("/employees"),
      ]);
      setRows(s.data);
      setEmployees(e.data);
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  useEffect(() => {
    load();
  }, []);

  const set = (k: keyof typeof form, v: string) =>
    setForm((f) => ({ ...f, [k]: v }));

  const fetchPreview = async () => {
    if (!form.employee_id || !form.pay_period) {
      setPreview(null);
      return;
    }
    setLoadingPreview(true);
    try {
      const { data } = await api.get<AttendancePreview>(
        "/salary/attendance-preview",
        {
          params: {
            employee_id: Number(form.employee_id),
            pay_period: form.pay_period,
          },
        },
      );
      setPreview(data);
    } catch (err) {
      setError(apiErrorMessage(err));
      setPreview(null);
    } finally {
      setLoadingPreview(false);
    }
  };

  useEffect(() => {
    if (showForm) fetchPreview();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [form.employee_id, form.pay_period, showForm]);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!preview) {
      setError(
        "Could not load attendance. Mark attendance first, then try again.",
      );
      return;
    }

    const advanceOutstanding = Number(preview.advance_outstanding || 0);
    const advanceDeduction = Number(form.advance_deduction || 0);

    if (advanceDeduction < 0) {
      setError("Advance deduction cannot be negative");
      return;
    }
    if (advanceDeduction > advanceOutstanding) {
      setError(
        `Advance deduction (${advanceDeduction}) exceeds outstanding (${advanceOutstanding})`,
      );
      return;
    }

    setSubmitting(true);
    const gross = Number(preview.adjusted_gross);
    const pfEmp = Number(preview.pf_employee);
    const pfEr = Number(preview.pf_employer);
    const esiEmp = Number(preview.esi_employee);
    const esiEr = Number(preview.esi_employer);
    const it = Number(form.income_tax || 0);
    const other = Number(form.other_deductions || 0);
    const net = gross - pfEmp - esiEmp - it - other - advanceDeduction;

    try {
      await api.post("/salary", {
        employee_id: Number(form.employee_id),
        pay_period: form.pay_period,
        days_in_month: preview.days_in_month,
        days_present: preview.days_present,
        days_absent: preview.days_absent,
        days_on_leave: preview.days_on_leave,
        payable_days: preview.payable_days,
        daily_rate: Number(preview.daily_rate),
        base_gross: Number(preview.base_gross),
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

  const downloadPayslip = async (s: Salary) => {
    try {
      const res = await api.get(`/salary/${s.id}/payslip.pdf`, {
        responseType: "blob",
      });
      const url = URL.createObjectURL(res.data);
      const a = document.createElement("a");
      a.href = url;
      a.download = `payslip-${s.employee_name ?? s.employee_id}-${s.pay_period}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
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
      key: "days",
      header: "Days (P/A/L)",
      render: (r) => (
        <span className="mono" style={{ fontSize: 12 }}>
          <span style={{ color: "#059669" }}>{r.days_present}</span>
          {" / "}
          <span style={{ color: "#dc2626" }}>{r.days_absent}</span>
          {" / "}
          <span style={{ color: "#d97706" }}>{r.days_on_leave}</span>
        </span>
      ),
    },
    {
      key: "gross",
      header: "Gross",
      align: "right",
      render: (r) => <span className="mono">{formatINR(r.gross)}</span>,
    },
    {
      key: "deductions",
      header: "Statutory",
      align: "right",
      render: (r) => (
        <span className="mono">
          {formatINR(
            Number(r.pf_employee) +
              Number(r.esi_employee) +
              Number(r.income_tax) +
              Number(r.other_deductions),
          )}
        </span>
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
        <button
          className="icon-btn"
          onClick={() => downloadPayslip(r)}
          title="Download payslip PDF"
        >
          <Download size={15} />
        </button>
      ),
    },
  ];

  // Live totals for the preview
  const advanceOutstanding = Number(preview?.advance_outstanding ?? 0);
  const advanceDeduction = Number(form.advance_deduction || 0);
  const advanceAfter = Math.max(0, advanceOutstanding - advanceDeduction);

  const adjustedGross = Number(preview?.adjusted_gross ?? 0);
  const pfEmp = Number(preview?.pf_employee ?? 0);
  const esiEmp = Number(preview?.esi_employee ?? 0);
  const it = Number(form.income_tax || 0);
  const other = Number(form.other_deductions || 0);
  const liveNet =
    adjustedGross - pfEmp - esiEmp - it - other - advanceDeduction;

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Payslips</h1>
          <p className="page-subtitle">
            Salary computed from attendance — advance recovery optional
          </p>
        </div>
        <div className="page-actions">
          <Button
            variant={showForm ? "secondary" : "primary"}
            icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}
          >
            {showForm ? "Cancel" : "New Payslip"}
          </Button>
        </div>
      </div>

      {error && (
        <div className="login-error" style={{ marginBottom: 16 }}>
          {error}
        </div>
      )}

      {showForm && (
        <Card
          title="New Payslip"
          subtitle="Select employee and month to auto-compute from attendance"
        >
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
              <div style={{ display: "flex", alignItems: "flex-end", gap: 8 }}>
                <Button
                  type="button"
                  variant="secondary"
                  size="sm"
                  onClick={fetchPreview}
                  loading={loadingPreview}
                  icon={<RefreshCw size={14} />}
                >
                  Refresh
                </Button>
              </div>
              <Input
                label="Income Tax (TDS)"
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
                  advanceOutstanding > 0
                    ? `Outstanding: ${formatINR(advanceOutstanding)}`
                    : "No outstanding advance"
                }
                disabled={advanceOutstanding <= 0}
              />
              <Input
                label="Notes"
                value={form.notes}
                onChange={(e) => set("notes", e.target.value)}
              />
            </div>

            {preview && (
              <>
                <div className="preview-tile">
                  <span className="preview-label">Attendance summary</span>
                  <div className="preview-grid">
                    <div>
                      <span className="field-label">Days in Month</span>
                      <span className="mono">{preview.days_in_month}</span>
                    </div>
                    <div>
                      <span className="field-label">Present</span>
                      <span className="mono" style={{ color: "#059669" }}>
                        {preview.days_present}
                      </span>
                    </div>
                    <div>
                      <span className="field-label">Absent</span>
                      <span className="mono" style={{ color: "#dc2626" }}>
                        {preview.days_absent}
                      </span>
                    </div>
                    <div>
                      <span className="field-label">On Leave</span>
                      <span className="mono" style={{ color: "#d97706" }}>
                        {preview.days_on_leave}
                      </span>
                    </div>
                    <div>
                      <span className="field-label">Payable Days</span>
                      <span className="mono" style={{ fontWeight: 700 }}>
                        {preview.payable_days}
                      </span>
                    </div>
                    <div>
                      <span className="field-label">Daily Rate</span>
                      <span className="mono">
                        {formatINR(preview.daily_rate)}
                      </span>
                    </div>
                    <div>
                      <span className="field-label">Base Gross</span>
                      <span className="mono">
                        {formatINR(preview.base_gross)}
                      </span>
                    </div>
                    <div>
                      <span className="field-label">Adjusted Gross</span>
                      <span
                        className="mono"
                        style={{
                          fontWeight: 700,
                          color: "var(--color-success)",
                        }}
                      >
                        {formatINR(preview.adjusted_gross)}
                      </span>
                    </div>
                  </div>
                </div>

                {advanceOutstanding > 0 && (
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
                          {formatINR(advanceOutstanding)}
                        </span>
                      </div>
                      <div>
                        <span className="field-label">
                          Recovered This Month
                        </span>
                        <span className="mono">
                          {formatINR(advanceDeduction)}
                        </span>
                      </div>
                      <div>
                        <span className="field-label">Balance After</span>
                        <span className="mono" style={{ fontWeight: 700 }}>
                          {formatINR(advanceAfter)}
                        </span>
                      </div>
                    </div>
                  </div>
                )}

                <div className="preview-tile" style={{ marginTop: 12 }}>
                  <span className="preview-label">Computed net pay</span>
                  <div className="preview-grid">
                    <div>
                      <span className="field-label">PF (Employee)</span>
                      <span className="mono">
                        {formatINR(preview.pf_employee)}
                      </span>
                    </div>
                    <div>
                      <span className="field-label">ESI (Employee)</span>
                      <span className="mono">
                        {formatINR(preview.esi_employee)}
                      </span>
                    </div>
                    <div>
                      <span className="field-label">Income Tax</span>
                      <span className="mono">{formatINR(it)}</span>
                    </div>
                    <div>
                      <span className="field-label">Other</span>
                      <span className="mono">{formatINR(other)}</span>
                    </div>
                    <div>
                      <span className="field-label">Advance</span>
                      <span
                        className="mono"
                        style={{
                          color:
                            advanceDeduction > 0
                              ? "var(--color-danger)"
                              : undefined,
                        }}
                      >
                        {formatINR(advanceDeduction)}
                      </span>
                    </div>
                    <div>
                      <span className="field-label">Net Pay</span>
                      <span
                        className="mono"
                        style={{
                          fontWeight: 700,
                          color: "var(--color-success)",
                        }}
                      >
                        {formatINR(liveNet)}
                      </span>
                    </div>
                  </div>
                </div>
              </>
            )}

            {!preview &&
              form.employee_id &&
              form.pay_period &&
              !loadingPreview && (
                <div
                  style={{
                    marginTop: 16,
                    padding: "12px 14px",
                    background: "var(--color-warning-soft)",
                    color: "var(--color-warning)",
                    borderRadius: "var(--radius)",
                    fontSize: 12.5,
                  }}
                >
                  No attendance records found for this employee in{" "}
                  {form.pay_period}. Mark attendance first, or the salary will
                  compute to zero.
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
                Save Payslip
              </Button>
            </div>
          </form>
        </Card>
      )}

      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card
          title="Payroll Records"
          subtitle={`${rows.length} records`}
          padded={false}
        >
          <div className="table-scroll">
            <Table columns={columns} rows={rows} empty="No payroll records." />
          </div>
        </Card>
      </div>
    </>
  );
}
