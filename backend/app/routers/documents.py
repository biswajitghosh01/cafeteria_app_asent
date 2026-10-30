import logging
import re
import uuid
from pathlib import Path
from typing import Annotated

from fastapi import (
    APIRouter, Depends, File, Form, HTTPException, Query, UploadFile,
)
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import get_current_user
from app.config import settings
from app.database import get_db
from app.models import AuditLog, Document, DocumentVersion, User
from app.schemas import DocumentCreate, DocumentOut, DocumentVersionOut

logger = logging.getLogger("as-enterprises.documents")

router = APIRouter(prefix="/documents", tags=["documents"])

ALLOWED_EXT = {
    ".pdf", ".png", ".jpg", ".jpeg", ".webp",
    ".doc", ".docx", ".xls", ".xlsx", ".csv", ".txt",
}
MAX_SIZE = 25 * 1024 * 1024  # 25 MB


def _safe_filename(name: str) -> str:
    name = Path(name).name
    return re.sub(r"[^A-Za-z0-9._-]+", "_", name)


def _upload_root() -> Path:
    """Return the upload directory, creating it on first use."""
    root = settings.upload_path
    root.mkdir(parents=True, exist_ok=True)
    return root


async def _log(db, user, action, entity, entity_id, details=""):
    db.add(AuditLog(
        user_email=user.email,
        action=action,
        entity=entity,
        entity_id=entity_id,
        details=details,
    ))


@router.get("", response_model=list[DocumentOut])
async def list_documents(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    category: str | None = Query(None),
):
    stmt = (
        select(Document)
        .options(selectinload(Document.versions))
        .order_by(Document.created_at.desc())
    )
    if category:
        stmt = stmt.where(Document.category == category)
    result = await db.execute(stmt)
    return result.scalars().all()


@router.post("", response_model=DocumentOut, status_code=201)
async def create_document(
    payload: DocumentCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    doc = Document(
        title=payload.title,
        category=payload.category,
        description=payload.description,
        current_version=0,
        created_by=user.email,
    )
    db.add(doc)
    await db.flush()
    await _log(db, user, "create", "document", str(doc.id),
               f"Created document {doc.title}")
    await db.commit()

    stmt = (
        select(Document)
        .options(selectinload(Document.versions))
        .where(Document.id == doc.id)
    )
    return (await db.execute(stmt)).scalar_one()


@router.post(
    "/{document_id}/versions",
    response_model=DocumentVersionOut,
    status_code=201,
)
async def upload_version(
    document_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    file: UploadFile = File(...),
    notes: str | None = Form(None),
):
    doc = await db.get(Document, document_id)
    if doc is None:
        raise HTTPException(404, "Document not found")

    original = _safe_filename(file.filename or "unnamed")
    ext = Path(original).suffix.lower()
    if ext not in ALLOWED_EXT:
        raise HTTPException(
            400,
            f"File type {ext} not allowed. Allowed: {', '.join(sorted(ALLOWED_EXT))}",
        )

    content = await file.read()
    if len(content) == 0:
        raise HTTPException(400, "Uploaded file is empty")
    if len(content) > MAX_SIZE:
        raise HTTPException(
            400,
            f"File exceeds {MAX_SIZE // (1024 * 1024)} MB limit",
        )

    try:
        root = _upload_root()
    except Exception as exc:
        logger.exception("Cannot access upload directory: %s", exc)
        raise HTTPException(
            500,
            f"Upload directory not writable: {settings.upload_root}",
        ) from exc

    doc_dir = root / str(document_id)
    doc_dir.mkdir(parents=True, exist_ok=True)

    next_version = (doc.current_version or 0) + 1
    stored_name = f"v{next_version}_{uuid.uuid4().hex[:8]}{ext}"
    stored_path = doc_dir / stored_name

    try:
        with stored_path.open("wb") as fh:
            fh.write(content)
    except Exception as exc:
        logger.exception("Cannot write file %s: %s", stored_path, exc)
        raise HTTPException(500, f"Failed to save file: {exc}") from exc

    version = DocumentVersion(
        document_id=document_id,
        version=next_version,
        original_filename=original,
        stored_path=str(stored_path),
        content_type=file.content_type,
        file_size=len(content),
        notes=notes,
        uploaded_by=user.email,
    )
    db.add(version)
    doc.current_version = next_version
    await _log(db, user, "upload", "document", str(document_id),
               f"Uploaded v{next_version} of {doc.title}")
    await db.commit()
    await db.refresh(version)
    return version


@router.get(
    "/{document_id}/versions",
    response_model=list[DocumentVersionOut],
)
async def list_versions(
    document_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    stmt = (
        select(DocumentVersion)
        .where(DocumentVersion.document_id == document_id)
        .order_by(DocumentVersion.version.desc())
    )
    result = await db.execute(stmt)
    return result.scalars().all()


@router.get("/versions/{version_id}/download")
async def download_version(
    version_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
):
    version = await db.get(DocumentVersion, version_id)
    if version is None:
        raise HTTPException(404, "Version not found")

    path = Path(version.stored_path)
    if not path.exists():
        raise HTTPException(404, "File missing on disk")

    return FileResponse(
        path,
        media_type=version.content_type or "application/octet-stream",
        filename=version.original_filename,
    )


@router.delete("/{document_id}", status_code=204)
async def delete_document(
    document_id: int,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    doc = await db.get(Document, document_id)
    if doc is None:
        raise HTTPException(404, "Document not found")

    # Remove files from disk
    try:
        doc_dir = _upload_root() / str(document_id)
        if doc_dir.exists():
            for f in doc_dir.iterdir():
                f.unlink(missing_ok=True)
            doc_dir.rmdir()
    except Exception as exc:
        logger.warning("Could not remove files for document %s: %s", document_id, exc)

    await _log(db, user, "delete", "document", str(document_id),
               f"Deleted document {doc.title}")
    await db.delete(doc)
    await db.commit()