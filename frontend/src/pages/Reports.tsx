import { Download, FileSpreadsheet, FileText } from "lucide-react";
import { useEffect, useState } from "react";
import Button from "../components/ui/Button";
import Card from "../components/ui/Card";
import { api, apiErrorMessage } from "../lib/api";
import { firstOfMonthISO, formatINR, todayISO } from "../lib/format";

interface DownloadDef {
  key: string;
  title: string;
  description: string;
  endpoint: string;
  params: "range" | "period" | "asOf";
  format: "xlsx" | "pdf";
}

interface ProfitLossReport {
  sales_revenue: number | string;
  purchases: number | string;
  gross_profit: number | string;
  commission_expense: number | string;
  compliance_expense: number | string;
  other_sales_expense: number | string;
  fixed_expenses: number | string;
  payroll_expense: number | string;
  total_expenses: number | string;
  net_profit: number | string;
}

interface BalanceSheetForm {
  cash_and_bank: string;
  accounts_receivable: string;
  inventory: string;
  other_current_assets: string;
  property_and_equipment: string;
  accounts_payable: string;
  loans_payable: string;
  gst_payable: string;
  other_liabilities: string;
  owner_capital: string;
  retained_earnings: string;
}

interface BalanceSheetReport extends BalanceSheetForm {
  as_of_date: string;
  total_assets: number | string;
  total_liabilities: number | string;
  total_equity: number | string;
  total_liabilities_and_equity: number | string;
}

type BalanceSheetField = keyof BalanceSheetForm;

const BALANCE_SHEET_FIELDS: {
  key: BalanceSheetField;
  label: string;
  group: "Assets" | "Liabilities" | "Equity";
}[] = [
  { key: "cash_and_bank", label: "Cash and bank", group: "Assets" },
  { key: "accounts_receivable", label: "Accounts receivable", group: "Assets" },
  { key: "inventory", label: "Inventory", group: "Assets" },
  { key: "other_current_assets", label: "Other current assets", group: "Assets" },
  { key: "property_and_equipment", label: "Property and equipment", group: "Assets" },
  { key: "accounts_payable", label: "Accounts payable", group: "Liabilities" },
  { key: "loans_payable", label: "Loans payable", group: "Liabilities" },
  { key: "gst_payable", label: "GST payable", group: "Liabilities" },
  { key: "other_liabilities", label: "Other liabilities", group: "Liabilities" },
  { key: "owner_capital", label: "Owner capital", group: "Equity" },
  { key: "retained_earnings", label: "Retained earnings", group: "Equity" },
];

const EMPTY_BALANCE_SHEET: BalanceSheetForm = {
  cash_and_bank: "0",
  accounts_receivable: "0",
  inventory: "0",
  other_current_assets: "0",
  property_and_equipment: "0",
  accounts_payable: "0",
  loans_payable: "0",
  gst_payable: "0",
  other_liabilities: "0",
  owner_capital: "0",
  retained_earnings: "0",
};

const balanceSheetFormFromReport = (
  report: BalanceSheetReport,
): BalanceSheetForm => ({
  cash_and_bank: String(report.cash_and_bank),
  accounts_receivable: String(report.accounts_receivable),
  inventory: String(report.inventory),
  other_current_assets: String(report.other_current_assets),
  property_and_equipment: String(report.property_and_equipment),
  accounts_payable: String(report.accounts_payable),
  loans_payable: String(report.loans_payable),
  gst_payable: String(report.gst_payable),
  other_liabilities: String(report.other_liabilities),
  owner_capital: String(report.owner_capital),
  retained_earnings: String(report.retained_earnings),
});

const DOWNLOADS: DownloadDef[] = [
  {
    key: "profit-loss-xlsx",
    title: "Profit and Loss Statement",
    description: "Income and expenses calculated from recorded transactions.",
    endpoint: "/reports/profit-loss.xlsx",
    params: "range",
    format: "xlsx",
  },
  {
    key: "profit-loss-pdf",
    title: "Profit and Loss Statement",
    description: "Printable profit and loss statement for the selected period.",
    endpoint: "/reports/profit-loss.pdf",
    params: "range",
    format: "pdf",
  },
  {
    key: "sales-xlsx",
    title: "Sales Register",
    description:
      "All sales with transaction value, TDS, GST, commission, compliance and other charges.",
    endpoint: "/reports/sales.xlsx",
    params: "range",
    format: "xlsx",
  },
  {
    key: "sales-pdf",
    title: "Sales Register",
    description: "Printable sales register for the selected period.",
    endpoint: "/reports/sales.pdf",
    params: "range",
    format: "pdf",
  },
  {
    key: "purchases-xlsx",
    title: "Purchases Register",
    description: "Vendor bills with inward GST for the selected period.",
    endpoint: "/reports/purchases.xlsx",
    params: "range",
    format: "xlsx",
  },
  {
    key: "purchases-pdf",
    title: "Purchases Register",
    description: "Printable purchases register.",
    endpoint: "/reports/purchases.pdf",
    params: "range",
    format: "pdf",
  },
  {
    key: "expenses-xlsx",
    title: "Fixed Expenses",
    description: "Rent, electricity, maintenance and other fixed expenses.",
    endpoint: "/reports/expenses.xlsx",
    params: "range",
    format: "xlsx",
  },
  {
    key: "expenses-pdf",
    title: "Fixed Expenses",
    description: "Printable fixed-expenses statement.",
    endpoint: "/reports/expenses.pdf",
    params: "range",
    format: "pdf",
  },
  {
    key: "salary-xlsx",
    title: "Salary Register",
    description:
      "Per-employee PF, ESI, income tax, other deductions and net pay.",
    endpoint: "/reports/salary.xlsx",
    params: "period",
    format: "xlsx",
  },
  {
    key: "salary-pdf",
    title: "Salary Register",
    description: "Printable salary register for the selected pay period.",
    endpoint: "/reports/salary.pdf",
    params: "period",
    format: "pdf",
  },
  {
    key: "balance-sheet-xlsx",
    title: "Balance Sheet",
    description: "Saved assets, liabilities, and equity as of the selected date.",
    endpoint: "/reports/balance-sheet.xlsx",
    params: "asOf",
    format: "xlsx",
  },
  {
    key: "balance-sheet-pdf",
    title: "Balance Sheet",
    description: "Printable balance sheet as of the selected date.",
    endpoint: "/reports/balance-sheet.pdf",
    params: "asOf",
    format: "pdf",
  },
];

export default function Reports() {
  const [start, setStart] = useState(firstOfMonthISO());
  const [end, setEnd] = useState(todayISO());
  const [period, setPeriod] = useState(new Date().toISOString().slice(0, 7));
  const [asOfDate, setAsOfDate] = useState(todayISO());
  const [balanceSheet, setBalanceSheet] =
    useState<BalanceSheetForm>(EMPTY_BALANCE_SHEET);
  const [balanceSheetExists, setBalanceSheetExists] = useState(false);
  const [balanceSheetLoading, setBalanceSheetLoading] = useState(true);
  const [profitLoss, setProfitLoss] = useState<ProfitLossReport | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    if (!asOfDate) {
      setBalanceSheetLoading(false);
      setBalanceSheetExists(false);
      return () => {
        active = false;
      };
    }
    setError(null);
    setBalanceSheetLoading(true);
    api
      .get<BalanceSheetReport | null>("/reports/balance-sheet", {
        params: { as_of_date: asOfDate },
      })
      .then(({ data }) => {
        if (!active) return;
        setBalanceSheet(
          data ? balanceSheetFormFromReport(data) : EMPTY_BALANCE_SHEET,
        );
        setBalanceSheetExists(data !== null);
      })
      .catch((err: unknown) => {
        if (active) setError(apiErrorMessage(err));
      })
      .finally(() => {
        if (active) setBalanceSheetLoading(false);
      });
    return () => {
      active = false;
    };
  }, [asOfDate]);

  const download = async (def: DownloadDef) => {
    setBusy(def.key);
    setError(null);
    setSuccess(null);
    try {
      const params =
        def.params === "range"
          ? { start, end }
          : def.params === "period"
            ? { pay_period: period }
            : { as_of_date: asOfDate };

      const res = await api.get(def.endpoint, {
        params,
        responseType: "blob",
      });

      // Try to derive filename from Content-Disposition header
      const disposition = res.headers["content-disposition"] as
        | string
        | undefined;
      const match = disposition?.match(/filename="?([^"]+)"?/);
      const filename = match?.[1] ?? `${def.key}.${def.format}`;

      const url = URL.createObjectURL(res.data);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusy(null);
    }
  };

  const generateProfitLoss = async () => {
    setBusy("profit-loss-preview");
    setError(null);
    setSuccess(null);
    try {
      const { data } = await api.get<ProfitLossReport>("/reports/profit-loss", {
        params: { start, end },
      });
      setProfitLoss(data);
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusy(null);
    }
  };

  const saveBalanceSheet = async () => {
    setBusy("balance-sheet-save");
    setError(null);
    setSuccess(null);
    try {
      await api.put("/reports/balance-sheet", {
        as_of_date: asOfDate,
        ...balanceSheet,
      });
      setBalanceSheetExists(true);
      setSuccess(`Balance sheet saved for ${asOfDate}.`);
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusy(null);
    }
  };

  const assetsTotal = BALANCE_SHEET_FIELDS.filter(
    (field) => field.group === "Assets",
  ).reduce((total, field) => total + Number(balanceSheet[field.key] || 0), 0);
  const liabilitiesTotal = BALANCE_SHEET_FIELDS.filter(
    (field) => field.group === "Liabilities",
  ).reduce((total, field) => total + Number(balanceSheet[field.key] || 0), 0);
  const equityTotal = BALANCE_SHEET_FIELDS.filter(
    (field) => field.group === "Equity",
  ).reduce((total, field) => total + Number(balanceSheet[field.key] || 0), 0);
  const balanceDifference = assetsTotal - liabilitiesTotal - equityTotal;
  const balanceAmountsValid = BALANCE_SHEET_FIELDS.every((field) => {
    const value = balanceSheet[field.key].trim();
    return (
      value !== "" &&
      Number.isFinite(Number(value)) &&
      (field.key === "retained_earnings" || Number(value) >= 0)
    );
  });

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Reports</h1>
          <p className="page-subtitle">
            Generate financial statements and download Excel or PDF registers
          </p>
        </div>
      </div>

      {error && (
        <div className="login-error" style={{ marginBottom: 16 }}>
          {error}
        </div>
      )}
      {success && (
        <div
          style={{
            marginBottom: 16,
            padding: 12,
            color: "var(--color-success)",
            background: "var(--color-success-soft)",
            borderRadius: "var(--radius-sm)",
          }}
        >
          {success}
        </div>
      )}

      <Card title="Reporting Period" padded>
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(3, 1fr)",
            gap: 12,
          }}
        >
          <label className="field">
            <span className="field-label">From</span>
            <input
              type="date"
              className="input"
              value={start}
              onChange={(e) => {
                setStart(e.target.value);
                setProfitLoss(null);
              }}
            />
          </label>
          <label className="field">
            <span className="field-label">To</span>
            <input
              type="date"
              className="input"
              value={end}
              onChange={(e) => {
                setEnd(e.target.value);
                setProfitLoss(null);
              }}
            />
          </label>
          <label className="field">
            <span className="field-label">Salary Pay Period</span>
            <input
              type="month"
              className="input"
              value={period}
              onChange={(e) => setPeriod(e.target.value)}
            />
          </label>
        </div>
      </Card>

      <Card
        title="Profit and Loss Statement"
        subtitle="Calculated from recorded sales, purchases, fixed expenses, and payroll."
        padded
      >
        <p style={{ color: "var(--text-muted)", marginTop: 0 }}>
          Sales and purchase GST are excluded where separately recorded.
          Commission and related charges use their pre-GST values. Fixed
          expenses use the amounts entered, and payroll includes gross pay plus
          employer PF/ESI by pay month, whether paid or unpaid. Purchases are
          treated as period costs because inventory and cost of goods sold are
          not tracked.
        </p>
        <Button
          loading={busy === "profit-loss-preview"}
          onClick={generateProfitLoss}
        >
          Generate statement
        </Button>
        {profitLoss && (
          <div style={{ marginTop: 20, overflowX: "auto" }}>
            <table className="data-table">
              <tbody>
                <tr>
                  <th>Statement line</th>
                  <th>Amount</th>
                </tr>
                <tr>
                  <td>Sales revenue (excluding output GST)</td>
                  <td>{formatINR(profitLoss.sales_revenue)}</td>
                </tr>
                <tr>
                  <td>Purchases (excluding input GST)</td>
                  <td>{formatINR(profitLoss.purchases)}</td>
                </tr>
                <tr>
                  <td>Gross profit</td>
                  <td>{formatINR(profitLoss.gross_profit)}</td>
                </tr>
                <tr>
                  <td>Commission expense (excluding GST)</td>
                  <td>{formatINR(profitLoss.commission_expense)}</td>
                </tr>
                <tr>
                  <td>Compliance expense (excluding GST)</td>
                  <td>{formatINR(profitLoss.compliance_expense)}</td>
                </tr>
                <tr>
                  <td>Other sales expense (excluding GST)</td>
                  <td>{formatINR(profitLoss.other_sales_expense)}</td>
                </tr>
                <tr>
                  <td>Fixed expenses (as recorded)</td>
                  <td>{formatINR(profitLoss.fixed_expenses)}</td>
                </tr>
                <tr>
                  <td>Payroll (gross plus employer PF/ESI)</td>
                  <td>{formatINR(profitLoss.payroll_expense)}</td>
                </tr>
                <tr>
                  <th>Total operating expenses</th>
                  <th>{formatINR(profitLoss.total_expenses)}</th>
                </tr>
                <tr>
                  <th>Net profit / (loss)</th>
                  <th>{formatINR(profitLoss.net_profit)}</th>
                </tr>
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card
        title="Balance Sheet"
        subtitle="Enter balances as of a date. Assets must equal liabilities plus equity."
        padded
      >
        <label className="field" style={{ maxWidth: 280, marginBottom: 16 }}>
          <span className="field-label">As of date</span>
          <input
            type="date"
            className="input"
            value={asOfDate}
            onChange={(event) => {
              setAsOfDate(event.target.value);
              setBalanceSheetExists(false);
              setBalanceSheet(EMPTY_BALANCE_SHEET);
              setSuccess(null);
            }}
          />
        </label>
        <p style={{ color: "var(--text-muted)" }}>
          This statement is entered manually because the app does not track all
          balance-sheet accounts. Amounts are saved as a dated snapshot.
        </p>
        {balanceSheetLoading ? (
          <p>Loading balance sheet…</p>
        ) : (
          <>
            {(["Assets", "Liabilities", "Equity"] as const).map((group) => (
              <div key={group} style={{ marginTop: 18 }}>
                <h3 className="card-title">{group}</h3>
                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))",
                    gap: 12,
                  }}
                >
                  {BALANCE_SHEET_FIELDS.filter((field) => field.group === group).map(
                    (field) => (
                      <label className="field" key={field.key}>
                        <span className="field-label">{field.label}</span>
                        <input
                          type="number"
                          min={field.key === "retained_earnings" ? undefined : "0"}
                          step="0.01"
                          className="input"
                          value={balanceSheet[field.key]}
                          onChange={(event) => {
                            setBalanceSheet((current) => ({
                              ...current,
                              [field.key]: event.target.value,
                            }));
                            setBalanceSheetExists(false);
                            setSuccess(null);
                          }}
                        />
                      </label>
                    ),
                  )}
                </div>
              </div>
            ))}
            <div style={{ marginTop: 20 }}>
              <strong>Total assets: {formatINR(assetsTotal)}</strong>
              <span style={{ margin: "0 16px", color: "var(--text-muted)" }}>
                Total liabilities and equity: {formatINR(liabilitiesTotal + equityTotal)}
              </span>
              <p
                style={{
                  color: balanceAmountsValid && Math.abs(balanceDifference) < 0.005
                    ? "var(--color-success)"
                    : "var(--color-danger)",
                }}
              >
                {!balanceAmountsValid
                  ? "Enter a valid amount for each balance."
                  : Math.abs(balanceDifference) < 0.005
                  ? "The balance sheet balances."
                  : `Difference: ${formatINR(balanceDifference)}. Adjust balances before saving.`}
              </p>
            </div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              <Button
                loading={busy === "balance-sheet-save"}
                disabled={
                  !balanceAmountsValid || Math.abs(balanceDifference) >= 0.005
                }
                onClick={saveBalanceSheet}
              >
                Save balance sheet
              </Button>
              {DOWNLOADS.filter((def) => def.params === "asOf").map((def) => (
                <Button
                  key={def.key}
                  variant="secondary"
                  size="sm"
                  icon={def.format === "xlsx" ? <FileSpreadsheet size={14} /> : <FileText size={14} />}
                  loading={busy === def.key}
                  disabled={!balanceSheetExists}
                  onClick={() => download(def)}
                >
                  Download {def.format.toUpperCase()}
                </Button>
              ))}
            </div>
          </>
        )}
      </Card>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))",
          gap: 16,
          marginTop: 20,
        }}
      >
        {DOWNLOADS.filter((def) => def.params !== "asOf").map((def) => (
          <Card key={def.key} padded>
            <div
              style={{
                display: "flex",
                gap: 12,
                alignItems: "flex-start",
              }}
            >
              <div style={{ color: "var(--color-primary-500)" }}>
                {def.format === "xlsx" ? (
                  <FileSpreadsheet size={22} />
                ) : (
                  <FileText size={22} />
                )}
              </div>
              <div style={{ flex: 1 }}>
                <strong style={{ display: "block", marginBottom: 4 }}>
                  {def.title} · {def.format.toUpperCase()}
                </strong>
                <p
                  style={{
                    fontSize: 12.5,
                    color: "var(--text-muted)",
                    margin: "0 0 12px",
                  }}
                >
                  {def.description}
                </p>
                <Button
                  size="sm"
                  icon={<Download size={14} />}
                  loading={busy === def.key}
                  onClick={() => download(def)}
                >
                  Download
                </Button>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </>
  );
}
