import {
  BarChart3,
  Calendar,
  Coins,
  FileText,
  Files,
  LayoutDashboard,
  Package,
  Receipt,
  ScrollText,
  Settings as SettingsIcon,
  ShieldCheck,
  ShoppingCart,
  Users,
  Wallet,
} from "lucide-react";
import { NavLink } from "react-router-dom";
import { branding } from "../../config/branding.config";
import { useAuth } from "../../context/AuthContext";

const NAV = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard, end: true },
  { to: "/sales", label: "Sales", icon: ShoppingCart },
  { to: "/purchases", label: "Purchases", icon: Package },
  { to: "/expenses", label: "Fixed Expenses", icon: Receipt },
  { to: "/employees", label: "Employees", icon: Users },
  { to: "/attendance", label: "Attendance", icon: Calendar },
  { to: "/salary", label: "Salary & Statutory", icon: Wallet },
  { to: "/payslips", label: "Payslips", icon: FileText },
  { to: "/advances", label: "Advances", icon: Coins },
  { to: "/documents", label: "Documents", icon: Files },
  { to: "/reports", label: "Reports", icon: BarChart3 },
  { to: "/settings", label: "Settings", icon: SettingsIcon },
];

export default function Sidebar() {
  const { user } = useAuth();
  const isAdmin = user?.role === "admin";

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        <img src={branding.logoUrl} alt={branding.companyName} />
        <div className="sidebar-brand-text">
          <strong>{branding.companyName}</strong>
          <small>{branding.titleModifier}</small>
        </div>
      </div>

      <nav className="sidebar-nav">
        {NAV.map(({ to, label, icon: Icon, end }) => (
          <NavLink
            key={to}
            to={to}
            end={end}
            className={({ isActive }) =>
              `nav-link${isActive ? " nav-link-active" : ""}`
            }
          >
            <Icon size={18} strokeWidth={1.9} />
            <span>{label}</span>
          </NavLink>
        ))}

        {isAdmin && (
          <>
            <div className="nav-divider">
              <span>Administration</span>
            </div>
            <NavLink
              to="/admin"
              className={({ isActive }) =>
                `nav-link${isActive ? " nav-link-active" : ""}`
              }
            >
              <ShieldCheck size={18} strokeWidth={1.9} />
              <span>Admin Console</span>
            </NavLink>
            <NavLink
              to="/audit"
              className={({ isActive }) =>
                `nav-link${isActive ? " nav-link-active" : ""}`
              }
            >
              <ScrollText size={18} strokeWidth={1.9} />
              <span>Audit Logs</span>
            </NavLink>
          </>
        )}
      </nav>

      <footer className="sidebar-foot">
        <div className="sidebar-company-meta">
          {branding.gstin && <span>GSTIN: {branding.gstin}</span>}
          {branding.pan && <span>PAN: {branding.pan}</span>}
        </div>
      </footer>
    </aside>
  );
}
