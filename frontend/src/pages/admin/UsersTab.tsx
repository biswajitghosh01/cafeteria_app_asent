import { FormEvent, useEffect, useState } from 'react';
import { KeyRound, Plus, ShieldCheck, Trash2, UserCog } from 'lucide-react';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import { Input, Select } from '../../components/ui/Input';
import Table, { type Column } from '../../components/ui/Table';
import { useAuth } from '../../context/AuthContext';
import { api, apiErrorMessage } from '../../lib/api';
import { formatDate } from '../../lib/format';

type Role = 'admin' | 'counter';
interface AdminUser {
  id: number; email: string; full_name: string; role: Role; is_active: boolean;
  last_login_at: string | null; created_at: string | null;
}
const emptyCreate = { email: '', full_name: '', password: '', role: 'counter' as Role };

export default function UsersTab() {
  const { user: me } = useAuth();
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState({ ...emptyCreate });
  const [editing, setEditing] = useState<AdminUser | null>(null);
  const [resetting, setResetting] = useState<AdminUser | null>(null);
  const [newPassword, setNewPassword] = useState('');

  const load = async () => {
    try { const { data } = await api.get<AdminUser[]>('/admin/users'); setUsers(data); }
    catch (err) { setError(apiErrorMessage(err)); }
  };
  useEffect(() => { load(); }, []);

  const set = (k: keyof typeof form, v: string) => setForm((f) => ({ ...f, [k]: v }));
  const onCreate = async (e: FormEvent) => {
    e.preventDefault(); setError(null); setCreating(true);
    try { await api.post('/admin/users', form); setForm({ ...emptyCreate }); setShowCreate(false); await load(); }
    catch (err) { setError(apiErrorMessage(err)); }
    finally { setCreating(false); }
  };
  const onSaveEdit = async (e: FormEvent) => {
    e.preventDefault(); if (!editing) return;
    try {
      await api.put(`/admin/users/${editing.id}`, {
        full_name: editing.full_name, role: editing.role, is_active: editing.is_active,
      });
      setEditing(null); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
  };
  const onResetPassword = async (e: FormEvent) => {
    e.preventDefault(); if (!resetting) return;
    try {
      await api.post(`/admin/users/${resetting.id}/reset-password`, { new_password: newPassword });
      setResetting(null); setNewPassword(''); await load();
    } catch (err) { setError(apiErrorMessage(err)); }
  };
  const onDelete = async (u: AdminUser) => {
    if (!confirm(`Delete user ${u.email}? This cannot be undone.`)) return;
    try { await api.delete(`/admin/users/${u.id}`); await load(); }
    catch (err) { setError(apiErrorMessage(err)); }
  };
  const columns: Column<AdminUser>[] = [
    { key: 'name', header: 'Name',
      render: (u) => (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <strong>{u.full_name}</strong>
          {u.id === me?.id && <Badge tone="info">You</Badge>}
        </div>
      ) },
    { key: 'email', header: 'Email', render: (u) => u.email },
    { key: 'role', header: 'Role',
      render: (u) => u.role === 'admin'
        ? <Badge tone="info"><ShieldCheck size={12} /> Admin</Badge>
        : <Badge>Counter</Badge> },
    { key: 'status', header: 'Status',
      render: (u) => u.is_active ? <Badge tone="success">Active</Badge> : <Badge tone="danger">Disabled</Badge> },
    { key: 'last', header: 'Last Login',
      render: (u) => u.last_login_at ? formatDate(u.last_login_at) : '—' },
    { key: 'created', header: 'Created',
      render: (u) => u.created_at ? formatDate(u.created_at) : '—' },
    { key: 'actions', header: '', align: 'right',
      render: (u) => (
        <div style={{ display: 'flex', gap: 4, justifyContent: 'flex-end' }}>
          <button className="icon-btn" title="Edit user" onClick={() => setEditing({ ...u })}>
            <UserCog size={15} />
          </button>
          <button className="icon-btn" title="Reset password"
            onClick={() => { setResetting(u); setNewPassword(''); }}>
            <KeyRound size={15} />
          </button>
          <button className="icon-btn" title="Delete user"
            onClick={() => onDelete(u)} disabled={u.id === me?.id}>
            <Trash2 size={15} />
          </button>
        </div>
      ) },
  ];
  return (
    <>
      <div className="page-actions" style={{ justifyContent: 'flex-end', marginBottom: 16 }}>
        <Button variant={showCreate ? 'secondary' : 'primary'} icon={<Plus size={15} />}
          onClick={() => setShowCreate((s) => !s)}>
          {showCreate ? 'Cancel' : 'New User'}
        </Button>
      </div>
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      {showCreate && (
        <Card title="Create User" padded>
          <form onSubmit={onCreate}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 14 }}>
              <Input label="Full Name" value={form.full_name} onChange={(e) => set('full_name', e.target.value)} required />
              <Input label="Email" type="email" value={form.email} onChange={(e) => set('email', e.target.value)} required />
              <Input label="Password" type="password" value={form.password}
                onChange={(e) => set('password', e.target.value)} required hint="Minimum 8 characters" />
              <Select label="Role" value={form.role}
                onChange={(e) => set('role', e.target.value as Role)}>
                <option value="counter">Counter</option>
                <option value="admin">Administrator</option>
              </Select>
            </div>
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setShowCreate(false)}>Cancel</Button>
              <Button type="submit" loading={creating}>Create User</Button>
            </div>
          </form>
        </Card>
      )}
      {editing && (
        <Card title={`Edit User: ${editing.email}`} padded>
          <form onSubmit={onSaveEdit}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 14 }}>
              <Input label="Full Name" value={editing.full_name}
                onChange={(e) => setEditing({ ...editing, full_name: e.target.value })} />
              <Select label="Role" value={editing.role}
                onChange={(e) => setEditing({ ...editing, role: e.target.value as Role })}>
                <option value="counter">Counter</option>
                <option value="admin">Administrator</option>
              </Select>
              <Select label="Status" value={editing.is_active ? 'active' : 'disabled'}
                onChange={(e) => setEditing({ ...editing, is_active: e.target.value === 'active' })}>
                <option value="active">Active</option>
                <option value="disabled">Disabled</option>
              </Select>
            </div>
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setEditing(null)}>Cancel</Button>
              <Button type="submit">Save Changes</Button>
            </div>
          </form>
        </Card>
      )}
      {resetting && (
        <Card title={`Reset Password: ${resetting.email}`} padded>
          <form onSubmit={onResetPassword}>
            <Input label="New Password" type="password" value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)} required hint="Minimum 8 characters" />
            <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <Button variant="secondary" type="button" onClick={() => setResetting(null)}>Cancel</Button>
              <Button type="submit">Reset Password</Button>
            </div>
          </form>
        </Card>
      )}
      <div style={{ marginTop: showCreate || editing || resetting ? 20 : 0 }}>
        <Card title="Users"
          subtitle={`${users.length} users · ${users.filter((u) => u.is_active).length} active`}
          padded={false}>
          <Table columns={columns} rows={users} empty="No users found." />
        </Card>
      </div>
    </>
  );
}
