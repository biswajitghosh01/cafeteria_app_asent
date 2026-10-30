import {
  ChevronLeft,
  ChevronRight,
  CheckCircle2,
  Calendar,
} from "lucide-react";
import { useEffect, useState } from "react";
import Button from "../components/ui/Button";
import Card from "../components/ui/Card";
import { api, apiErrorMessage } from "../lib/api";

type Status = "present" | "absent" | "on_leave";

interface MonthRow {
  employee_id: number;
  employee_name: string;
  emp_code: string;
  days: Record<string, Status | null>;
  present: number;
  absent: number;
  on_leave: number;
  payable_days: number;
}

interface MonthResponse {
  year: number;
  month: number;
  days_in_month: number;
  employees: MonthRow[];
}

const MONTH_NAMES = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const DAY_INITIALS = ["S", "M", "T", "W", "T", "F", "S"];

const CYCLE: (Status | null)[] = ["present", "absent", "on_leave", null];

const STATUS_BG: Record<Status, string> = {
  present: "#059669",
  absent: "#dc2626",
  on_leave: "#d97706",
};

const STATUS_LABEL: Record<Status, string> = {
  present: "Present",
  absent: "Absent",
  on_leave: "On Leave",
};

export default function Attendance() {
  const today = new Date();
  const [year, setYear] = useState(today.getFullYear());
  const [month, setMonth] = useState(today.getMonth() + 1);
  const [data, setData] = useState<MonthResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [savingCell, setSavingCell] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const { data } = await api.get<MonthResponse>("/attendance/month", {
        params: { year, month },
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
  }, [year, month]);

  const prevMonth = () => {
    if (month === 1) {
      setYear(year - 1);
      setMonth(12);
    } else {
      setMonth(month - 1);
    }
  };

  const nextMonth = () => {
    if (month === 12) {
      setYear(year + 1);
      setMonth(1);
    } else {
      setMonth(month + 1);
    }
  };

  const cycleStatus = (current: Status | null): Status | null => {
    const idx = CYCLE.indexOf(current);
    return CYCLE[(idx + 1) % CYCLE.length];
  };

  const handleCellClick = async (
    employeeId: number,
    dateStr: string,
    current: Status | null,
  ) => {
    const next = cycleStatus(current);
    setSavingCell(`${employeeId}-${dateStr}`);

    // Optimistic update
    setData((prev) => {
      if (!prev) return prev;
      return {
        ...prev,
        employees: prev.employees.map((emp) =>
          emp.employee_id === employeeId
            ? { ...emp, days: { ...emp.days, [dateStr]: next } }
            : emp,
        ),
      };
    });

    try {
      if (next === null) {
        // Remove entry — look it up
        const all = await api.get(`/attendance`, {
          params: { employee_id: employeeId, year, month },
        });
        const existing = all.data.find(
          (r: { attendance_date: string }) => r.attendance_date === dateStr,
        );
        if (existing) {
          await api.delete(`/attendance/${existing.id}`);
        }
      } else {
        await api.post("/attendance", {
          employee_id: employeeId,
          attendance_date: dateStr,
          status: next,
        });
      }
      // Reload to get accurate totals
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
      await load();
    } finally {
      setSavingCell(null);
    }
  };

  const markAllPresent = async (employeeId: number) => {
    if (!data) return;
    if (!confirm("Mark every day of this month as Present for this employee?"))
      return;

    const entries = [];
    for (let d = 1; d <= data.days_in_month; d++) {
      const dateStr = `${year}-${String(month).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
      entries.push({
        employee_id: employeeId,
        attendance_date: dateStr,
        status: "present",
      });
    }

    try {
      await api.post("/attendance/bulk", { entries });
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  const markAllPresentForAll = async () => {
    if (!data) return;
    if (
      !confirm(
        `Mark every day of ${MONTH_NAMES[month - 1]} as Present for ALL ${data.employees.length} employees?`,
      )
    )
      return;

    const entries = [];
    for (const emp of data.employees) {
      for (let d = 1; d <= data.days_in_month; d++) {
        const dateStr = `${year}-${String(month).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
        entries.push({
          employee_id: emp.employee_id,
          attendance_date: dateStr,
          status: "present",
        });
      }
    }

    try {
      await api.post("/attendance/bulk", { entries });
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  const dayHeader = (d: number): { label: string; isWeekend: boolean } => {
    const dateObj = new Date(year, month - 1, d);
    const dow = dateObj.getDay();
    return {
      label: DAY_INITIALS[dow],
      isWeekend: dow === 0 || dow === 6,
    };
  };

  const days = data
    ? Array.from({ length: data.days_in_month }, (_, i) => i + 1)
    : [];

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Attendance</h1>
          <p className="page-subtitle">
            Click a cell to cycle: Present → Absent → On Leave → clear
          </p>
        </div>
        <div className="page-actions">
          <div
            className="month-picker"
            role="group"
            aria-label="Month navigation"
          >
            <button
              type="button"
              className="icon-btn"
              onClick={prevMonth}
              aria-label="Previous month"
              title="Previous month"
            >
              <ChevronLeft size={16} />
            </button>
            <span className="month-picker-label" aria-live="polite">
              {MONTH_NAMES[month - 1]} {year}
            </span>
            <button
              type="button"
              className="icon-btn"
              onClick={nextMonth}
              aria-label="Next month"
              title="Next month"
            >
              <ChevronRight size={16} />
            </button>
          </div>
        </div>
      </div>

      {error && (
        <div className="login-error" style={{ marginBottom: 16 }}>
          {error}
        </div>
      )}

      {/* Legend */}
      <Card padded>
        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            gap: 20,
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <div style={{ display: "flex", gap: 20, flexWrap: "wrap" }}>
            <LegendItem color="#059669" label="Present" />
            <LegendItem color="#dc2626" label="Absent" />
            <LegendItem color="#d97706" label="On Leave" />
            <LegendItem color="#e2e8f0" label="Not marked" border />
          </div>
          <div>
            <Button
              size="sm"
              variant="secondary"
              icon={<Calendar size={14} />}
              onClick={markAllPresentForAll}
              loading={loading}
            >
              Mark all Present (all employees)
            </Button>
          </div>
        </div>
      </Card>

      <div style={{ marginTop: 20 }}>
        <Card
          title={`${MONTH_NAMES[month - 1]} ${year}`}
          subtitle={
            data
              ? `${data.employees.length} employees · ${data.days_in_month} days`
              : "Loading…"
          }
          padded={false}
        >
          {loading && !data ? (
            <div className="table-empty">Loading…</div>
          ) : !data || data.employees.length === 0 ? (
            <div className="table-empty">
              No active employees. Add employees first, then come back to mark
              attendance.
            </div>
          ) : (
            <div className="table-scroll">
              <table className="data-table attendance-table">
                <thead>
                  <tr>
                    <th
                      style={{
                        position: "sticky",
                        left: 0,
                        background: "var(--bg-muted)",
                        zIndex: 2,
                        minWidth: 200,
                      }}
                    >
                      Employee
                    </th>
                    {days.map((d) => {
                      const { label, isWeekend } = dayHeader(d);
                      return (
                        <th
                          key={d}
                          style={{
                            textAlign: "center",
                            minWidth: 28,
                            padding: "6px 2px",
                            background: isWeekend
                              ? "#e2e8f0"
                              : "var(--bg-muted)",
                          }}
                        >
                          <div style={{ fontSize: 9, opacity: 0.7 }}>
                            {label}
                          </div>
                          <div style={{ fontSize: 11 }}>{d}</div>
                        </th>
                      );
                    })}
                    <th style={{ textAlign: "center", minWidth: 40 }}>P</th>
                    <th style={{ textAlign: "center", minWidth: 40 }}>A</th>
                    <th style={{ textAlign: "center", minWidth: 40 }}>L</th>
                    <th style={{ textAlign: "center", minWidth: 60 }}>
                      Payable
                    </th>
                    <th style={{ textAlign: "center", minWidth: 80 }}></th>
                  </tr>
                </thead>
                <tbody>
                  {data.employees.map((emp) => (
                    <tr key={emp.employee_id}>
                      <td
                        style={{
                          position: "sticky",
                          left: 0,
                          background: "var(--bg-surface)",
                          zIndex: 1,
                          whiteSpace: "nowrap",
                        }}
                      >
                        <strong>{emp.employee_name}</strong>
                        <div
                          style={{ fontSize: 11, color: "var(--text-muted)" }}
                        >
                          {emp.emp_code}
                        </div>
                      </td>
                      {days.map((d) => {
                        const dateStr = `${year}-${String(month).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
                        const status = emp.days[dateStr] ?? null;
                        const isSaving =
                          savingCell === `${emp.employee_id}-${dateStr}`;
                        return (
                          <td
                            key={d}
                            style={{
                              padding: 2,
                              textAlign: "center",
                            }}
                          >
                            <button
                              onClick={() =>
                                handleCellClick(
                                  emp.employee_id,
                                  dateStr,
                                  status,
                                )
                              }
                              title={
                                status
                                  ? `${dateStr}: ${STATUS_LABEL[status]}`
                                  : `${dateStr}: Not marked`
                              }
                              style={{
                                width: 26,
                                height: 26,
                                borderRadius: 6,
                                border:
                                  status === null
                                    ? "1px solid var(--border)"
                                    : "none",
                                background:
                                  status === null ? "white" : STATUS_BG[status],
                                color: "white",
                                cursor: "pointer",
                                display: "inline-flex",
                                alignItems: "center",
                                justifyContent: "center",
                                fontSize: 11,
                                fontWeight: 600,
                                opacity: isSaving ? 0.5 : 1,
                                transition: "opacity .15s, background .15s",
                              }}
                            >
                              {status === "present" && "P"}
                              {status === "absent" && "A"}
                              {status === "on_leave" && "L"}
                            </button>
                          </td>
                        );
                      })}
                      <td
                        style={{
                          textAlign: "center",
                          fontWeight: 600,
                          color: "#059669",
                        }}
                      >
                        {emp.present}
                      </td>
                      <td
                        style={{
                          textAlign: "center",
                          fontWeight: 600,
                          color: "#dc2626",
                        }}
                      >
                        {emp.absent}
                      </td>
                      <td
                        style={{
                          textAlign: "center",
                          fontWeight: 600,
                          color: "#d97706",
                        }}
                      >
                        {emp.on_leave}
                      </td>
                      <td style={{ textAlign: "center", fontWeight: 700 }}>
                        {emp.payable_days} / {data.days_in_month}
                      </td>
                      <td style={{ textAlign: "center" }}>
                        <button
                          className="icon-btn"
                          title="Mark all days present"
                          onClick={() => markAllPresent(emp.employee_id)}
                        >
                          <CheckCircle2 size={15} />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>

      <div style={{ marginTop: 20 }}>
        <Card title="How salary is calculated" padded>
          <div
            style={{
              fontSize: 13,
              color: "var(--text-muted)",
              lineHeight: 1.8,
            }}
          >
            <p style={{ margin: "0 0 8px" }}>
              <strong style={{ color: "var(--text-strong)" }}>
                Daily Rate
              </strong>{" "}
              = Base Gross ÷ Days in Month
            </p>
            <p style={{ margin: "0 0 8px" }}>
              <strong style={{ color: "var(--text-strong)" }}>
                Payable Days
              </strong>{" "}
              = Days marked{" "}
              <span style={{ color: "#059669", fontWeight: 600 }}>Present</span>
            </p>
            <p style={{ margin: "0 0 8px" }}>
              <strong style={{ color: "var(--text-strong)" }}>
                Adjusted Gross
              </strong>{" "}
              = Daily Rate × Payable Days
            </p>
            <p style={{ margin: 0 }}>
              PF, ESI, and Income Tax are then computed on the Adjusted Gross.
              Both{" "}
              <span style={{ color: "#dc2626", fontWeight: 600 }}>Absent</span>{" "}
              and{" "}
              <span style={{ color: "#d97706", fontWeight: 600 }}>
                On Leave
              </span>{" "}
              days reduce the payable days.
            </p>
          </div>
        </Card>
      </div>
    </>
  );
}

function LegendItem({
  color,
  label,
  border = false,
}: {
  color: string;
  label: string;
  border?: boolean;
}) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
      <span
        style={{
          width: 16,
          height: 16,
          borderRadius: 4,
          background: color,
          border: border ? "1px solid var(--border-strong)" : "none",
        }}
      />
      <span style={{ fontSize: 12.5, color: "var(--text-muted)" }}>
        {label}
      </span>
    </div>
  );
}
