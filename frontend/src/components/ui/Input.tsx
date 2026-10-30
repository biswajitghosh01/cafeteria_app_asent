import type { InputHTMLAttributes, SelectHTMLAttributes, ReactNode } from 'react';
interface FieldProps { label: string; hint?: string; error?: string; children: ReactNode }
export function Field({ label, hint, error, children }: FieldProps) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
      {hint && !error && <span className="field-hint">{hint}</span>}
      {error && <span className="field-error">{error}</span>}
    </label>
  );
}
interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string; hint?: string; error?: string;
}
export function Input({ label, hint, error, ...rest }: InputProps) {
  return (
    <Field label={label} hint={hint} error={error}>
      <input {...rest} className="input" />
    </Field>
  );
}
interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label: string; children: ReactNode;
}
export function Select({ label, children, ...rest }: SelectProps) {
  return <Field label={label}><select {...rest} className="input">{children}</select></Field>;
}
