import { FormEvent, useState } from "react";
import { Navigate } from "react-router-dom";
import Button from "../components/ui/Button";
import { branding } from "../config/branding.config";
import { useAuth } from "../context/AuthContext";
import { apiErrorMessage } from "../lib/api";

export default function Login() {
  const { user, login } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  if (user) return <Navigate to="/" replace />;

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await login(email.trim(), password);
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="login-screen">
      <div className="login-brand">
        <div className="login-brand-inner">
          <img
            className="login-brand-logo"
            src={branding.logoUrl}
            alt={branding.companyName}
          />
          <h2>{branding.companyName}</h2>
          <p>{branding.titleModifier}</p>
        </div>
      </div>
      <div className="login-form-wrap">
        <div className="login-card">
          <img
            className="login-logo"
            src={branding.logoUrl}
            alt={branding.companyName}
          />
          <h1 className="login-title">Welcome back</h1>
          <p className="login-subtitle">
            Sign in to {branding.companyName} {branding.titleModifier}
          </p>
          <form onSubmit={onSubmit}>
            {error && <div className="login-error">{error}</div>}
            <label className="field">
              <span className="field-label">Email</span>
              <input
                type="email"
                autoComplete="username"
                required
                className="input"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </label>
            <label className="field">
              <span className="field-label">Password</span>
              <input
                type="password"
                autoComplete="current-password"
                required
                className="input"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </label>
            <Button type="submit" loading={submitting}>
              Sign in
            </Button>
          </form>
          <div className="login-footnote">
            © {new Date().getFullYear()} {branding.companyName}
            {branding.contactEmail && <> · {branding.contactEmail}</>}
          </div>
        </div>
      </div>
    </div>
  );
}
