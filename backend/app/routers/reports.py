from datetime import date
from decimal import Decimal
from io import BytesIO
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle,
)
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.database import get_db
from app.models import (
    AuditLog, BalanceSheetSnapshot, Employee, FixedExpense, Purchase,
    SalaryRecord, Sale, User,
)
from app.schemas import (
    BalanceSheetInput, BalanceSheetOut, DashboardSummary, ProfitLossOut,
)

router = APIRouter(prefix="/reports", tags=["reports"])

# =============================================================================
# Shared helpers
# =============================================================================

CURRENCY_FMT = "₹#,##0.00"
HEADER_FILL = PatternFill("solid", fgColor="0F2D52")
HEADER_FONT = Font(color="FFFFFF", bold=True, size=11)
TOTAL_FONT = Font(bold=True)

PDF_HEADER_BG = colors.HexColor("#0f2d52")
PDF_ROW_ALT = colors.HexColor("#f8fafc")
PDF_GRID = colors.HexColor("#cbd5e1")


def _inr(value) -> str:
    try:
        n = Decimal(str(value or 0))
        return f"₹{n:,.2f}"
    except Exception:
        return "₹0.00"


def _autosize(ws, widths: dict[int, int]) -> None:
    for col_idx, width in widths.items():
        ws.column_dimensions[get_column_letter(col_idx)].width = width


def _write_xlsx_header(ws, headers: list[str]) -> None:
    for col_idx, text in enumerate(headers, start=1):
        cell = ws.cell(row=1, column=col_idx, value=text)
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = Alignment(horizontal="center", vertical="center")


def _stream_xlsx(ws, filename: str) -> StreamingResponse:
    buffer = BytesIO()
    ws.parent.save(buffer)
    buffer.seek(0)
    return StreamingResponse(
        buffer,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _stream_pdf(story, filename: str) -> StreamingResponse:
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=landscape(A4),
        leftMargin=24, rightMargin=24, topMargin=28, bottomMargin=28,
        title=filename,
    )
    doc.build(story)
    buffer.seek(0)
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _pdf_title(text: str) -> Paragraph:
    style = ParagraphStyle(
        "title", fontSize=16, fontName="Helvetica-Bold",
        textColor=PDF_HEADER_BG, spaceAfter=6,
    )
    return Paragraph(text, style)


def _pdf_subtitle(text: str) -> Paragraph:
    style = ParagraphStyle(
        "subtitle", fontSize=10, fontName="Helvetica",
        textColor=colors.HexColor("#475569"), spaceAfter=12,
    )
    return Paragraph(text, style)


def _pdf_table(headers: list[str], rows: list[list[str]]) -> Table:
    data = [headers] + rows
    table = Table(data, repeatRows=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), PDF_HEADER_BG),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("ALIGN", (1, 1), (-1, -1), "RIGHT"),
        ("ALIGN", (0, 0), (-1, 0), "CENTER"),
        ("GRID", (0, 0), (-1, -1), 0.25, PDF_GRID),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1),
         [colors.white, PDF_ROW_ALT]),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    return table


async def _profit_loss(
    db: AsyncSession, start: date, end: date,
) -> ProfitLossOut:
    if start > end:
        raise HTTPException(422, "Start date must be on or before end date")

    sales = (await db.execute(select(
        func.coalesce(func.sum(Sale.transaction_value), 0),
        func.coalesce(func.sum(Sale.gst_payable), 0),
        func.coalesce(func.sum(Sale.commission_base), 0),
        func.coalesce(func.sum(Sale.compliance_base), 0),
        func.coalesce(func.sum(Sale.other_base), 0),
    ).where(
        Sale.period_start >= start,
        Sale.period_end <= end,
    ))).one()

    purchases = (await db.execute(
        select(func.coalesce(func.sum(Purchase.amount), 0))
        .where(Purchase.purchase_date.between(start, end))
    )).scalar_one()

    fixed_expenses = (await db.execute(
        select(func.coalesce(func.sum(FixedExpense.amount), 0))
        .where(FixedExpense.expense_date.between(start, end))
    )).scalar_one()

    payroll = (await db.execute(
        select(func.coalesce(
            func.sum(
                SalaryRecord.gross
                + SalaryRecord.pf_employer
                + SalaryRecord.esi_employer
            ),
            0,
        )).where(
            SalaryRecord.pay_period >= start.strftime("%Y-%m"),
            SalaryRecord.pay_period <= end.strftime("%Y-%m"),
        )
    )).scalar_one()

    sales_revenue = Decimal(str(sales[0] or 0)) - Decimal(str(sales[1] or 0))
    purchase_cost = Decimal(str(purchases or 0))
    gross_profit = sales_revenue - purchase_cost
    commission = Decimal(str(sales[2] or 0))
    compliance = Decimal(str(sales[3] or 0))
    other_sales = Decimal(str(sales[4] or 0))
    fixed_cost = Decimal(str(fixed_expenses or 0))
    payroll_cost = Decimal(str(payroll or 0))
    total_expenses = (
        commission + compliance + other_sales + fixed_cost + payroll_cost
    )

    return ProfitLossOut(
        start=start,
        end=end,
        sales_revenue=sales_revenue,
        purchases=purchase_cost,
        gross_profit=gross_profit,
        commission_expense=commission,
        compliance_expense=compliance,
        other_sales_expense=other_sales,
        fixed_expenses=fixed_cost,
        payroll_expense=payroll_cost,
        total_expenses=total_expenses,
        net_profit=gross_profit - total_expenses,
    )


def _profit_loss_rows(report: ProfitLossOut) -> list[tuple[str, Decimal]]:
    return [
        ("Sales revenue (excluding output GST)", report.sales_revenue),
        ("Purchases (excluding input GST)", -report.purchases),
        ("Gross profit", report.gross_profit),
        ("Commission expense (excluding GST)", -report.commission_expense),
        ("Compliance expense (excluding GST)", -report.compliance_expense),
        ("Other sales expense (excluding GST)", -report.other_sales_expense),
        ("Fixed expenses (as recorded)", -report.fixed_expenses),
        ("Payroll (gross plus employer PF/ESI)", -report.payroll_expense),
        ("Total operating expenses", -report.total_expenses),
        ("Net profit / (loss)", report.net_profit),
    ]


def _balance_sheet_out(snapshot: BalanceSheetSnapshot) -> BalanceSheetOut:
    assets = sum((
        snapshot.cash_and_bank,
        snapshot.accounts_receivable,
        snapshot.inventory,
        snapshot.other_current_assets,
        snapshot.property_and_equipment,
    ), Decimal("0.00"))
    liabilities = sum((
        snapshot.accounts_payable,
        snapshot.loans_payable,
        snapshot.gst_payable,
        snapshot.other_liabilities,
    ), Decimal("0.00"))
    equity = snapshot.owner_capital + snapshot.retained_earnings
    return BalanceSheetOut(
        id=snapshot.id,
        as_of_date=snapshot.as_of_date,
        cash_and_bank=snapshot.cash_and_bank,
        accounts_receivable=snapshot.accounts_receivable,
        inventory=snapshot.inventory,
        other_current_assets=snapshot.other_current_assets,
        property_and_equipment=snapshot.property_and_equipment,
        accounts_payable=snapshot.accounts_payable,
        loans_payable=snapshot.loans_payable,
        gst_payable=snapshot.gst_payable,
        other_liabilities=snapshot.other_liabilities,
        owner_capital=snapshot.owner_capital,
        retained_earnings=snapshot.retained_earnings,
        created_at=snapshot.created_at,
        updated_at=snapshot.updated_at,
        total_assets=assets,
        total_liabilities=liabilities,
        total_equity=equity,
        total_liabilities_and_equity=liabilities + equity,
        balanced=assets == liabilities + equity,
    )


# =============================================================================
# Dashboard (existing)
# =============================================================================

@router.get("/dashboard", response_model=DashboardSummary)
async def dashboard(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...),
    end: date = Query(...),
):
    sales_row = (await db.execute(select(
        func.coalesce(func.sum(Sale.transaction_value), 0),
        func.coalesce(func.sum(Sale.tds), 0),
        func.coalesce(func.sum(Sale.gst_payable), 0),
        func.coalesce(func.sum(Sale.commission_gross), 0),
        func.coalesce(func.sum(Sale.compliance_gross), 0),
        func.coalesce(func.sum(Sale.other_gross), 0),
        func.coalesce(func.sum(Sale.total_gross), 0),
        func.coalesce(func.sum(Sale.net_receivable), 0),
    ).where(
        Sale.period_start >= start,
        Sale.period_end <= end,
    ))).one()

    purchases_total = (await db.execute(
        select(func.coalesce(func.sum(Purchase.total), 0))
        .where(Purchase.purchase_date.between(start, end))
    )).scalar_one()

    expenses_total = (await db.execute(
        select(func.coalesce(func.sum(FixedExpense.amount), 0))
        .where(FixedExpense.expense_date.between(start, end))
    )).scalar_one()

    salary_total = (await db.execute(
        select(func.coalesce(func.sum(SalaryRecord.net_pay), 0))
        .where(SalaryRecord.paid.is_(True))
    )).scalar_one()

    net_position = (
        Decimal(sales_row[7])
        - Decimal(purchases_total)
        - Decimal(expenses_total)
        - Decimal(salary_total)
    )

    return DashboardSummary(
        period_start=start,
        period_end=end,
        total_transaction_value=sales_row[0],
        total_tds=sales_row[1],
        total_gst_payable=sales_row[2],
        total_commission=sales_row[3],
        total_compliance=sales_row[4],
        total_other=sales_row[5],
        total_charges=sales_row[6],
        total_net_payable=sales_row[7],
        total_purchases=purchases_total,
        total_fixed_expenses=expenses_total,
        total_salary_paid=salary_total,
        net_position=net_position,
    )


# =============================================================================
# Financial statements
# =============================================================================

@router.get("/profit-loss", response_model=ProfitLossOut)
async def profit_loss(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...),
    end: date = Query(...),
):
    return await _profit_loss(db, start, end)


@router.get("/profit-loss.xlsx")
async def profit_loss_xlsx(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...),
    end: date = Query(...),
):
    report = await _profit_loss(db, start, end)
    wb = Workbook()
    ws = wb.active
    ws.title = "Profit and Loss"
    _write_xlsx_header(ws, ["Statement line", "Amount"])
    for label, amount in _profit_loss_rows(report):
        ws.append([label, float(amount)])
        ws.cell(row=ws.max_row, column=2).number_format = CURRENCY_FMT
    ws.append([])
    note_row = ws.max_row + 1
    ws.append([
        "Basis: Purchases are treated as current-period costs because inventory "
        "and cost of goods sold are not tracked. Fixed expenses use entered amounts."
    ])
    ws.merge_cells(start_row=note_row, start_column=1, end_row=note_row, end_column=2)
    ws.cell(row=note_row, column=1).alignment = Alignment(wrap_text=True)
    ws.row_dimensions[note_row].height = 30
    _autosize(ws, {1: 48, 2: 20})
    return _stream_xlsx(ws, f"profit-loss-{start}-to-{end}.xlsx")


@router.get("/profit-loss.pdf")
async def profit_loss_pdf(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...),
    end: date = Query(...),
):
    report = await _profit_loss(db, start, end)
    rows = [[label, _inr(amount)] for label, amount in _profit_loss_rows(report)]
    story = [
        _pdf_title("Profit and Loss Statement"),
        _pdf_subtitle(f"Period: {start.isoformat()} to {end.isoformat()}"),
        _pdf_table(["Statement line", "Amount"], rows),
        Spacer(1, 10),
        _pdf_subtitle(
            "Payroll uses recorded gross pay plus employer PF/ESI. Salary "
            "records are included by pay month, whether paid or unpaid. "
            "Purchases are treated as current-period costs because inventory "
            "and cost of goods sold are not tracked; fixed expenses use entered amounts."
        ),
    ]
    return _stream_pdf(story, f"profit-loss-{start}-to-{end}.pdf")


@router.get("/balance-sheet", response_model=BalanceSheetOut | None)
async def get_balance_sheet(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    as_of_date: date = Query(...),
):
    snapshot = (await db.execute(
        select(BalanceSheetSnapshot).where(
            BalanceSheetSnapshot.as_of_date == as_of_date
        )
    )).scalar_one_or_none()
    return _balance_sheet_out(snapshot) if snapshot else None


@router.put("/balance-sheet", response_model=BalanceSheetOut)
async def save_balance_sheet(
    payload: BalanceSheetInput,
    request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
):
    values = payload.model_dump(exclude={"as_of_date"})
    total_assets = sum((
        values["cash_and_bank"],
        values["accounts_receivable"],
        values["inventory"],
        values["other_current_assets"],
        values["property_and_equipment"],
    ), Decimal("0.00"))
    total_liabilities_and_equity = sum((
        values["accounts_payable"],
        values["loans_payable"],
        values["gst_payable"],
        values["other_liabilities"],
        values["owner_capital"],
        values["retained_earnings"],
    ), Decimal("0.00"))
    if total_assets != total_liabilities_and_equity:
        raise HTTPException(
            422,
            "Balance sheet does not balance: assets must equal liabilities plus equity",
        )

    snapshot = (await db.execute(
        select(BalanceSheetSnapshot).where(
            BalanceSheetSnapshot.as_of_date == payload.as_of_date
        )
    )).scalar_one_or_none()
    action = "update" if snapshot else "create"
    if snapshot is None:
        snapshot = BalanceSheetSnapshot(
            as_of_date=payload.as_of_date,
            **values,
        )
        db.add(snapshot)
    else:
        for field, value in values.items():
            setattr(snapshot, field, value)

    db.add(AuditLog(
        user_email=user.email,
        action=action,
        entity="balance_sheet",
        entity_id=payload.as_of_date.isoformat(),
        details=f"Balance sheet as of {payload.as_of_date.isoformat()}",
        ip_address=request.client.host if request.client else None,
    ))
    await db.commit()
    await db.refresh(snapshot)
    return _balance_sheet_out(snapshot)


async def _get_saved_balance_sheet(
    db: AsyncSession, as_of_date: date,
) -> BalanceSheetOut:
    snapshot = (await db.execute(
        select(BalanceSheetSnapshot).where(
            BalanceSheetSnapshot.as_of_date == as_of_date
        )
    )).scalar_one_or_none()
    if snapshot is None:
        raise HTTPException(404, "No saved balance sheet exists for this date")
    return _balance_sheet_out(snapshot)


@router.get("/balance-sheet.xlsx")
async def balance_sheet_xlsx(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    as_of_date: date = Query(...),
):
    report = await _get_saved_balance_sheet(db, as_of_date)
    wb = Workbook()
    ws = wb.active
    ws.title = "Balance Sheet"
    _write_xlsx_header(ws, ["Account", "Amount"])
    for label, amount in [
        ("Cash and bank", report.cash_and_bank),
        ("Accounts receivable", report.accounts_receivable),
        ("Inventory", report.inventory),
        ("Other current assets", report.other_current_assets),
        ("Property and equipment", report.property_and_equipment),
        ("Total assets", report.total_assets),
        ("Accounts payable", report.accounts_payable),
        ("Loans payable", report.loans_payable),
        ("GST payable", report.gst_payable),
        ("Other liabilities", report.other_liabilities),
        ("Total liabilities", report.total_liabilities),
        ("Owner capital", report.owner_capital),
        ("Retained earnings", report.retained_earnings),
        ("Total equity", report.total_equity),
        ("Total liabilities and equity", report.total_liabilities_and_equity),
    ]:
        ws.append([label, float(amount)])
        ws.cell(row=ws.max_row, column=2).number_format = CURRENCY_FMT
    _autosize(ws, {1: 38, 2: 20})
    return _stream_xlsx(ws, f"balance-sheet-{as_of_date}.xlsx")


@router.get("/balance-sheet.pdf")
async def balance_sheet_pdf(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    as_of_date: date = Query(...),
):
    report = await _get_saved_balance_sheet(db, as_of_date)
    rows = [
        ["ASSETS", ""],
        ["Cash and bank", _inr(report.cash_and_bank)],
        ["Accounts receivable", _inr(report.accounts_receivable)],
        ["Inventory", _inr(report.inventory)],
        ["Other current assets", _inr(report.other_current_assets)],
        ["Property and equipment", _inr(report.property_and_equipment)],
        ["Total assets", _inr(report.total_assets)],
        ["LIABILITIES", ""],
        ["Accounts payable", _inr(report.accounts_payable)],
        ["Loans payable", _inr(report.loans_payable)],
        ["GST payable", _inr(report.gst_payable)],
        ["Other liabilities", _inr(report.other_liabilities)],
        ["Total liabilities", _inr(report.total_liabilities)],
        ["EQUITY", ""],
        ["Owner capital", _inr(report.owner_capital)],
        ["Retained earnings", _inr(report.retained_earnings)],
        ["Total equity", _inr(report.total_equity)],
        ["Total liabilities and equity", _inr(report.total_liabilities_and_equity)],
    ]
    story = [
        _pdf_title("Balance Sheet"),
        _pdf_subtitle(f"As of: {as_of_date.isoformat()}"),
        _pdf_table(["Account", "Amount"], rows),
    ]
    return _stream_pdf(story, f"balance-sheet-{as_of_date}.pdf")


# =============================================================================
# Sales Register
# =============================================================================

@router.get("/sales.xlsx")
async def sales_xlsx(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...),
    end: date = Query(...),
):
    rows = (await db.execute(
        select(Sale)
        .where(Sale.period_start >= start, Sale.period_end <= end)
        .order_by(Sale.period_start, Sale.id)
    )).scalars().all()

    wb = Workbook()
    ws = wb.active
    ws.title = "Sales Register"

    headers = [
        "Period Start", "Period End", "Invoice", "Customer",
        "Transaction Value", "TDS", "GST Payable",
        "Commission", "Compliance", "Other",
        "Total Charges", "Net Payable",
    ]
    _write_xlsx_header(ws, headers)

    for r in rows:
        ws.append([
            r.period_start.isoformat(), r.period_end.isoformat(),
            r.invoice_no, r.customer,
            float(r.transaction_value), float(r.tds),
            float(r.gst_payable), float(r.commission_gross),
            float(r.compliance_gross), float(r.other_gross),
            float(r.total_gross), float(r.net_receivable),
        ])

    for col in range(5, 13):
        for row in range(2, ws.max_row + 1):
            ws.cell(row=row, column=col).number_format = CURRENCY_FMT

    total_row = ws.max_row + 1
    ws.cell(row=total_row, column=4, value="TOTAL").font = TOTAL_FONT
    for col in range(5, 13):
        letter = get_column_letter(col)
        cell = ws.cell(
            row=total_row, column=col,
            value=f"=SUM({letter}2:{letter}{total_row - 1})",
        )
        cell.font = TOTAL_FONT
        cell.number_format = CURRENCY_FMT

    _autosize(ws, {1: 12, 2: 12, 3: 16, 4: 24,
                   5: 16, 6: 12, 7: 12, 8: 14,
                   9: 14, 10: 12, 11: 14, 12: 14})

    return _stream_xlsx(ws, f"sales-{start}-to-{end}.xlsx")


@router.get("/sales.pdf")
async def sales_pdf(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...),
    end: date = Query(...),
):
    rows = (await db.execute(
        select(Sale)
        .where(Sale.period_start >= start, Sale.period_end <= end)
        .order_by(Sale.period_start, Sale.id)
    )).scalars().all()

    headers = [
        "Period", "Invoice", "Customer", "Txn Value",
        "TDS", "GST", "Commission", "Compliance",
        "Other", "Charges", "Net Payable",
    ]
    data = [
        [
            f"{r.period_start} → {r.period_end}",
            r.invoice_no, (r.customer or "")[:20],
            _inr(r.transaction_value), _inr(r.tds), _inr(r.gst_payable),
            _inr(r.commission_gross), _inr(r.compliance_gross),
            _inr(r.other_gross), _inr(r.total_gross),
            _inr(r.net_receivable),
        ]
        for r in rows
    ]

    story = [
        _pdf_title("Sales Register"),
        _pdf_subtitle(f"Period: {start.isoformat()} to {end.isoformat()}"),
        _pdf_table(headers, data),
    ]
    return _stream_pdf(story, f"sales-{start}-to-{end}.pdf")


# =============================================================================
# Purchases Register
# =============================================================================

@router.get("/purchases.xlsx")
async def purchases_xlsx(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...),
    end: date = Query(...),
):
    rows = (await db.execute(
        select(Purchase)
        .where(Purchase.purchase_date.between(start, end))
        .order_by(Purchase.purchase_date, Purchase.id)
    )).scalars().all()

    wb = Workbook()
    ws = wb.active
    ws.title = "Purchases"
    _write_xlsx_header(ws, ["Date", "Bill No.", "Vendor",
                            "Amount", "GST", "Total"])

    for r in rows:
        ws.append([
            r.purchase_date.isoformat(), r.bill_no, r.vendor,
            float(r.amount), float(r.gst), float(r.total),
        ])

    for col in range(4, 7):
        for row in range(2, ws.max_row + 1):
            ws.cell(row=row, column=col).number_format = CURRENCY_FMT

    total_row = ws.max_row + 1
    ws.cell(row=total_row, column=3, value="TOTAL").font = TOTAL_FONT
    for col in range(4, 7):
        letter = get_column_letter(col)
        cell = ws.cell(
            row=total_row, column=col,
            value=f"=SUM({letter}2:{letter}{total_row - 1})",
        )
        cell.font = TOTAL_FONT
        cell.number_format = CURRENCY_FMT

    _autosize(ws, {1: 12, 2: 16, 3: 32, 4: 14, 5: 12, 6: 14})
    return _stream_xlsx(ws, f"purchases-{start}-to-{end}.xlsx")


@router.get("/purchases.pdf")
async def purchases_pdf(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...),
    end: date = Query(...),
):
    rows = (await db.execute(
        select(Purchase)
        .where(Purchase.purchase_date.between(start, end))
        .order_by(Purchase.purchase_date, Purchase.id)
    )).scalars().all()

    headers = ["Date", "Bill", "Vendor", "Amount", "GST", "Total"]
    data = [
        [
            r.purchase_date.isoformat(), r.bill_no, (r.vendor or "")[:28],
            _inr(r.amount), _inr(r.gst), _inr(r.total),
        ]
        for r in rows
    ]

    story = [
        _pdf_title("Purchases Register"),
        _pdf_subtitle(f"Period: {start.isoformat()} to {end.isoformat()}"),
        _pdf_table(headers, data),
    ]
    return _stream_pdf(story, f"purchases-{start}-to-{end}.pdf")


# =============================================================================
# Fixed Expenses
# =============================================================================

@router.get("/expenses.xlsx")
async def expenses_xlsx(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...),
    end: date = Query(...),
):
    rows = (await db.execute(
        select(FixedExpense)
        .where(FixedExpense.expense_date.between(start, end))
        .order_by(FixedExpense.expense_date, FixedExpense.id)
    )).scalars().all()

    wb = Workbook()
    ws = wb.active
    ws.title = "Fixed Expenses"
    _write_xlsx_header(ws, ["Date", "Category", "Description",
                            "Amount", "Due Date", "Paid"])

    for r in rows:
        ws.append([
            r.expense_date.isoformat(),
            r.category.value,
            r.description,
            float(r.amount),
            r.due_date.isoformat() if r.due_date else "",
            "Yes" if r.is_paid else "No",
        ])

    for row in range(2, ws.max_row + 1):
        ws.cell(row=row, column=4).number_format = CURRENCY_FMT

    total_row = ws.max_row + 1
    ws.cell(row=total_row, column=3, value="TOTAL").font = TOTAL_FONT
    cell = ws.cell(row=total_row, column=4,
                   value=f"=SUM(D2:D{total_row - 1})")
    cell.font = TOTAL_FONT
    cell.number_format = CURRENCY_FMT

    _autosize(ws, {1: 12, 2: 14, 3: 36, 4: 14, 5: 12, 6: 8})
    return _stream_xlsx(ws, f"fixed-expenses-{start}-to-{end}.xlsx")


@router.get("/expenses.pdf")
async def expenses_pdf(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    start: date = Query(...),
    end: date = Query(...),
):
    rows = (await db.execute(
        select(FixedExpense)
        .where(FixedExpense.expense_date.between(start, end))
        .order_by(FixedExpense.expense_date, FixedExpense.id)
    )).scalars().all()

    headers = ["Date", "Category", "Description", "Amount", "Due", "Paid"]
    data = [
        [
            r.expense_date.isoformat(),
            r.category.value,
            (r.description or "")[:40],
            _inr(r.amount),
            r.due_date.isoformat() if r.due_date else "—",
            "Yes" if r.is_paid else "No",
        ]
        for r in rows
    ]

    story = [
        _pdf_title("Fixed Expenses Statement"),
        _pdf_subtitle(f"Period: {start.isoformat()} to {end.isoformat()}"),
        _pdf_table(headers, data),
    ]
    return _stream_pdf(story, f"fixed-expenses-{start}-to-{end}.pdf")


# =============================================================================
# Salary Register
# =============================================================================

@router.get("/salary.xlsx")
async def salary_xlsx(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    pay_period: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
):
    rows = (await db.execute(
        select(SalaryRecord, Employee.full_name, Employee.emp_code)
        .join(Employee, Employee.id == SalaryRecord.employee_id)
        .where(SalaryRecord.pay_period == pay_period)
        .order_by(Employee.full_name)
    )).all()

    wb = Workbook()
    ws = wb.active
    ws.title = "Salary Register"
    _write_xlsx_header(ws, [
        "Code", "Employee", "Gross",
        "PF (Emp)", "PF (Er)", "ESI (Emp)", "ESI (Er)",
        "Income Tax", "Other", "Net Pay", "Paid",
    ])

    for record, name, code in rows:
        ws.append([
            code, name, float(record.gross),
            float(record.pf_employee), float(record.pf_employer),
            float(record.esi_employee), float(record.esi_employer),
            float(record.income_tax), float(record.other_deductions),
            float(record.net_pay),
            "Yes" if record.paid else "No",
        ])

    for col in range(3, 11):
        for row in range(2, ws.max_row + 1):
            ws.cell(row=row, column=col).number_format = CURRENCY_FMT

    total_row = ws.max_row + 1
    ws.cell(row=total_row, column=2, value="TOTAL").font = TOTAL_FONT
    for col in range(3, 11):
        letter = get_column_letter(col)
        cell = ws.cell(
            row=total_row, column=col,
            value=f"=SUM({letter}2:{letter}{total_row - 1})",
        )
        cell.font = TOTAL_FONT
        cell.number_format = CURRENCY_FMT

    _autosize(ws, {1: 10, 2: 26, 3: 12, 4: 12, 5: 12,
                   6: 12, 7: 12, 8: 12, 9: 12, 10: 12, 11: 6})
    return _stream_xlsx(ws, f"salary-{pay_period}.xlsx")


@router.get("/salary.pdf")
async def salary_pdf(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: Annotated[User, Depends(get_current_user)],
    pay_period: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
):
    rows = (await db.execute(
        select(SalaryRecord, Employee.full_name, Employee.emp_code)
        .join(Employee, Employee.id == SalaryRecord.employee_id)
        .where(SalaryRecord.pay_period == pay_period)
        .order_by(Employee.full_name)
    )).all()

    headers = ["Code", "Employee", "Gross",
               "PF (E)", "PF (R)", "ESI (E)", "ESI (R)",
               "IT", "Other", "Net", "Paid"]
    data = [
        [
            code, (name or "")[:20], _inr(record.gross),
            _inr(record.pf_employee), _inr(record.pf_employer),
            _inr(record.esi_employee), _inr(record.esi_employer),
            _inr(record.income_tax), _inr(record.other_deductions),
            _inr(record.net_pay),
            "Yes" if record.paid else "No",
        ]
        for record, name, code in rows
    ]

    story = [
        _pdf_title("Salary Register"),
        _pdf_subtitle(f"Pay period: {pay_period}"),
        _pdf_table(headers, data),
    ]
    return _stream_pdf(story, f"salary-{pay_period}.pdf")