const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR',
  maximumFractionDigits: 2, minimumFractionDigits: 2 });

export const formatINR = (v: number | string): string => inr.format(Number(v ?? 0));
export const formatNumber = (v: number | string): string =>
  new Intl.NumberFormat('en-IN').format(Number(v ?? 0));
export const formatDate = (v: string | Date): string => {
  const d = typeof v === 'string' ? new Date(v) : v;
  return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
};
export const todayISO = (): string => new Date().toISOString().slice(0, 10);
export const firstOfMonthISO = (): string => {
  const d = new Date(); d.setDate(1);
  return d.toISOString().slice(0, 10);
};
