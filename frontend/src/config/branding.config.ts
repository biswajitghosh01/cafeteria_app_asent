export interface Branding {
  companyId: string;
  companyName: string;
  titleModifier: string;
  logoUrl: string;
  brandImageUrl: string;
  faviconUrl: string;
  primaryColor: string;
  accentColor: string;
  gstin: string;
  pan: string;
  address: string;
  contactEmail: string;
  contactPhone: string;
}

const env = import.meta.env;

export const branding: Branding = {
  companyId: env.VITE_COMPANY_ID || "as-enterprises",
  companyName: env.VITE_COMPANY_NAME || "AS Enterprises",
  titleModifier: env.VITE_TITLE_MODIFIER || "Operations Console",
  logoUrl: env.VITE_LOGO_URL || "/assets/as-enterprises-logo.png",
  brandImageUrl: env.VITE_BRAND_IMAGE_URL || "/assets/as-enterprises-logo.png",
  faviconUrl: env.VITE_FAVICON_URL || "/favicon.svg",
  primaryColor: env.VITE_PRIMARY_COLOR || "#0f2d52",
  accentColor: env.VITE_ACCENT_COLOR || "#c9a227",
  gstin: env.VITE_GSTIN || "",
  pan: env.VITE_PAN || "",
  address: env.VITE_ADDRESS || "",
  contactEmail: env.VITE_CONTACT_EMAIL || "",
  contactPhone: env.VITE_CONTACT_PHONE || "",
};

export function applyBrandingToDocument(): void {
  document.title = `${branding.companyName} · ${branding.titleModifier}`;
  let link = document.querySelector<HTMLLinkElement>('link[rel="icon"]');
  if (!link) {
    link = document.createElement("link");
    link.rel = "icon";
    document.head.appendChild(link);
  }
  link.href = branding.faviconUrl;
  const root = document.documentElement;
  root.style.setProperty("--color-primary-500", branding.primaryColor);
  root.style.setProperty("--color-success", branding.accentColor);
}
