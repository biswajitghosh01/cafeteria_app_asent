import { createContext, useCallback, useContext, useEffect, useMemo, useState,
  type ReactNode } from 'react';
import { api, clearToken, getToken, setToken } from '../lib/api';

export type UserRole = 'admin' | 'counter';
export interface CurrentUser { id: number; email: string; full_name: string; role: UserRole; is_active: boolean }
interface AuthContextValue {
  user: CurrentUser | null; loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
}
const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<CurrentUser | null>(null);
  const [loading, setLoading] = useState(true);

  const loadMe = useCallback(async () => {
    if (!getToken()) { setUser(null); setLoading(false); return; }
    try { const { data } = await api.get<CurrentUser>('/auth/me'); setUser(data); }
    catch { clearToken(); setUser(null); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { loadMe(); }, [loadMe]);

  const login = useCallback(async (email: string, password: string) => {
    const body = new URLSearchParams();
    body.append('username', email); body.append('password', password);
    const { data } = await api.post<{ access_token: string }>(
      '/auth/login', body,
      { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } },
    );
    setToken(data.access_token);
    const me = await api.get<CurrentUser>('/auth/me');
    setUser(me.data);
  }, []);

  const logout = useCallback(async () => {
    try { await api.post('/auth/logout'); } catch { /* ignore */ }
    clearToken(); setUser(null);
  }, []);

  const value = useMemo(() => ({ user, loading, login, logout }),
    [user, loading, login, logout]);
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}
