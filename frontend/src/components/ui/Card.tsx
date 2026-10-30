import type { ReactNode } from 'react';
interface Props { title?: string; subtitle?: string; actions?: ReactNode; children: ReactNode; padded?: boolean }
export default function Card({ title, subtitle, actions, children, padded = true }: Props) {
  return (
    <section className="card">
      {(title || actions) && (
        <header className="card-header">
          <div>
            {title && <h3 className="card-title">{title}</h3>}
            {subtitle && <p className="card-subtitle">{subtitle}</p>}
          </div>
          {actions && <div className="card-actions">{actions}</div>}
        </header>
      )}
      <div className={padded ? 'card-body' : ''}>{children}</div>
    </section>
  );
}
