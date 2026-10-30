import { Pencil, Plus, Trash2 } from "lucide-react";
import { FormEvent, useEffect, useState } from "react";
import Badge from "../components/ui/Badge";
import Button from "../components/ui/Button";
import Card from "../components/ui/Card";
import { Input, Select } from "../components/ui/Input";
import Table, { type Column } from "../components/ui/Table";
import { api, apiErrorMessage } from "../lib/api";
import { formatDate, formatINR, todayISO } from "../lib/format";

type Status = "active" | "on_notice" | "resigned" | "terminated" | "retired";

interface Employee {
  id: number;
  emp_code: string;
  full_name: string;
  designation: string;
  department: string | null;
  date_of_joining: string;
  status: Status;
  date_of_leaving: string | null;
  all_dues_clear: boolean;
  no_dues_email: string | null;
  basic_salary: string;
  hra: string;
  allowances: string;
  pan: string | null;
  uan: string | null;
  esi_no: string | null;
  is_active: boolean;
}

const STATUS_LABEL: Record<Status, string> = {
  active: "Active",
  on_notice: "On Notice",
  resigned: "Resigned",
  terminated: "Terminated",
  retired: "Retired",
};

const STATUS_TONE: Record<
  Status,
  "success" | "warning" | "neutral" | "danger" | "info"
> = {
  active: "success",
  on_notice: "warning",
  resigned: "neutral",
  terminated: "danger",
  retired: "info",
};

const emptyForm = {
  emp_code: "",
  full_name: "",
  designation: "",
  department: "",
  date_of_joining: todayISO(),
  status: "active" as Status,
  date_of_leaving: "",
  all_dues_clear: false,
  no_dues_email: "",
  basic_salary: "",
  hra: "",
  allowances: "",
  pan: "",
  uan: "",
  esi_no: "",
  is_active: true,
};

export default function Employees() {
  const [rows, setRows] = useState<Employee[]>([]);
  const [form, setForm] = useState({ ...emptyForm });
  const [editingId, setEditingId] = useState<number | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const load = async () => {
    try {
      const { data } = await api.get<Employee[]>("/employees", {
        params: { include_inactive: true },
      });
      setRows(data);
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  useEffect(() => {
    load();
  }, []);

  const set = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) =>
    setForm((f) => ({ ...f, [key]: value }));

  const openCreate = () => {
    setForm({ ...emptyForm });
    setEditingId(null);
    setShowForm(true);
    setError(null);
  };

  const openEdit = (emp: Employee) => {
    setForm({
      emp_code: emp.emp_code,
      full_name: emp.full_name,
      designation: emp.designation,
      department: emp.department ?? "",
      date_of_joining: emp.date_of_joining,
      status: emp.status,
      date_of_leaving: emp.date_of_leaving ?? "",
      all_dues_clear: emp.all_dues_clear,
      no_dues_email: emp.no_dues_email ?? "",
      basic_salary: emp.basic_salary,
      hra: emp.hra,
      allowances: emp.allowances,
      pan: emp.pan ?? "",
      uan: emp.uan ?? "",
      esi_no: emp.esi_no ?? "",
      is_active: emp.is_active,
    });
    setEditingId(emp.id);
    setShowForm(true);
    setError(null);
  };

  const closeForm = () => {
    setShowForm(false);
    setEditingId(null);
    setForm({ ...emptyForm });
  };

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);

    const payload = {
      emp_code: form.emp_code,
      full_name: form.full_name,
      designation: form.designation,
      department: form.department || null,
      date_of_joining: form.date_of_joining,
      status: form.status,
      date_of_leaving: form.date_of_leaving || null,
      all_dues_clear: form.all_dues_clear,
      no_dues_email: form.no_dues_email || null,
      basic_salary: Number(form.basic_salary || 0),
      hra: Number(form.hra || 0),
      allowances: Number(form.allowances || 0),
      pan: form.pan || null,
      uan: form.uan || null,
      esi_no: form.esi_no || null,
      is_active: form.is_active,
    };

    try {
      if (editingId !== null) {
        await api.put(`/employees/${editingId}`, payload);
      } else {
        await api.post("/employees", payload);
      }
      closeForm();
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  const remove = async (emp: Employee) => {
    if (
      !confirm(
        `Delete employee "${emp.full_name}"? This also removes their salary records.`,
      )
    )
      return;
    try {
      await api.delete(`/employees/${emp.id}`);
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  const columns: Column<Employee>[] = [
    {
      key: "code",
      header: "Code",
      render: (r) => <span className="mono">{r.emp_code}</span>,
    },
    {
      key: "name",
      header: "Name",
      render: (r) => <strong>{r.full_name}</strong>,
    },
    { key: "desig", header: "Designation", render: (r) => r.designation },
    { key: "dept", header: "Department", render: (r) => r.department || "—" },
    {
      key: "doj",
      header: "Joined",
      render: (r) => formatDate(r.date_of_joining),
    },
    {
      key: "status",
      header: "Status",
      render: (r) => (
        <Badge tone={STATUS_TONE[r.status]}>{STATUS_LABEL[r.status]}</Badge>
      ),
    },
    {
      key: "dol",
      header: "Left On",
      render: (r) => (r.date_of_leaving ? formatDate(r.date_of_leaving) : "—"),
    },
    {
      key: "dues",
      header: "Dues",
      render: (r) =>
        r.all_dues_clear ? (
          <Badge tone="success">Clear</Badge>
        ) : (
          <Badge tone="warning">Pending</Badge>
        ),
    },
    {
      key: "basic",
      header: "Basic",
      align: "right",
      render: (r) => <span className="mono">{formatINR(r.basic_salary)}</span>,
    },
    {
      key: "actions",
      header: "",
      align: "right",
      render: (r) => (
        <div style={{ display: "flex", gap: 4, justifyContent: "flex-end" }}>
          <button
            className="icon-btn"
            title="Edit employee"
            onClick={() => openEdit(r)}
          >
            <Pencil size={15} />
          </button>
          <button
            className="icon-btn"
            title="Delete employee"
            onClick={() => remove(r)}
          >
            <Trash2 size={15} />
          </button>
        </div>
      ),
    },
  ];

  const isEdit = editingId !== null;

  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Employees</h1>
          <p className="page-subtitle">
            {rows.length} employees ·{" "}
            {rows.filter((r) => r.status === "active").length} active
          </p>
        </div>
        <div className="page-actions">
          <Button
            variant={showForm ? "secondary" : "primary"}
            icon={<Plus size={15} />}
            onClick={showForm ? closeForm : openCreate}
          >
            {showForm ? "Cancel" : "New Employee"}
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
          title={isEdit ? `Edit Employee — ${form.full_name}` : "New Employee"}
          subtitle={
            isEdit
              ? "Update any field and save"
              : "All fields marked with * are required"
          }
        >
          <form onSubmit={onSubmit}>
            <div className="form-grid-3">
              <Input
                label="Employee Code *"
                value={form.emp_code}
                onChange={(e) => set("emp_code", e.target.value)}
                required
              />
              <Input
                label="Full Name *"
                value={form.full_name}
                onChange={(e) => set("full_name", e.target.value)}
                required
              />
              <Input
                label="Designation *"
                value={form.designation}
                onChange={(e) => set("designation", e.target.value)}
                required
              />
              <Input
                label="Department"
                value={form.department}
                onChange={(e) => set("department", e.target.value)}
              />
              <Input
                label="Date of Joining *"
                type="date"
                value={form.date_of_joining}
                onChange={(e) => set("date_of_joining", e.target.value)}
                required
              />
              <Select
                label="Employee Status *"
                value={form.status}
                onChange={(e) => set("status", e.target.value as Status)}
              >
                <option value="active">Active</option>
                <option value="on_notice">On Notice</option>
                <option value="resigned">Resigned</option>
                <option value="terminated">Terminated</option>
                <option value="retired">Retired</option>
              </Select>
              <Input
                label="Date of Leaving"
                type="date"
                value={form.date_of_leaving}
                onChange={(e) => set("date_of_leaving", e.target.value)}
              />
              <Select
                label="All Dues Clear"
                value={form.all_dues_clear ? "yes" : "no"}
                onChange={(e) =>
                  set("all_dues_clear", e.target.value === "yes")
                }
              >
                <option value="no">No — dues pending</option>
                <option value="yes">Yes — cleared</option>
              </Select>
              <Input
                label="No Dues Email / Confirmation"
                value={form.no_dues_email}
                onChange={(e) => set("no_dues_email", e.target.value)}
                hint="Email address or confirmation reference"
              />
              <Input
                label="Basic Salary *"
                type="number"
                step="0.01"
                value={form.basic_salary}
                onChange={(e) => set("basic_salary", e.target.value)}
                required
              />
              <Input
                label="HRA"
                type="number"
                step="0.01"
                value={form.hra}
                onChange={(e) => set("hra", e.target.value)}
              />
              <Input
                label="Allowances"
                type="number"
                step="0.01"
                value={form.allowances}
                onChange={(e) => set("allowances", e.target.value)}
              />
              <Input
                label="PAN"
                value={form.pan}
                onChange={(e) => set("pan", e.target.value)}
              />
              <Input
                label="UAN"
                value={form.uan}
                onChange={(e) => set("uan", e.target.value)}
              />
              <Input
                label="ESI No."
                value={form.esi_no}
                onChange={(e) => set("esi_no", e.target.value)}
              />
              <Select
                label="Show in lists"
                value={form.is_active ? "yes" : "no"}
                onChange={(e) => set("is_active", e.target.value === "yes")}
              >
                <option value="yes">Yes — visible</option>
                <option value="no">No — hidden</option>
              </Select>
            </div>

            <div className="form-actions">
              <Button variant="secondary" type="button" onClick={closeForm}>
                Cancel
              </Button>
              <Button type="submit" loading={submitting}>
                {isEdit ? "Save Changes" : "Create Employee"}
              </Button>
            </div>
          </form>
        </Card>
      )}

      <div style={{ marginTop: showForm ? 20 : 0 }}>
        <Card
          title="Employees"
          subtitle={`${rows.length} total · ${
            rows.filter((r) => r.status === "active").length
          } active`}
          padded={false}
        >
          <div className="table-scroll">
            <Table
              columns={columns}
              rows={rows}
              empty="No employees yet. Click New Employee to add one."
            />
          </div>
        </Card>
      </div>
    </>
  );
}
