/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_COMPANY_NAME: string;
  readonly VITE_COMPANY_ID: string;
  readonly VITE_TITLE_MODIFIER: string;
  readonly VITE_LOGO_URL: string;
  readonly VITE_BRAND_IMAGE_URL: string;
  readonly VITE_FAVICON_URL: string;
  readonly VITE_PRIMARY_COLOR: string;
  readonly VITE_ACCENT_COLOR: string;
  readonly VITE_GSTIN: string;
  readonly VITE_PAN: string;
  readonly VITE_ADDRESS: string;
  readonly VITE_CONTACT_EMAIL: string;
  readonly VITE_CONTACT_PHONE: string;
}
interface ImportMeta { readonly env: ImportMetaEnv; }
