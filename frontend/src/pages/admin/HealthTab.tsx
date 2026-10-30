import { Activity, AlertTriangle, CheckCircle2, Clock, Cpu, Database, HardDrive, MemoryStick, Users } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import StatTile from '../../components/ui/StatTile';
import { api, apiErrorMessage } from '../../lib/api';

interface Health {
  status: string; environment: string; version: string; database: string;
  uptime_seconds: number; db_ok: boolean; db_latency_ms: number;
  cpu_percent: number; memory_percent: number; disk_percent: number;
  log_file: string; log_size_bytes: number;
  request_count: number; error_count: number;
  user_count: number; active_session_count: number;
}
const uptime = (s: number) => {
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
};
const bytes = (b: number) =>
  b < 1024 ? `${b} B`
  : b < 1024 * 1024 ? `${(b / 1024).toFixed(1)} KB`
  : `${(b / (1024 * 1024)).toFixed(2)} MB`;

export default function HealthTab() {
  const [data, setData] = useState<Health | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(true);

  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try { const { data } = await api.get<Health>('/admin/health'); setData(data); }
    catch (err) { setError(apiErrorMessage(err)); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => {
    load();
    if (!autoRefresh) return;
    const t = setInterval(load, 10000);
    return () => clearInterval(t);
  }, [load, autoRefresh]);

  const errorRate = data && data.request_count > 0
    ? ((data.error_count / data.request_count) * 100).toFixed(2) : '0.00';

  return (
    <>
      <div className="page-actions" style={{ marginBottom: 16, justifyContent: 'flex-end' }}>
        <label className="checkbox-line">
          <input type="checkbox" checked={autoRefresh}
            onChange={(e) => setAutoRefresh(e.target.checked)} />
          Auto-refresh every 10s
        </label>
        <Button variant="secondary" onClick={load} loading={loading}>Refresh</Button>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {data && (<>
        <Card padded>
          <div className="status-banner">
            {data.status === 'ok' ? (<>
              <CheckCircle2 size={22} color="var(--color-success)" />
              <div>
                <strong>All systems operational</strong>
                <p>Environment <code>{data.environment}</code> · Version <code>{data.version}</code> · Database <code>{data.database}</code></p>
              </div>
            </>) : (<>
              <AlertTriangle size={22} color="var(--color-danger)" />
              <div><strong>Degraded</strong><p>The database is unresponsive.</p></div>
            </>)}
          </div>
        </Card>
        <div className="grid-stats" style={{ marginTop: 20 }}>
          <StatTile label="Uptime" value={uptime(data.uptime_seconds)} icon={<Clock size={18} />} />
          <StatTile label="Database" value={data.db_ok ? 'Healthy' : 'Down'}
            tone={data.db_ok ? 'success' : 'danger'}
            icon={<Database size={18} />} hint={`${data.db_latency_ms.toFixed(1)} ms`} />
          <StatTile label="CPU" value={`${data.cpu_percent.toFixed(1)}%`}
            tone={data.cpu_percent > 85 ? 'danger' : 'neutral'} icon={<Cpu size={18} />} />
          <StatTile label="Memory" value={`${data.memory_percent.toFixed(1)}%`}
            tone={data.memory_percent > 85 ? 'danger' : 'neutral'} icon={<MemoryStick size={18} />} />
          <StatTile label="Disk" value={`${data.disk_percent.toFixed(1)}%`}
            tone={data.disk_percent > 85 ? 'danger' : 'neutral'} icon={<HardDrive size={18} />} />
          <StatTile label="Users" value={String(data.user_count)}
            hint={`${data.active_session_count} active`} icon={<Users size={18} />} />
          <StatTile label="Requests" value={data.request_count.toLocaleString()} icon={<Activity size={18} />} />
          <StatTile label="Errors" value={String(data.error_count)}
            tone={data.error_count > 0 ? 'danger' : 'neutral'} hint={`${errorRate}% rate`} />
        </div>
        <Card title="Log File" subtitle="Rotating file — readable from Server Logs tab" padded>
          <div className="kv"><span>Path</span><code>{data.log_file}</code></div>
          <div className="kv"><span>Size</span><code>{bytes(data.log_size_bytes)}</code></div>
          <div className="kv"><span>Environment</span>
            <Badge tone={data.environment === 'production' ? 'success' : 'warning'}>
              {data.environment}
            </Badge>
          </div>
          <div className="kv"><span>Database</span>
            <Badge tone={data.database === 'sqlite' ? 'warning' : 'success'}>
              {data.database}
            </Badge>
          </div>
        </Card>
      </>)}
    </>
  );
}
