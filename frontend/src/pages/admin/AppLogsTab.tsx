import { Filter } from 'lucide-react';
import { useEffect, useState } from 'react';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import Table, { type Column } from '../../components/ui/Table';
import { api, apiErrorMessage } from '../../lib/api';

interface AuditEntry {
  id: number; user_email: string | null; action: string; entity: string;
  entity_id: string | null; details: string | null;
  ip_address: string | null; created_at: string;
}
const TONE: Record<string, 'success' | 'danger' | 'warning' | 'info' | 'neutral'> = {
  login: 'success', login_failed: 'danger', logout: 'neutral',
  create: 'success', update: 'info', delete: 'danger', reset_password: 'warning',
};

export default function AppLogsTab() {
  const [rows, setRows] = useState<AuditEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [action, setAction] = useState('');
  const [entity, setEntity] = useState('');
  const [userEmail, setUserEmail] = useState('');
  const load = async () => {
    setLoading(true); setError(null);
    try {
      const params: Record<string, string> = {};
      if (action) params.action = action;
      if (entity) params.entity = entity;
      if (userEmail) params.user_email = userEmail;
      const { data } = await api.get<AuditEntry[]>('/admin/logs/app', { params });
      setRows(data);
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); /* eslint-disable-next-line */ }, []);
  const columns: Column<AuditEntry>[] = [
    { key: 'ts', header: 'Timestamp',
      render: (r) => <span className="mono" style={{ fontSize: 12 }}>{new Date(r.created_at).toLocaleString('en-IN')}</span> },
    { key: 'user', header: 'User', render: (r) => r.user_email ?? '—' },
    { key: 'action', header: 'Action',
      render: (r) => <Badge tone={TONE[r.action] ?? 'neutral'}>{r.action}</Badge> },
    { key: 'entity', header: 'Entity', render: (r) => r.entity },
    { key: 'id', header: 'Entity ID',
      render: (r) => r.entity_id ? <span className="mono">{r.entity_id}</span> : '—' },
    { key: 'details', header: 'Details', render: (r) => r.details ?? '—' },
    { key: 'ip', header: 'IP',
      render: (r) => <span className="mono" style={{ fontSize: 12 }}>{r.ip_address ?? '—'}</span> },
  ];
  return (
    <>
      <Card title="Filters" padded>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12 }}>
          <label className="field">
            <span className="field-label">Action</span>
            <input className="input" placeholder="login, create, delete…"
              value={action} onChange={(e) => setAction(e.target.value)} />
          </label>
          <label className="field">
            <span className="field-label">Entity</span>
            <input className="input" placeholder="sale, user, purchase…"
              value={entity} onChange={(e) => setEntity(e.target.value)} />
          </label>
          <label className="field">
            <span className="field-label">User Email</span>
            <input className="input" placeholder="partial match"
              value={userEmail} onChange={(e) => setUserEmail(e.target.value)} />
          </label>
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8 }}>
            <Button onClick={load} loading={loading} icon={<Filter size={15} />}>Apply</Button>
            <Button variant="secondary"
              onClick={() => { setAction(''); setEntity(''); setUserEmail(''); }}>Clear</Button>
          </div>
        </div>
      </Card>
      {error && <div className="login-error" style={{ margin: '16px 0' }}>{error}</div>}
      <div style={{ marginTop: 20 }}>
        <Card title="Application Audit Log" subtitle={`${rows.length} entries shown`} padded={false}>
          <Table columns={columns} rows={rows} empty="No log entries match." />
        </Card>
      </div>
    </>
  );
}
