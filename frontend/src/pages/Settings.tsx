import { useEffect, useState } from 'react';
import Badge from '../components/ui/Badge';
import Card from '../components/ui/Card';
import { branding } from '../config/branding.config';
import { api } from '../lib/api';

interface ServerSettings { app_name: string; environment: string; database: string }

export default function Settings() {
  const [srv, setSrv] = useState<ServerSettings | null>(null);
  useEffect(() => {
    api.get<ServerSettings>('/settings/server').then(({ data }) => setSrv(data)).catch(() => {});
  }, []);
  return (
    <>
      <div className="page-header">
        <div>
          <h1 className="page-title">Settings</h1>
          <p className="page-subtitle">Branding is embedded at build time</p>
        </div>
      </div>
      <Card title="Company Branding" subtitle="From VITE_* environment variables" padded>
        <div className="kv"><span>Company Name</span><code>{branding.companyName}</code></div>
        <div className="kv"><span>Company ID</span><code>{branding.companyId}</code></div>
        <div className="kv"><span>Title Modifier</span><code>{branding.titleModifier}</code></div>
        <div className="kv"><span>GSTIN</span><code>{branding.gstin || '—'}</code></div>
        <div className="kv"><span>PAN</span><code>{branding.pan || '—'}</code></div>
        <div className="kv"><span>Contact Email</span><code>{branding.contactEmail || '—'}</code></div>
        <div className="kv"><span>Contact Phone</span><code>{branding.contactPhone || '—'}</code></div>
      </Card>
      <div style={{ marginTop: 20 }}>
        <Card title="Server" subtitle="From /api/settings/server" padded>
          {srv ? (
            <>
              <div className="kv"><span>App Name</span><code>{srv.app_name}</code></div>
              <div className="kv"><span>Environment</span>
                <Badge tone={srv.environment === 'production' ? 'success' : 'warning'}>
                  {srv.environment}
                </Badge>
              </div>
              <div className="kv"><span>Database</span>
                <Badge tone={srv.database === 'sqlite' ? 'warning' : 'success'}>
                  {srv.database}
                </Badge>
              </div>
            </>
          ) : <div className="table-empty">Loading…</div>}
        </Card>
      </div>
    </>
  );
}
