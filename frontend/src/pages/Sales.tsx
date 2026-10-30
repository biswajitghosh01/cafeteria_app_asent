import { FormEvent, useEffect, useState } from "react";
import { Plus, Trash2 } from "lucide-react";
import Button from "../components/ui/Button";
import Card from "../components/ui/Card";
import { Input } from "../components/ui/Input";
import Table, { type Column } from "../components/ui/Table";
import { api, apiErrorMessage } from "../lib/api";
import {
  firstOfMonthISO,
  formatDate,
  formatINR,
  todayISO,
} from "../lib/format";

interface Sale {
  id: number;
  invoice_no: string;
  period_start: string;
  period_end: string;
  customer: string;
  transaction_value: string;
  tds: string;
  gst_payable: string;
  commission_gross: string;
  compliance_gross: string;
  other_gross: string;
  total_gross: string;
  net_receivable: string;
}

const TDS_RATE = 0.001;
const FOOD_GST_RATE = 0.05;

const emptyForm = {
  invoice_no: "",
  period_start: firstOfMonthISO(),
  period_end: todayISO(),
  customer: "",
  transaction_value: "",
  commission_gross: "",
  compliance_gross: "",
  other_gross: "",
  notes: "",
};

export default function Sales() {
  const [rows, setRows] = useState<Sale[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const load = async () => {
    try {
      const { data } = await api.get<Sale[]>("/sales");
      setRows(data);
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  useEffect(() => {
    load();
  }, []);

  const set = (k: keyof typeof form, v: string) =>
    setForm((f) => ({ ...f, [k]: v }));

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);

    const payload = {
      invoice_no: form.invoice_no,
      period_start: form.period_start,
      period_end: form.period_end,
      customer: form.customer,
      notes: form.notes || null,
      transaction_value: Number(form.transaction_value || 0),
      commission_gross: Number(form.commission_gross || 0),
      compliance_gross: Number(form.compliance_gross || 0),
      other_gross: Number(form.other_gross || 0),
      // All of these are recomputed server-side
      tds: 0,
      gst_payable: 0,
      commission_base: 0,
      commission_gst: 0,
      compliance_base: 0,
      compliance_gst: 0,
      other_base: 0,
      other_gst: 0,
      total_gross: 0,
      net_receivable: 0,
    };

    try {
      await api.post("/sales", payload);
      setForm({ ...emptyForm });
      setShowForm(false);
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  const remove = async (id: number) => {
    if (!confirm("Delete this sale record?")) return;
    await api.delete(`/sales/${id}`);
    await load();
  };

  // ---- Live preview of auto-computed values ----
  const tv = Number(form.transaction_value || 0);
  const commission = Number(form.commission_gross || 0);
  const compliance = Number(form.compliance_gross || 0);
  const other = Number(form.other_gross || 0);

  const previewTds = +(tv * TDS_RATE).toFixed(2);
  const previewGst = +(tv - tv / (1 + FOOD_GST_RATE)).toFixed(2);
  const previewCharges =
    previewTds + previewGst + commission + compliance + other;
  const previewNet = +(tv - previewCharges).toFixed(2);

  // ---- Totals for the list footer ----
  const totalCharges = rows.reduce((s, r) => s + Number(r.total_gross), 0);
  const totalNet = rows.reduce((s, r) => s + Number(r.net_receivable), 0);

  const columns: Column<Sale>[] = [
    {
      key: "period",
      header: "Period",
      render: (r) => (
        <span style={{ whiteSpace: "nowrap" }}>
          {formatDate(r.period_start)} – {formatDate(r.period_end)}
        </span>
      ),
    },
    {
      key: "invoice",
      header: "Invoice",
      render: (r) => <span className="mono">{r.invoice_no}</span>,
    },
    {
      key: "customer",
      header: "Customer",
      render: (r) => r.customer,
    },
    {
      key: "tv",
      header: "Transaction Value",
      align: "right",
      render: (r) => (
        <span className="mono">{formatINR(r.transaction_value)}</span>
      ),
    },
    {
      key: "tds",
      header: "TDS (0.1%)",
      align: "right",
      render: (r) => <span className="mono">{formatINR(r.tds)}</span>,
    },
    {
      key: "gst",
      header: "GST (5%)",
      align: "right",
      render: (r) => <span className="mono">{formatINR(r.gst_payable)}</span>,
    },
    {
      key: "commission",
      header: "Commission",
      align: "right",
      render: (r) => (
        <span className="mono">{formatINR(r.commission_gross)}</span>
      ),
    },
    {
      key: "compliance",
      header: "Compliance",
      align: "right",
      render: (r) => (
        <span className="mono">{formatINR(r.compliance_gross)}</span>
      ),
    },
    {
      key: "other",
      header: "Other",
      align: "right",
      render: (r) => <span className="mono">{formatINR(r.other_gross)}</span>,
    },
    {
      key: "charges",
      header: "Total Charges",
      align: "right",
      render: (r) => <span className="mono">{formatINR(r.total_gross)}</span>,
    },
    {
      key: "net",
      header: "Net Payable",
      align: "right",
      render: (r) => (
        <strong className="mono" style={{ color: "var(--color-success)" }}>
          {formatINR(r.net_receivable)}
        </strong>
      ),
    },
    {
      key: "actions",
      header: "",
      align: "right",
      render: (r) => (
        <button
          className="icon-btn"
          onClick={() => remove(r.id)}
          title="Delete"
        >
          <Trash2 size={15} />
        </button>
      ),
    },
  ];

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Sales</h1>
          <p className="page-subtitle">
            Enter the transaction value and charges — Net Payable is computed
            automatically
          </p>
        </div>
        <div className="page-actions">
          <Button
            variant={showForm ? "secondary" : "primary"}
            icon={<Plus size={15} />}
            onClick={() => setShowForm((s) => !s)}
          >
            {showForm ? "Cancel" : "New Sale"}
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
          title="New Sales Entry"
          subtitle="All amounts inclusive of the GST noted in the label"
        >
          <form onSubmit={onSubmit}>
            <div className="form-grid-3">
              <Input
                label="Invoice No."
                value={form.invoice_no}
                onChange={(e) => set("invoice_no", e.target.value)}
                required
              />
              <Input
                label="Period Start"
                type="date"
                value={form.period_start}
                onChange={(e) => set("period_start", e.target.value)}
                required
              />
              <Input
                label="Period End"
                type="date"
                value={form.period_end}
                onChange={(e) => set("period_end", e.target.value)}
                required
              />
              <Input
                label="Customer"
                value={form.customer}
                onChange={(e) => set("customer", e.target.value)}
                required
              />
              <Input
                label="Transaction Value (incl. GST 5%)"
                type="number"
                step="0.01"
                value={form.transaction_value}
                onChange={(e) => set("transaction_value", e.target.value)}
                required
              />
              <Input
                label="Commission (incl. GST 18%)"
                type="number"
                step="0.01"
                value={form.commission_gross}
                onChange={(e) => set("commission_gross", e.target.value)}
              />
              <Input
                label="Compliance Fee (incl. GST 18%)"
                type="number"
                step="0.01"
                value={form.compliance_gross}
                onChange={(e) => set("compliance_gross", e.target.value)}
              />
              <Input
                label="Other Deductions (incl. GST 18%)"
                type="number"
                step="0.01"
                value={form.other_gross}
                onChange={(e) => set("other_gross", e.target.value)}
              />
              <Input
                label="Notes (optional)"
                value={form.notes}
                onChange={(e) => set("notes", e.target.value)}
              />
            </div>

            <div className="preview-tile">
              <span className="preview-label">Auto-computed</span>
              <div className="preview-grid">
                <div>
                  <span className="field-label">TDS (0.1%)</span>
                  <span className="mono">{formatINR(previewTds)}</span>
                </div>
                <div>
                  <span className="field-label">GST Payable (5%)</span>
                  <span className="mono">{formatINR(previewGst)}</span>
                </div>
                <div>
                  <span className="field-label">Total Charges</span>
                  <span className="mono">{formatINR(previewCharges)}</span>
                </div>
                <div>
                  <span className="field-label">Net Payable</span>
                  <span
                    className="mono"
                    style={{ color: "var(--color-success)" }}
                  >
                    {formatINR(previewNet)}
                  </span>
                </div>
              </div>
            </div>

            <div className="form-actions">
              <Button
                variant="secondary"
                type="button"
                onClick={() => setShowForm(false)}
              >
                Cancel
              </Button>
              <Button type="submit" loading={submitting}>
                Save Sale
              </Button>
            </div>
          </form>
        </Card>
      )}

      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card
          title="Sales Records"
          subtitle={`${rows.length} records · Total Charges: ${formatINR(
            totalCharges,
          )} · Total Net: ${formatINR(totalNet)}`}
          padded={false}
        >
          <div className="table-scroll">
            <Table
              columns={columns}
              rows={rows}
              empty="No sales recorded yet."
            />
          </div>
        </Card>
      </div>
    </>
  );
}
