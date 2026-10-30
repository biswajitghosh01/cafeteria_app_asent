import { Download, RefreshCw, Search } from 'lucide-react';
import { useEffect, useState } from 'react';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import { api, apiErrorMessage } from '../../lib/api';

interface LogEntry { timestamp: string; level: string; logger: string; message: string }
interface LogResponse {
  entries: LogEntry[]; total_matched: number;
  file_size_bytes: number; lines_scanned: number;
}
const TONE: Record<string, 'success' | 'danger' | 'warning' | 'info' | 'neutral'> = {
  DEBUG: 'neutral', INFO: 'info', WARNING: 'warning', ERROR: 'danger', CRITICAL: 'danger',
};

export default function ServerLogsTab() {
  const [data, setData] = useState<LogResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [level, setLevel] = useState('');
  const [search, setSearch] = useState('');
  const [autoRefresh, setAutoRefresh] = useState(true);
  const load = async () => {
    setLoading(true); setError(null);
    try {
      const params: Record<string, string | number> = { limit: 500 };
      if (level) params.level = level;
      if (search) params.search = search;
      const { data } = await api.get<LogResponse>('/admin/logs/server', { params });
      setData(data);
    } catch (err) { setError(apiErrorMessage(err)); }
    finally { setLoading(false); }
  };
  useEffect(() => { load(); /* eslint-disable-next-line */ }, [level]);
  useEffect(() => {
    if (!autoRefresh) return;
    const t = setInterval(load, 10000);
    return () => clearInterval(t);
    /* eslint-disable-next-line */
  }, [autoRefresh, level, search]);
  const download = async () => {
    const res = await api.get('/admin/logs/server/download', { responseType: 'blob' });
    const url = URL.createObjectURL(res.data);
    const a = document.createElement('a');
    a.href = url;
    a.download = `food-court-api-${new Date().toISOString().slice(0, 10)}.log`;
    a.click();
    URL.revokeObjectURL(url);
  };
  return (
    <>
      <Card title="Filters" padded>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12 }}>
          <label className="field">
            <span className="field-label">Level</span>
            <select className="input" value={level} onChange={(e) => setLevel(e.target.value)}>
              <option value="">All levels</option>
              <option value="DEBUG">DEBUG</option>
              <option value="INFO">INFO</option>
              <option value="WARNING">WARNING</option>
              <option value="ERROR">ERROR</option>
              <option value="CRITICAL">CRITICAL</option>
            </select>
          </label>
          <label className="field">
            <span className="field-label">Search</span>
            <input className="input" placeholder="substring match…"
              value={search} onChange={(e) => setSearch(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && load()} />
          </label>
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8 }}>
            <Button onClick={load} loading={loading} icon={<Search size={15} />}>Apply</Button>
            <Button variant="secondary" onClick={download} icon={<Download size={15} />}>Download</Button>
          </div>
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 12, justifyContent: 'flex-end' }}>
            <label className="checkbox-line">
              <input type="checkbox" checked={autoRefresh}
                onChange={(e) => setAutoRefresh(e.target.checked)} /> Auto-refresh
            </label>
            <button className="icon-btn" onClick={load} title="Refresh"><RefreshCw size={16} /></button>
          </div>
        </div>
      </Card>
      {error && <div className="login-error" style={{ margin: '16px 0' }}>{error}</div>}
      <div style={{ marginTop: 20 }}>
        <Card title="Server Log"
          subtitle={data
            ? `${data.total_matched} matched of ${data.lines_scanned} lines · ${(data.file_size_bytes / 1024).toFixed(1)} KB`
            : 'Loading…'}
          padded={false}>
          <div className="log-viewer">
            {!data || data.entries.length === 0 ? (
              <div className="table-empty">No log entries match the filter.</div>
            ) : (
              data.entries.map((entry, i) => (
                <div key={i} className={`log-line log-${entry.level.toLowerCase()}`}>
                  <span className="log-ts">{entry.timestamp}</span>
                  <Badge tone={TONE[entry.level] ?? 'neutral'}>{entry.level}</Badge>
                  <span className="log-logger">{entry.logger}</span>
                  <span className="log-msg">{entry.message}</span>
                </div>
              ))
            )}
          </div>
        </Card>
      </div>
    </>
  );
}
