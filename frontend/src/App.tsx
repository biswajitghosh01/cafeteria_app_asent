import { useEffect } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import AdminRoute from "./components/AdminRoute";
import AppLayout from "./components/Layout/AppLayout";
import ProtectedRoute from "./components/ProtectedRoute";
import { applyBrandingToDocument } from "./config/branding.config";
import AdminConsole from "./pages/admin/AdminConsole";
import Advances from "./pages/Advances";
import Attendance from "./pages/Attendance";
import AuditLogs from "./pages/AuditLogs";
import Dashboard from "./pages/Dashboard";
import Documents from "./pages/Documents";
import Employees from "./pages/Employees";
import Expenses from "./pages/Expenses";
import Login from "./pages/Login";
import Payslips from "./pages/Payslips";
import Purchases from "./pages/Purchases";
import Reports from "./pages/Reports";
import Salary from "./pages/Salary";
import Sales from "./pages/Sales";
import Settings from "./pages/Settings";

export default function App() {
  useEffect(() => {
    applyBrandingToDocument();
  }, []);

  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route element={<ProtectedRoute />}>
        <Route element={<AppLayout />}>
          <Route index element={<Dashboard />} />
          <Route path="sales" element={<Sales />} />
          <Route path="purchases" element={<Purchases />} />
          <Route path="expenses" element={<Expenses />} />
          <Route path="employees" element={<Employees />} />
          <Route path="attendance" element={<Attendance />} />
          <Route path="salary" element={<Salary />} />
          <Route path="payslips" element={<Payslips />} />
          <Route path="advances" element={<Advances />} />
          <Route path="documents" element={<Documents />} />
          <Route path="reports" element={<Reports />} />
          <Route path="settings" element={<Settings />} />
          <Route element={<AdminRoute />}>
            <Route path="admin" element={<AdminConsole />} />
            <Route path="audit" element={<AuditLogs />} />
          </Route>
        </Route>
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
