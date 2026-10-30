import { useEffect, useState } from 'react';
import Badge from '../components/ui/Badge';
import Card from '../components/ui/Card';
import Table, { type Column } from '../components/ui/Table';
import { api, apiErrorMessage } from '../lib/api';

interface AuditEntry {
  id: number; user_email: string | null; action: string; entity: string;
  entity_id: string | null; details: string | null;
  ip_address: string | null; created_at: string;
}

export default function AuditLogs() {
  const [rows, setRows] = useState<AuditEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    api.get<AuditEntry[]>('/audit').then(({ data }) => setRows(data))
      .catch((err) => setError(apiErrorMessage(err)));
  }, []);
  const columns: Column<AuditEntry>[] = [
    { key: 'ts', header: 'Timestamp',
      render: (r) => <span className="mono" style={{ fontSize: 12 }}>{new Date(r.created_at).toLocaleString('en-IN')}</span> },
    { key: 'user', header: 'User', render: (r) => r.user_email ?? '—' },
    { key: 'action', header: 'Action', render: (r) => <Badge>{r.action}</Badge> },
    { key: 'entity', header: 'Entity', render: (r) => r.entity },
    { key: 'id', header: 'Entity ID',
      render: (r) => r.entity_id ? <span className="mono">{r.entity_id}</span> : '—' },
    { key: 'details', header: 'Details', render: (r) => r.details ?? '—' },
    { key: 'ip', header: 'IP',
      render: (r) => <span className="mono" style={{ fontSize: 12 }}>{r.ip_address ?? '—'}</span> },
  ];
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Audit Logs</h1>
          <p className="page-subtitle">Full audit trail is available in Admin Console → Application Logs</p>
        </div>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      <Card title="Recent Activity" padded={false}>
        <Table columns={columns} rows={rows} empty="No audit entries." />
      </Card>
    </>
  );
}
