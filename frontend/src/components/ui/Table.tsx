import type { ReactNode } from 'react';
export interface Column<T> {
  key: string; header: string; align?: 'left' | 'right' | 'center';
  render: (row: T) => ReactNode;
}
interface Props<T> { columns: Column<T>[]; rows: T[]; empty?: string }
export default function Table<T>({ columns, rows, empty = 'No records yet.' }: Props<T>) {
  if (rows.length === 0) return <div className="table-empty">{empty}</div>;
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead><tr>{columns.map((c) => (
          <th key={c.key} style={{ textAlign: c.align ?? 'left' }}>{c.header}</th>
        ))}</tr></thead>
        <tbody>{rows.map((row, i) => (
          <tr key={i}>{columns.map((c) => (
            <td key={c.key} style={{ textAlign: c.align ?? 'left' }}>{c.render(row)}</td>
          ))}</tr>
        ))}</tbody>
      </table>
    </div>
  );
}
