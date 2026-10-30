import { useEffect, useState } from "react";
import {
  ArrowDownRight,
  ArrowUpRight,
  IndianRupee,
  Receipt,
  Wallet,
  TrendingUp,
} from "lucide-react";
import Button from "../components/ui/Button";
import Card from "../components/ui/Card";
import StatTile from "../components/ui/StatTile";
import { api, apiErrorMessage } from "../lib/api";
import {
  firstOfMonthISO,
  formatDate,
  formatINR,
  todayISO,
} from "../lib/format";

interface Summary {
  period_start: string;
  period_end: string;
  total_transaction_value: string;
  total_tds: string;
  total_gst_payable: string;
  total_commission: string;
  total_compliance: string;
  total_other: string;
  total_charges: string;
  total_net_payable: string;
  total_purchases: string;
  total_fixed_expenses: string;
  total_salary_paid: string;
  net_position: string;
}

export default function Dashboard() {
  const [start, setStart] = useState(firstOfMonthISO());
  const [end, setEnd] = useState(todayISO());
  const [data, setData] = useState<Summary | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const { data } = await api.get<Summary>("/reports/dashboard", {
        params: { start, end },
      });
      setData(data);
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const positive = Number(data?.net_position ?? 0) >= 0;

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Dashboard</h1>
          <p className="page-subtitle">
            {data
              ? `${formatDate(data.period_start)} – ${formatDate(data.period_end)}`
              : "Loading…"}
          </p>
        </div>
        <div className="page-actions">
          <input
            type="date"
            className="input"
            value={start}
            onChange={(e) => setStart(e.target.value)}
          />
          <span style={{ color: "var(--text-muted)" }}>→</span>
          <input
            type="date"
            className="input"
            value={end}
            onChange={(e) => setEnd(e.target.value)}
          />
          <Button onClick={load} loading={loading}>
            Apply
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
          label="Transaction Value"
          value={formatINR(data?.total_transaction_value ?? 0)}
          icon={<TrendingUp size={18} />}
        />
        <StatTile
          label="TDS (0.1%)"
          value={formatINR(data?.total_tds ?? 0)}
          icon={<ArrowDownRight size={18} />}
          tone="warning"
        />
        <StatTile
          label="GST Payable (5%)"
          value={formatINR(data?.total_gst_payable ?? 0)}
          tone="warning"
        />
        <StatTile
          label="Commission"
          value={formatINR(data?.total_commission ?? 0)}
          icon={<IndianRupee size={18} />}
        />
        <StatTile
          label="Compliance"
          value={formatINR(data?.total_compliance ?? 0)}
        />
        <StatTile
          label="Other Deductions"
          value={formatINR(data?.total_other ?? 0)}
        />
        <StatTile
          label="Total Charges"
          value={formatINR(data?.total_charges ?? 0)}
          tone="danger"
          icon={<Receipt size={18} />}
        />
        <StatTile
          label="Net Payable"
          value={formatINR(data?.total_net_payable ?? 0)}
          tone="success"
          icon={<Wallet size={18} />}
        />
        <StatTile
          label="Purchases"
          value={formatINR(data?.total_purchases ?? 0)}
          icon={<Receipt size={18} />}
        />
        <StatTile
          label="Fixed Expenses"
          value={formatINR(data?.total_fixed_expenses ?? 0)}
          tone="danger"
        />
        <StatTile
          label="Salary Paid"
          value={formatINR(data?.total_salary_paid ?? 0)}
          tone="danger"
        />
        <StatTile
          label="Net Position"
          value={formatINR(data?.net_position ?? 0)}
          tone={positive ? "success" : "danger"}
          icon={
            positive ? <ArrowUpRight size={18} /> : <ArrowDownRight size={18} />
          }
        />
      </div>

      <div className="grid-2">
        <Card title="Sales Composition" subtitle="Current period">
          <CompositionBars data={data} />
        </Card>
        <Card title="Net Payable" subtitle="Transaction Value − Total Charges">
          <div
            className="mono"
            style={{
              fontSize: 32,
              fontWeight: 700,
              color: "var(--color-success)",
            }}
          >
            {formatINR(data?.total_net_payable ?? 0)}
          </div>
          <p
            style={{ color: "var(--text-muted)", fontSize: 12.5, marginTop: 6 }}
          >
            Amount payable after deducting TDS, GST, Commission, Compliance and
            Other charges.
          </p>
        </Card>
      </div>
    </>
  );
}

function CompositionBars({ data }: { data: Summary | null }) {
  if (!data) return <div className="table-empty">No data.</div>;

  const rows = [
    {
      label: "Commission",
      value: Number(data.total_commission),
      color: "#1e3a5f",
    },
    {
      label: "Compliance",
      value: Number(data.total_compliance),
      color: "#2563eb",
    },
    { label: "Other", value: Number(data.total_other), color: "#7c3aed" },
    { label: "TDS", value: Number(data.total_tds), color: "#d97706" },
    { label: "GST", value: Number(data.total_gst_payable), color: "#0891b2" },
  ];
  const max = Math.max(...rows.map((r) => r.value), 1);

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
      {rows.map((r) => (
        <div key={r.label}>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              marginBottom: 6,
              fontSize: 12.5,
            }}
          >
            <span style={{ color: "var(--text-muted)" }}>{r.label}</span>
            <span className="mono" style={{ color: "var(--text-strong)" }}>
              {formatINR(r.value)}
            </span>
          </div>
          <div
            style={{
              height: 8,
              background: "var(--bg-muted)",
              borderRadius: 999,
              overflow: "hidden",
            }}
          >
            <div
              style={{
                width: `${(r.value / max) * 100}%`,
                height: "100%",
                background: r.color,
                transition: "width .4s ease",
              }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}
