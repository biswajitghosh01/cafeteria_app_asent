import type { ReactNode } from 'react';
interface Props {
  label: string; value: string;
  delta?: { value: string; positive: boolean };
  hint?: string; icon?: ReactNode;
  tone?: 'neutral' | 'success' | 'danger' | 'warning';
}
export default function StatTile({ label, value, delta, hint, icon, tone = 'neutral' }: Props) {
  return (
    <div className={`stat-tile stat-${tone}`}>
      <div className="stat-head">
        <span className="stat-label">{label}</span>
        {icon && <span className="stat-icon">{icon}</span>}
      </div>
      <div className="stat-value mono">{value}</div>
      {(delta || hint) && (
        <div className="stat-foot">
          {delta && <span className={delta.positive ? 'delta up' : 'delta down'}>
            {delta.positive ? '▲' : '▼'} {delta.value}</span>}
          {hint && <span className="stat-hint">{hint}</span>}
        </div>
      )}
    </div>
  );
}
