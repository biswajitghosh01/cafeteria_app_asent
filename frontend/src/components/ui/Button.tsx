import type { ButtonHTMLAttributes, ReactNode } from 'react';
type Variant = 'primary' | 'secondary' | 'ghost' | 'danger';
type Size = 'sm' | 'md';
interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant; size?: Size; loading?: boolean; icon?: ReactNode;
}
export default function Button({ variant = 'primary', size = 'md', loading = false,
  icon, children, className = '', disabled, ...rest }: Props) {
  return (
    <button {...rest} disabled={disabled || loading}
      className={`btn btn-${variant} btn-${size} ${className}`.trim()}>
      {loading ? <span className="spinner-sm" /> : icon}
      {children}
    </button>
  );
}
