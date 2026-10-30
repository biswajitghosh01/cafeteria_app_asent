from datetime import date
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import AuditLog, Sale, User
from app.schemas import SaleCreate, SaleOut

router = APIRouter(prefix="/sales", tags=["sales"])

TDS_RATE = Decimal("0.001")        # 0.1%
FOOD_GST_RATE = Decimal("0.05")    # 5%  (inclusive in transaction_value)
GST_18_RATE = Decimal("0.18")      # 18% (inclusive in commission/compliance/other)


def _totals(p: SaleCreate) -> SaleCreate:
    """Compute TDS, GST payable, and Net Payable.

    The user enters: transaction_value, commission_gross,
    compliance_gross, other_gross.
    The backend computes everything else.
    """
    tv = Decimal(str(p.transaction_value or 0))

    # 1. TDS = 0.1% of transaction value
    p.tds = (tv * TDS_RATE).quantize(Decimal("0.01"))

    # 2. GST Payable = 5% component already inside the transaction value
    #    (TV is inclusive of GST, so GST = TV − TV/1.05)
    p.gst_payable = (tv - (tv / (1 + FOOD_GST_RATE))).quantize(Decimal("0.01"))

    # 3. Split each 18%-inclusive amount into base + GST (for reporting only)
    for field in ("commission", "compliance", "other"):
        gross = Decimal(str(getattr(p, f"{field}_gross") or 0))
        base = (gross / (1 + GST_18_RATE)).quantize(Decimal("0.01"))
        gst = (gross - base).quantize(Decimal("0.01"))
        setattr(p, f"{field}_base", base)
        setattr(p, f"{field}_gst", gst)

    # 4. Total charges = TDS + GST + Commission + Compliance + Other (all gross)
    p.total_gross = (
        p.tds
        + p.gst_payable
        + Decimal(str(p.commission_gross or 0))
        + Decimal(str(p.compliance_gross or 0))
        + Decimal(str(p.other_gross or 0))
    ).quantize(Decimal("0.01"))

    # 5. Net Payable = Transaction Value − Total Charges
    p.net_receivable = (tv - p.total_gross).quantize(Decimal("0.01"))

    return p


async def _log(db, user, request, action, entity, entity_id, details=""):
    db.add(AuditLog(
        user_email=user.email,
        action=action,
        entity=entity,
        entity_id=entity_id,
        details=details,
        ip_address=request.client.host if request.client else None,
    ))


@router.get("", response_model=list[SaleOut])
async def list_sales(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date | None = Query(None),
    end: date | None = Query(None),
    limit: int = Query(200, le=1000),
):
    stmt = select(Sale).order_by(Sale.period_start.desc(), Sale.id.desc()).limit(limit)
    if start:
        stmt = stmt.where(Sale.period_start >= start)
    if end:
        stmt = stmt.where(Sale.period_end <= end)
    result = await db.execute(stmt)
    return result.scalars().all()


@router.post("", response_model=SaleOut, status_code=201)
async def create_sale(
    request: Request,
    payload: SaleCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    payload = _totals(payload)
    sale = Sale(**payload.model_dump(), created_by=user.id)
    db.add(sale)
    await db.flush()
    await _log(db, user, request, "create", "sale", str(sale.id),
               f"Invoice {sale.invoice_no}")
    await db.commit()
    await db.refresh(sale)
    return sale


@router.put("/{sale_id}", response_model=SaleOut)
async def update_sale(
    sale_id: int,
    request: Request,
    payload: SaleCreate,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    sale = await db.get(Sale, sale_id)
    if sale is None:
        raise HTTPException(404, "Sale not found")
    payload = _totals(payload)
    for k, v in payload.model_dump().items():
        setattr(sale, k, v)
    await _log(db, user, request, "update", "sale", str(sale.id),
               f"Invoice {sale.invoice_no}")
    await db.commit()
    await db.refresh(sale)
    return sale


@router.delete("/{sale_id}", status_code=204)
async def delete_sale(
    sale_id: int,
    request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    sale = await db.get(Sale, sale_id)
    if sale is None:
        raise HTTPException(404, "Sale not found")
    await _log(db, user, request, "delete", "sale", str(sale.id),
               f"Invoice {sale.invoice_no}")
    await db.delete(sale)
    await db.commit()