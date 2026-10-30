"""Generate employee payslip PDFs using reportlab."""
import os
from datetime import date
from decimal import Decimal
from io import BytesIO
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

_BUNDLED_DIR = Path(__file__).parent / "fonts"

_FONT_CANDIDATES = [
    (str(_BUNDLED_DIR / "DejaVuSans.ttf"),
     str(_BUNDLED_DIR / "DejaVuSans-Bold.ttf")),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
     "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"),
    ("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
     "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"),
    ("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
     "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf"),
]

REGULAR_FONT = "Helvetica"
BOLD_FONT = "Helvetica-Bold"
RUPEE_AVAILABLE = False


def _is_ttc(path: str) -> bool:
    try:
        with open(path, "rb") as fh:
            return fh.read(4) == b"ttcf"
    except Exception:
        return False


def _register_fonts() -> None:
    global REGULAR_FONT, BOLD_FONT, RUPEE_AVAILABLE

    for regular_path, bold_path in _FONT_CANDIDATES:
        if not os.path.exists(regular_path):
            continue
        if _is_ttc(regular_path):
            continue
        try:
            pdfmetrics.registerFont(TTFont("ASFont", regular_path))
            REGULAR_FONT = "ASFont"

            if os.path.exists(bold_path) and not _is_ttc(bold_path):
                pdfmetrics.registerFont(TTFont("ASFont-Bold", bold_path))
                BOLD_FONT = "ASFont-Bold"
            else:
                BOLD_FONT = "ASFont"

            RUPEE_AVAILABLE = True
            return
        except Exception:
            continue

    REGULAR_FONT = "Helvetica"
    BOLD_FONT = "Helvetica-Bold"
    RUPEE_AVAILABLE = False


_register_fonts()


def _inr(value) -> str:
    try:
        n = Decimal(str(value or 0))
        symbol = "₹" if RUPEE_AVAILABLE else "Rs. "
        return f"{symbol}{n:,.2f}"
    except Exception:
        return "Rs. 0.00"


def _build_payslip_story(
    *,
    employee: dict,
    payroll: dict,
    company_name: str = "AS Enterprises",
) -> list:
    styles = getSampleStyleSheet()

    h1 = ParagraphStyle(
        "h1", parent=styles["Heading1"], fontName=BOLD_FONT,
        fontSize=18, textColor=colors.HexColor("#0f2d52"), alignment=1,
    )
    normal = ParagraphStyle(
        "normal", parent=styles["Normal"], fontName=REGULAR_FONT,
        fontSize=9, textColor=colors.HexColor("#0f172a"),
    )
    small = ParagraphStyle(
        "small", parent=styles["Normal"], fontName=REGULAR_FONT,
        fontSize=8, textColor=colors.HexColor("#64748b"), alignment=1,
    )

    story = [
        Paragraph(company_name, h1),
        Paragraph("PAYSLIP", h1),
        Spacer(1, 8),
    ]

    emp_rows = [
        ["Employee Code", employee.get("emp_code", "—"),
         "Pay Period", payroll.get("pay_period", "—")],
        ["Employee Name", employee.get("full_name", "—"),
         "Designation", employee.get("designation", "—")],
        ["Department", employee.get("department") or "—",
         "Date of Joining", str(employee.get("date_of_joining") or "—")],
        ["PAN", employee.get("pan") or "—",
         "UAN", employee.get("uan") or "—"],
        ["ESI No.", employee.get("esi_no") or "—",
         "Bank A/C", employee.get("bank_account") or "—"],
    ]
    emp_table = Table(emp_rows, colWidths=[35 * mm, 55 * mm, 35 * mm, 55 * mm])
    emp_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#f1f5f9")),
        ("BACKGROUND", (2, 0), (2, -1), colors.HexColor("#f1f5f9")),
        ("FONTNAME", (0, 0), (0, -1), BOLD_FONT),
        ("FONTNAME", (2, 0), (2, -1), BOLD_FONT),
        ("FONTNAME", (1, 0), (1, -1), REGULAR_FONT),
        ("FONTNAME", (3, 0), (3, -1), REGULAR_FONT),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#cbd5e1")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    story += [emp_table, Spacer(1, 10)]

    # Attendance summary
    attend_rows = [
        ["Days in Month", "Days Present", "Days Absent",
         "On Leave", "Payable Days"],
        [
            str(payroll.get("days_in_month", 0)),
            str(payroll.get("days_present", 0)),
            str(payroll.get("days_absent", 0)),
            str(payroll.get("days_on_leave", 0)),
            str(payroll.get("payable_days", 0)),
        ],
    ]
    attend_table = Table(
        attend_rows,
        colWidths=[35 * mm, 35 * mm, 35 * mm, 35 * mm, 40 * mm],
    )
    attend_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0f2d52")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), BOLD_FONT),
        ("FONTNAME", (0, 1), (-1, -1), REGULAR_FONT),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#cbd5e1")),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]))
    story += [attend_table, Spacer(1, 10)]

    # Earnings & deductions
    base_gross = Decimal(str(payroll.get("base_gross") or 0))
    gross = Decimal(str(payroll.get("gross") or 0))
    pf_employee = Decimal(str(payroll.get("pf_employee") or 0))
    esi_employee = Decimal(str(payroll.get("esi_employee") or 0))
    income_tax = Decimal(str(payroll.get("income_tax") or 0))
    other = Decimal(str(payroll.get("other_deductions") or 0))
    advance = Decimal(str(payroll.get("advance_deduction") or 0))
    advance_before = Decimal(str(payroll.get("advance_balance_before") or 0))
    advance_after = Decimal(str(payroll.get("advance_balance_after") or 0))

    total_deductions = (
        pf_employee + esi_employee + income_tax + other + advance
    )
    net_pay = Decimal(str(payroll.get("net_pay") or 0))

    earn_rows = [
        ["Earnings", "Amount"],
        ["Base Gross (Full Month)", _inr(base_gross)],
        [f"Daily Rate × {payroll.get('payable_days', 0)} Days", _inr(gross)],
        ["Total Earnings", _inr(gross)],
    ]
    ded_rows = [
        ["Deductions", "Amount"],
        ["PF (Employee 12%)", _inr(pf_employee)],
        ["ESI (Employee 0.75%)", _inr(esi_employee)],
        ["Income Tax (TDS)", _inr(income_tax)],
        ["Other Deductions", _inr(other)],
        ["Salary Advance Recovery", _inr(advance)],
        ["Total Deductions", _inr(total_deductions)],
    ]

    left = Table(earn_rows, colWidths=[55 * mm, 30 * mm])
    right = Table(ded_rows, colWidths=[55 * mm, 30 * mm])

    table_style = TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#0f2d52")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), BOLD_FONT),
        ("FONTNAME", (0, 1), (0, -1), REGULAR_FONT),
        ("FONTNAME", (1, 1), (1, -1), REGULAR_FONT),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("ALIGN", (1, 1), (1, -1), "RIGHT"),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#cbd5e1")),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ])
    left.setStyle(table_style)
    right.setStyle(table_style)

    combined = Table([[left, right]], colWidths=[90 * mm, 90 * mm])
    combined.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
    ]))
    story += [combined, Spacer(1, 10)]

    # Advance balance line if there was any activity
    if advance > 0 or advance_before > 0:
        balance_note = Table(
            [[
                "Advance balance before",
                _inr(advance_before),
                "Recovered this month",
                _inr(advance),
                "Balance after",
                _inr(advance_after),
            ]],
            colWidths=[38 * mm, 25 * mm, 38 * mm, 25 * mm, 30 * mm, 24 * mm],
        )
        balance_note.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#fef3c7")),
            ("FONTNAME", (0, 0), (0, 0), BOLD_FONT),
            ("FONTNAME", (2, 0), (2, 0), BOLD_FONT),
            ("FONTNAME", (4, 0), (4, 0), BOLD_FONT),
            ("FONTNAME", (1, 0), (1, 0), REGULAR_FONT),
            ("FONTNAME", (3, 0), (3, 0), REGULAR_FONT),
            ("FONTNAME", (5, 0), (5, 0), REGULAR_FONT),
            ("FONTSIZE", (0, 0), (-1, -1), 8),
            ("ALIGN", (1, 0), (1, 0), "RIGHT"),
            ("ALIGN", (3, 0), (3, 0), "RIGHT"),
            ("ALIGN", (5, 0), (5, 0), "RIGHT"),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ]))
        story += [balance_note, Spacer(1, 10)]

    # Net pay
    net_table = Table([["NET PAY", _inr(net_pay)]],
                      colWidths=[140 * mm, 40 * mm])
    net_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#c9a227")),
        ("TEXTCOLOR", (0, 0), (-1, -1), colors.white),
        ("FONTNAME", (0, 0), (-1, -1), BOLD_FONT),
        ("FONTSIZE", (0, 0), (-1, -1), 14),
        ("ALIGN", (1, 0), (1, 0), "RIGHT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 10),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
    ]))
    story += [net_table, Spacer(1, 16)]

    pf_employer = Decimal(str(payroll.get("pf_employer") or 0))
    esi_employer = Decimal(str(payroll.get("esi_employer") or 0))
    story += [
        Paragraph("Employer Contributions (for information only)", normal),
        Paragraph(
            f"PF (Employer): {_inr(pf_employer)}  |  "
            f"ESI (Employer): {_inr(esi_employer)}",
            normal,
        ),
        Spacer(1, 20),
    ]

    story += [
        Paragraph("This is a computer-generated payslip.", small),
        Paragraph(f"Generated on {date.today().isoformat()}", small),
    ]
    return story


def generate_payslip_pdf(employee: dict, payroll: dict) -> BytesIO:
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=20 * mm,
        rightMargin=20 * mm,
        topMargin=20 * mm,
        bottomMargin=20 * mm,
        title=f"Payslip-{payroll.get('pay_period', 'unknown')}",
    )
    story = _build_payslip_story(employee=employee, payroll=payroll)
    doc.build(story)
    buffer.seek(0)
    return buffer