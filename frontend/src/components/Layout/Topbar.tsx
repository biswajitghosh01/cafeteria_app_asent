import { LogOut, UserCircle2 } from 'lucide-react';
import { useAuth } from '../../context/AuthContext';
export default function Topbar() {
  const { user, logout } = useAuth();
  return (
    <header className="topbar">
      <div className="topbar-left" />
      <div className="topbar-right">
        <div className="user-chip">
          <UserCircle2 size={20} />
          <div className="user-chip-text">
            <strong>{user?.full_name}</strong>
            <small>{user?.role === 'admin' ? 'Administrator' : 'Counter'}</small>
          </div>
        </div>
        <button className="icon-btn" onClick={logout} title="Sign out"><LogOut size={18} /></button>
      </div>
    </header>
  );
}
