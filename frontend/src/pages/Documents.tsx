import { Download, FileText, Plus, Trash2, Upload } from "lucide-react";
import { FormEvent, useEffect, useRef, useState } from "react";
import Badge from "../components/ui/Badge";
import Button from "../components/ui/Button";
import Card from "../components/ui/Card";
import { Input, Select } from "../components/ui/Input";
import Table, { type Column } from "../components/ui/Table";
import { api, apiErrorMessage } from "../lib/api";
import { formatDate } from "../lib/format";

interface Version {
  id: number;
  version: number;
  original_filename: string;
  content_type: string | null;
  file_size: number;
  notes: string | null;
  uploaded_by: string | null;
  uploaded_at: string;
}

interface Doc {
  id: number;
  title: string;
  category: string;
  description: string | null;
  current_version: number;
  is_active: boolean;
  created_by: string | null;
  created_at: string;
  versions: Version[];
}

const CATEGORIES = [
  "general",
  "license",
  "contract",
  "invoice",
  "insurance",
  "compliance",
];

function humanSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

export default function Documents() {
  const [docs, setDocs] = useState<Doc[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<number | null>(null);

  // Upload panel state
  const [showUpload, setShowUpload] = useState(false);
  const [uploadForm, setUploadForm] = useState({
    title: "",
    category: "general",
    description: "",
    notes: "",
  });
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const uploadFileRef = useRef<HTMLInputElement>(null);

  // Row-level "add version" state
  const [versioningFor, setVersioningFor] = useState<number | null>(null);
  const versionFileRef = useRef<HTMLInputElement>(null);

  const load = async () => {
    try {
      const { data } = await api.get<Doc[]>("/documents");
      setDocs(data);
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  useEffect(() => {
    load();
  }, []);

  // -------------------------------------------------------------------------
  // One-step upload: create document metadata + upload first file
  // -------------------------------------------------------------------------
  const onUploadFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0] ?? null;
    setUploadFile(f);
    // Auto-fill title from filename if empty
    if (f && !uploadForm.title) {
      const base = f.name.replace(/\.[^.]+$/, "");
      setUploadForm((u) => ({ ...u, title: base }));
    }
  };

  const submitUpload = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setSuccess(null);

    if (!uploadFile) {
      setError("Please choose a file to upload");
      return;
    }
    if (!uploadForm.title.trim()) {
      setError("Please enter a title");
      return;
    }

    setUploading(true);
    try {
      // Step 1: create the document metadata
      const { data: doc } = await api.post<Doc>("/documents", {
        title: uploadForm.title.trim(),
        category: uploadForm.category,
        description: uploadForm.description || null,
      });

      // Step 2: upload the file as version 1
      const form = new FormData();
      form.append("file", uploadFile);
      if (uploadForm.notes) form.append("notes", uploadForm.notes);

      // Do NOT set Content-Type manually — axios adds it with boundary
      await api.post(`/documents/${doc.id}/versions`, form);

      setSuccess(`Uploaded "${doc.title}" successfully`);
      setUploadForm({
        title: "",
        category: "general",
        description: "",
        notes: "",
      });
      setUploadFile(null);
      if (uploadFileRef.current) uploadFileRef.current.value = "";
      setShowUpload(false);
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setUploading(false);
    }
  };

  // -------------------------------------------------------------------------
  // Add a new version to an existing document
  // -------------------------------------------------------------------------
  const triggerVersionUpload = (docId: number) => {
    setVersioningFor(docId);
    // Trigger file picker after state is set
    requestAnimationFrame(() => versionFileRef.current?.click());
  };

  const onVersionFileSelected = async (
    e: React.ChangeEvent<HTMLInputElement>,
  ) => {
    const file = e.target.files?.[0];
    const docId = versioningFor;
    e.target.value = "";
    if (!file || !docId) return;

    const notes = window.prompt("Version notes (optional):") || "";

    const form = new FormData();
    form.append("file", file);
    if (notes) form.append("notes", notes);

    setError(null);
    setSuccess(null);
    try {
      // Do NOT set Content-Type manually
      await api.post(`/documents/${docId}/versions`, form);
      setSuccess(
        `Uploaded new version of "${docs.find((d) => d.id === docId)?.title}"`,
      );
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setVersioningFor(null);
    }
  };

  // -------------------------------------------------------------------------
  // Download and delete
  // -------------------------------------------------------------------------
  const downloadVersion = async (versionId: number, filename: string) => {
    try {
      const res = await api.get(`/documents/versions/${versionId}/download`, {
        responseType: "blob",
      });
      const url = URL.createObjectURL(res.data);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      a.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  const deleteDoc = async (doc: Doc) => {
    if (
      !confirm(
        `Delete "${doc.title}" and all ${doc.versions.length} version(s)? This cannot be undone.`,
      )
    )
      return;
    try {
      await api.delete(`/documents/${doc.id}`);
      await load();
    } catch (err) {
      setError(apiErrorMessage(err));
    }
  };

  const columns: Column<Doc>[] = [
    {
      key: "title",
      header: "Title",
      render: (r) => <strong>{r.title}</strong>,
    },
    {
      key: "category",
      header: "Category",
      render: (r) => <Badge>{r.category}</Badge>,
    },
    {
      key: "version",
      header: "Version",
      render: (r) => <span className="mono">v{r.current_version}</span>,
    },
    {
      key: "files",
      header: "Files",
      render: (r) =>
        `${r.versions.length} version${r.versions.length !== 1 ? "s" : ""}`,
    },
    {
      key: "updated",
      header: "Last Updated",
      render: (r) =>
        r.versions[0]
          ? formatDate(r.versions[0].uploaded_at)
          : formatDate(r.created_at),
    },
    {
      key: "actions",
      header: "",
      align: "right",
      render: (r) => (
        <div style={{ display: "flex", gap: 4, justifyContent: "flex-end" }}>
          <button
            className="icon-btn"
            title="Upload new version"
            onClick={() => triggerVersionUpload(r.id)}
          >
            <Upload size={15} />
          </button>
          <button
            className="icon-btn"
            title={expanded === r.id ? "Hide versions" : "Show versions"}
            onClick={() => setExpanded(expanded === r.id ? null : r.id)}
          >
            <FileText size={15} />
          </button>
          <button
            className="icon-btn"
            title="Delete document"
            onClick={() => deleteDoc(r)}
          >
            <Trash2 size={15} />
          </button>
        </div>
      ),
    },
  ];

  const expandedDoc =
    expanded !== null ? docs.find((d) => d.id === expanded) : null;

  return (
    <>
      {/* Hidden file inputs */}
      <input
        ref={uploadFileRef}
        type="file"
        style={{ display: "none" }}
        onChange={onUploadFileChange}
      />
      <input
        ref={versionFileRef}
        type="file"
        style={{ display: "none" }}
        onChange={onVersionFileSelected}
      />

      <div className="page-header">
        <div>
          <h1 className="page-title">Documents</h1>
          <p className="page-subtitle">
            Upload and version-control counter documents — licenses, contracts,
            invoices, compliance
          </p>
        </div>
        <div className="page-actions">
          <Button
            variant={showUpload ? "secondary" : "primary"}
            icon={<Upload size={15} />}
            onClick={() => {
              setShowUpload((s) => !s);
              setError(null);
              setSuccess(null);
            }}
          >
            {showUpload ? "Cancel" : "Upload Document"}
          </Button>
        </div>
      </div>

      {error && (
        <div className="login-error" style={{ marginBottom: 16 }}>
          {error}
        </div>
      )}
      {success && (
        <div
          style={{
            background: "var(--color-success-soft)",
            color: "var(--color-success)",
            padding: "9px 12px",
            borderRadius: "var(--radius-sm)",
            fontSize: 12.5,
            marginBottom: 16,
          }}
        >
          {success}
        </div>
      )}

      {showUpload && (
        <Card
          title="Upload a Document"
          subtitle="Fill in the details and choose the file — it's uploaded in one step"
        >
          <form onSubmit={submitUpload}>
            <div className="form-grid-3">
              <Input
                label="Title *"
                value={uploadForm.title}
                onChange={(e) =>
                  setUploadForm({ ...uploadForm, title: e.target.value })
                }
                required
              />
              <Select
                label="Category"
                value={uploadForm.category}
                onChange={(e) =>
                  setUploadForm({ ...uploadForm, category: e.target.value })
                }
              >
                {CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </Select>
              <Input
                label="Description (optional)"
                value={uploadForm.description}
                onChange={(e) =>
                  setUploadForm({ ...uploadForm, description: e.target.value })
                }
              />
              <Input
                label="Version notes (optional)"
                value={uploadForm.notes}
                onChange={(e) =>
                  setUploadForm({ ...uploadForm, notes: e.target.value })
                }
              />
              <label className="field" style={{ gridColumn: "span 2" }}>
                <span className="field-label">File *</span>
                <input
                  ref={uploadFileRef}
                  type="file"
                  onChange={onUploadFileChange}
                  className="input"
                  accept=".pdf,.png,.jpg,.jpeg,.webp,.doc,.docx,.xls,.xlsx,.csv,.txt"
                  required
                />
                {uploadFile && (
                  <span className="field-hint">
                    {uploadFile.name} · {humanSize(uploadFile.size)}
                  </span>
                )}
              </label>
            </div>

            <div className="form-actions">
              <Button
                variant="secondary"
                type="button"
                onClick={() => {
                  setShowUpload(false);
                  setUploadFile(null);
                  if (uploadFileRef.current) uploadFileRef.current.value = "";
                }}
              >
                Cancel
              </Button>
              <Button
                type="submit"
                loading={uploading}
                icon={<Upload size={15} />}
              >
                Upload
              </Button>
            </div>
          </form>
        </Card>
      )}

      <div style={{ marginTop: showUpload ? 20 : 0 }}>
        <Card
          title="Document Library"
          subtitle={`${docs.length} document${docs.length !== 1 ? "s" : ""}`}
          padded={false}
        >
          <div className="table-scroll">
            <Table
              columns={columns}
              rows={docs}
              empty="No documents yet. Click Upload Document to add one."
            />
          </div>
        </Card>
      </div>

      {expandedDoc && (
        <div style={{ marginTop: 20 }}>
          <Card
            title={`Version History — ${expandedDoc.title}`}
            subtitle={`${expandedDoc.versions.length} version${expandedDoc.versions.length !== 1 ? "s" : ""}`}
            padded={false}
          >
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Version</th>
                    <th>Filename</th>
                    <th>Size</th>
                    <th>Uploaded By</th>
                    <th>Date</th>
                    <th>Notes</th>
                    <th style={{ textAlign: "right" }}>Download</th>
                  </tr>
                </thead>
                <tbody>
                  {expandedDoc.versions.map((v) => (
                    <tr key={v.id}>
                      <td>
                        <Badge tone="info">v{v.version}</Badge>
                      </td>
                      <td>
                        <span className="mono">{v.original_filename}</span>
                      </td>
                      <td>{humanSize(v.file_size)}</td>
                      <td>{v.uploaded_by ?? "—"}</td>
                      <td>{formatDate(v.uploaded_at)}</td>
                      <td>{v.notes || "—"}</td>
                      <td style={{ textAlign: "right" }}>
                        <button
                          className="icon-btn"
                          onClick={() =>
                            downloadVersion(v.id, v.original_filename)
                          }
                          title="Download this version"
                        >
                          <Download size={15} />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>
        </div>
      )}
    </>
  );
}
