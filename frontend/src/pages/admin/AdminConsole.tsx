import { Activity, ScrollText, Server, Users } from 'lucide-react';
import { useState } from 'react';
import AppLogsTab from './AppLogsTab';
import HealthTab from './HealthTab';
import ServerLogsTab from './ServerLogsTab';
import UsersTab from './UsersTab';

type Tab = 'health' | 'users' | 'app-logs' | 'server-logs';
const TABS: { key: Tab; label: string; icon: typeof Activity }[] = [
  { key: 'health', label: 'System Health', icon: Activity },
  { key: 'users', label: 'User Management', icon: Users },
  { key: 'app-logs', label: 'Application Logs', icon: ScrollText },
  { key: 'server-logs', label: 'Server Logs', icon: Server },
];

export default function AdminConsole() {
  const [tab, setTab] = useState<Tab>('health');
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Admin Console</h1>
          <p className="page-subtitle">
            Monitor system health, manage users, and inspect application and server logs
          </p>
        </div>
      </div>
      <div className="tabs">
        {TABS.map(({ key, label, icon: Icon }) => (
          <button key={key} className={`tab${tab === key ? ' tab-active' : ''}`}
            onClick={() => setTab(key)}>
            <Icon size={16} /><span>{label}</span>
          </button>
        ))}
      </div>
      <div className="tab-panel">
        {tab === 'health' && <HealthTab />}
        {tab === 'users' && <UsersTab />}
        {tab === 'app-logs' && <AppLogsTab />}
        {tab === 'server-logs' && <ServerLogsTab />}
      </div>
    </>
  );
}
