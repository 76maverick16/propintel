"""
PropIntel Underwriting Engine — v0.7.1
======================================
Design Principle #1: Agents extract and narrate. Code computes.
No number that enters a calculation may originate from a language model.

All inputs must come from structured data sources (MLS, Rentcast, BLS, census).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Optional

# ---------------------------------------------------------------------------
# Constants (locked in spec v0.7.1)
# ---------------------------------------------------------------------------

SPEC_VERSION = "v0.7.1"

# §11.2a gate thresholds
GATE_MAX_MONTHLY_BLEED = -75.0          # Cond 1: monthly CF must be >= this
GATE_MIN_IRR_BASE = 0.110               # Cond 3: IRR (base appreciation) >= 11.0%
GATE_MAX_SUSTAINED_POS_MONTH = 36       # Cond 2: must converge by month 36
GATE_PORTFOLIO_CARRY_CEILING = -350.0   # Cond 4: portfolio total CF ceiling

# §7.3 maintenance curve (maint_curve_new)
# Index = year 0–9; value = fraction of purchase price per year
MAINT_CURVE_NEW = [
    0.02, 0.02,  # years 0–1 (months 1–24)
    0.03, 0.03, 0.03,  # years 2–4 (months 25–60) — step at month 37
    0.05, 0.05, 0.05,  # years 5–7 (months 61–84) — step at month 61
    0.07, 0.07,  # years 8–9 (months 85–120)
]

# §10.8 refi cost recovery constants
REFI_COST_DEFAULT = 5_000.0             # closing costs estimate for refi calc
LOAN_TERM_MONTHS = 360


# ---------------------------------------------------------------------------
# Input / Output dataclasses
# ---------------------------------------------------------------------------

@dataclass
class UnderwritingInputs:
    """
    All inputs to the underwriting engine.
    Every field must come from a structured data source — never an LLM.
    Flag rent_source and insurance_source with ⚠ if not from a primary source.
    """
    # Property
    purchase_price: float
    down_pct: float                     # e.g. 0.20 for 20%
    interest_rate: float                # annual, e.g. 0.0725 for 7.25%
    monthly_rent: float
    loan_term_months: int = LOAN_TERM_MONTHS

    # Revenue
    vacancy_rate: float = 0.08          # e.g. 0.08 for 8%

    # Operating expenses (annual)
    insurance_annual: float = 0.0
    tax_annual: float = 0.0
    hoa_monthly: float = 0.0
    mgmt_rate: float = 0.08             # fraction of collected rent

    # Appreciation band (per §7.10 thesis_confidence)
    appr_low_pct: float = 0.02
    appr_base_pct: float = 0.03
    appr_high_pct: float = 0.04

    # Annual growth rates (per §9.2e / §10.4)
    # rent grows at rent_growth_annual; insurance/HOA/turnover at expense_growth_annual;
    # tax grows at tax_growth_annual (spec §9.2 says "tax ×1.03", so default = appr_base_pct)
    rent_growth_annual: float = 0.025   # 2.5% / yr — spec: $1,900 → $1,947.50 in yr 2
    expense_growth_annual: float = 0.025  # 2.5% / yr — spec: ins/HOA/turnover ×1.025
    tax_growth_annual: float = 0.03     # 3.0% / yr — spec: tax ×1.03

    # Acquisition costs (per §5.8 / §9.3c)
    # Equity invested in IRR = price × (down_pct + closing_pct).
    # Default 3% matches the spec's ~10.6% IRR for Cabot (§9.4 cross-check).
    closing_pct: float = 0.03           # buyer closing costs as % of purchase price

    # Portfolio context (for Cond 4)
    current_portfolio_cf: float = 0.0  # existing monthly CF excl. this property

    # Source flags (for audit trail)
    rent_source: str = ""
    insurance_source: str = ""

    def __post_init__(self):
        if not (0 < self.down_pct < 1):
            raise ValueError(f"down_pct must be between 0 and 1, got {self.down_pct}")
        if not (0 < self.interest_rate < 1):
            raise ValueError(f"interest_rate must be between 0 and 1, got {self.interest_rate}")
        if self.monthly_rent <= 0:
            raise ValueError(f"monthly_rent must be positive, got {self.monthly_rent}")
        if self.purchase_price <= 0:
            raise ValueError(f"purchase_price must be positive, got {self.purchase_price}")


@dataclass
class MonthlySnapshot:
    """One month's cash flow detail in the 10-year trace."""
    month: int
    gross_rent: float
    vacancy_loss: float
    effective_rent: float
    principal: float
    interest: float
    piti_payment: float                 # P+I+T+I (tax + insurance pro-rated monthly)
    hoa: float
    mgmt_fee: float
    maintenance: float
    total_expenses: float
    net_cf: float                       # net cash flow this month


@dataclass
class GateResult:
    """§11.2a four-condition gate result."""
    # Condition values
    cond1_monthly_bleed: float          # worst monthly CF in horizon
    cond2_cf_status: str                # 'converges' / 'exceeds_horizon' / 'always_positive'
    cond2_sustained_pos_month: Optional[int]  # month when CF first turns positive
    cond3_irr_base: float               # IRR at base appreciation
    cond4_portfolio_carry: float        # portfolio total CF if this property added

    # Condition pass/fail
    cond1_pass: bool
    cond2_pass: bool
    cond3_pass: bool
    cond4_pass: bool

    # Overall verdict
    verdict: str                        # 'PASS' / 'FAIL' / 'CONDITIONAL'
    fail_conditions: list[str]          # e.g. ['cond3']
    notes: str = ""


@dataclass
class RefiTriggers:
    """§10.8 three refi trigger rates."""
    breakeven_rate: float               # rate that makes monthly CF = current CF
    recoup_rate: float                  # rate that recoups refi cost in 24 months
    cf_target_rate: float               # rate needed for CF = 0 (binding)


@dataclass
class UnderwritingResult:
    """Full output of one underwriting run."""
    spec_version: str = SPEC_VERSION
    inputs: Optional[UnderwritingInputs] = None

    # Loan basics
    loan_amount: float = 0.0
    monthly_pi: float = 0.0            # principal + interest payment

    # 10-year cash flow trace (120 months)
    cf_trace: list[MonthlySnapshot] = field(default_factory=list)

    # IRR band
    irr_10yr_low: float = 0.0
    irr_10yr_base: float = 0.0
    irr_10yr_high: float = 0.0

    # §11.2a gate
    gate: Optional[GateResult] = None

    # §10.8 refi triggers
    refi: Optional[RefiTriggers] = None

    # Flags for audit
    flags: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Core calculations
# ---------------------------------------------------------------------------

def _monthly_payment(principal: float, annual_rate: float, term_months: int) -> float:
    """Standard fixed-rate mortgage payment formula."""
    r = annual_rate / 12
    if r == 0:
        return principal / term_months
    return principal * (r * (1 + r) ** term_months) / ((1 + r) ** term_months - 1)


def _amortize_month(
    balance: float, annual_rate: float, payment: float
) -> tuple[float, float, float]:
    """
    Returns (interest, principal, new_balance) for one month.
    """
    r = annual_rate / 12
    interest = balance * r
    principal = payment - interest
    new_balance = balance - principal
    return interest, principal, max(new_balance, 0.0)


def _maint_monthly(monthly_rent: float, month: int) -> float:
    """
    Monthly maintenance cost from maint_curve_new.
    Per spec §9.3b: rates are applied to monthly rent (not purchase price).
    "2% of $1,900 is $456/yr" — i.e. 2% * monthly_rent * 12 / 12 = 2% * monthly_rent.
    month is 1-indexed (1–120).
    """
    year_idx = (month - 1) // 12          # 0-indexed year
    year_idx = min(year_idx, len(MAINT_CURVE_NEW) - 1)
    annual_rate = MAINT_CURVE_NEW[year_idx]
    # annual_rate * monthly_rent = annual maintenance; divide by 12 for monthly
    return monthly_rent * annual_rate


def _build_cf_trace(inputs: UnderwritingInputs) -> list[MonthlySnapshot]:
    """
    Build 120-month cash flow trace with annual rent and expense growth.

    Spec §9.2 formula (exact):
        effective_rent = rent × (1 − vacancy_pct − pm_pct − maint_pct_year)
        cash_flow = effective_rent − monthly_pi − monthly_tax
                                   − monthly_ins − hoa − monthly_turnover_cost

    Per §9.2e growth:
      - Rent grows at rent_growth_annual (default 2.5%/yr).
      - Insurance and HOA (turnover) grow at expense_growth_annual (2.5%/yr).
      - Tax grows at tax_growth_annual (3.0%/yr, per "tax ×1.03").
      - maint_pct_year comes from MAINT_CURVE_NEW (applied to gross rent).
      - All growth factors use annual compounding at year boundaries.
        month 1–12 → factor^0, month 13–24 → factor^1, etc.
    """
    loan_amount = inputs.purchase_price * (1 - inputs.down_pct)
    monthly_pi = _monthly_payment(loan_amount, inputs.interest_rate, inputs.loan_term_months)

    balance = loan_amount
    trace = []

    for month in range(1, 121):
        # Year index (0-based) for annual growth compounding
        year = (month - 1) // 12   # month 1–12 → year 0; month 13–24 → year 1

        # Annual growth factors
        rent_factor = (1 + inputs.rent_growth_annual) ** year
        expense_factor = (1 + inputs.expense_growth_annual) ** year
        tax_factor = (1 + inputs.tax_growth_annual) ** year

        # Grown gross rent
        gross_rent = inputs.monthly_rent * rent_factor

        # Spec §9.3b maintenance rate for this year (applied to gross rent)
        maint_rate = MAINT_CURVE_NEW[min(year, len(MAINT_CURVE_NEW) - 1)]
        maintenance = gross_rent * maint_rate

        # Spec §9.2 effective_rent formula:
        # effective_rent = rent × (1 − vacancy_pct − pm_pct − maint_pct_year)
        # NOTE: all three variable-cost rates reduce gross rent proportionally
        effective_rate = 1.0 - inputs.vacancy_rate - inputs.mgmt_rate - maint_rate
        effective_rent = gross_rent * effective_rate

        # Vacancy loss and mgmt fee (for MonthlySnapshot reporting only)
        vacancy_loss = gross_rent * inputs.vacancy_rate
        mgmt_fee = gross_rent * inputs.mgmt_rate   # on gross rent per spec §9.2

        # Fixed costs (grown)
        tax_monthly = (inputs.tax_annual / 12) * tax_factor
        insurance_monthly = (inputs.insurance_annual / 12) * expense_factor
        hoa_this_month = inputs.hoa_monthly * expense_factor

        interest, principal, balance = _amortize_month(balance, inputs.interest_rate, monthly_pi)

        total_expenses = (
            monthly_pi
            + tax_monthly
            + insurance_monthly
            + hoa_this_month
            + mgmt_fee
            + maintenance
        )

        # Spec §9.2: cash_flow = effective_rent − monthly_pi − tax − ins − hoa − turnover
        net_cf = effective_rent - monthly_pi - tax_monthly - insurance_monthly - hoa_this_month

        snap = MonthlySnapshot(
            month=month,
            gross_rent=gross_rent,
            vacancy_loss=vacancy_loss,
            effective_rent=effective_rent,
            principal=principal,
            interest=interest,
            piti_payment=monthly_pi + tax_monthly + insurance_monthly,
            hoa=hoa_this_month,
            mgmt_fee=mgmt_fee,
            maintenance=maintenance,
            total_expenses=total_expenses,
            net_cf=net_cf,
        )
        trace.append(snap)

    return trace


def _irr_10yr(inputs: UnderwritingInputs, appr_rate: float) -> float:
    """
    Compute 10-year IRR given an annual appreciation rate.
    Cash flows: month 0 = -equity (down payment + closing costs proxied as 0).
    Months 1–120 = net monthly CF.
    Month 120 += net sale proceeds (appreciation value - remaining loan balance - 6% selling costs).
    Uses Newton-Raphson on monthly IRR, then annualizes.
    """
    # Per §9.3c / §5.8: equity_invested = price × (down_pct + closing_pct)
    equity_invested = inputs.purchase_price * (inputs.down_pct + inputs.closing_pct)
    loan_amount = inputs.purchase_price * (1 - inputs.down_pct)
    monthly_pi = _monthly_payment(loan_amount, inputs.interest_rate, inputs.loan_term_months)

    # Build monthly CFs — same spec §9.2 formula as _build_cf_trace
    cfs = [-equity_invested]
    balance = loan_amount

    for month in range(1, 121):
        year = (month - 1) // 12
        rent_factor = (1 + inputs.rent_growth_annual) ** year
        expense_factor = (1 + inputs.expense_growth_annual) ** year
        tax_factor = (1 + inputs.tax_growth_annual) ** year

        gross_rent = inputs.monthly_rent * rent_factor
        maint_rate = MAINT_CURVE_NEW[min(year, len(MAINT_CURVE_NEW) - 1)]
        effective_rate = 1.0 - inputs.vacancy_rate - inputs.mgmt_rate - maint_rate
        effective_rent = gross_rent * effective_rate

        interest, principal, balance = _amortize_month(balance, inputs.interest_rate, monthly_pi)
        tax_monthly = (inputs.tax_annual / 12) * tax_factor
        insurance_monthly = (inputs.insurance_annual / 12) * expense_factor
        hoa_this_month = inputs.hoa_monthly * expense_factor

        net_cf = effective_rent - monthly_pi - tax_monthly - insurance_monthly - hoa_this_month
        cfs.append(net_cf)

    # Terminal value at month 120
    # Per spec §9.3c: "agent commission plus seller closing costs run 6–8%";
    # default is 7% per §9.4 table (disposition_cost_pct default 0.07).
    fv = inputs.purchase_price * ((1 + appr_rate) ** 10)
    selling_costs = fv * 0.07
    net_proceeds = fv - balance - selling_costs
    cfs[120] += net_proceeds

    # Newton-Raphson for monthly IRR
    monthly_irr = _npv_solve(cfs)
    if monthly_irr is None:
        return 0.0
    # Annualize: (1 + monthly_irr)^12 - 1
    return (1 + monthly_irr) ** 12 - 1


def _npv_solve(cfs: list[float], guess: float = 0.005, max_iter: int = 1000, tol: float = 1e-8) -> Optional[float]:
    """Newton-Raphson IRR solver. Returns monthly rate or None if no convergence."""
    r = guess
    for _ in range(max_iter):
        # Guard against extreme rates that cause (1+r)^t overflow
        if r < -0.9999 or r > 50.0:
            return None
        try:
            npv = sum(cf / (1 + r) ** t for t, cf in enumerate(cfs))
            d_npv = sum(-t * cf / (1 + r) ** (t + 1) for t, cf in enumerate(cfs))
        except (OverflowError, ZeroDivisionError):
            return None
        if abs(d_npv) < 1e-12:
            return None
        r_new = r - npv / d_npv
        if abs(r_new - r) < tol:
            return r_new
        r = r_new
    return None


def _gate_cf_status(trace: list[MonthlySnapshot]) -> tuple[str, Optional[int]]:
    """
    Determine §11.2a Cond 2 CF status.
    Returns (status, sustained_pos_month).
    status: 'always_positive' | 'converges' | 'exceeds_horizon'
    """
    if all(s.net_cf >= 0 for s in trace):
        return "always_positive", 1

    first_pos = None
    for snap in trace:
        if snap.net_cf >= 0:
            first_pos = snap.month
            break

    if first_pos is None:
        return "exceeds_horizon", None

    # Check sustained: no negative CF from first_pos onward
    if all(s.net_cf >= 0 for s in trace if s.month >= first_pos):
        return "converges", first_pos
    return "exceeds_horizon", None


def _compute_refi_triggers(
    inputs: UnderwritingInputs, current_monthly_pi: float
) -> RefiTriggers:
    """
    §10.8 Three refi trigger rates.
    Binary-search each trigger rate.
    """
    loan_amount = inputs.purchase_price * (1 - inputs.down_pct)

    # Per spec §9.2: effective_rent = gross_rent × (1 − vacancy − pm − maint)
    # Use year-1 maintenance rate as proxy for refi calc
    year1_maint_rate = MAINT_CURVE_NEW[0]
    effective_rate = 1.0 - inputs.vacancy_rate - inputs.mgmt_rate - year1_maint_rate
    effective_rent = inputs.monthly_rent * effective_rate

    # Fixed monthly costs (no PI — varies with rate)
    tax_monthly = inputs.tax_annual / 12
    insurance_monthly = inputs.insurance_annual / 12
    fixed_costs = tax_monthly + insurance_monthly + inputs.hoa_monthly

    current_net_cf = effective_rent - current_monthly_pi - fixed_costs

    def net_cf_at_rate(r: float) -> float:
        new_pi = _monthly_payment(loan_amount, r, inputs.loan_term_months)
        return effective_rent - new_pi - fixed_costs

    def binary_search_rate(target_cf: float, lo: float = 0.01, hi: float = 0.15) -> float:
        # CF decreases as rate increases, so:
        # if CF > target: rate is too low → need higher rate → lo = mid
        # if CF < target: rate is too high → need lower rate → hi = mid
        for _ in range(100):
            mid = (lo + hi) / 2
            cf = net_cf_at_rate(mid)
            if cf > target_cf:
                lo = mid   # rate too low, need higher
            else:
                hi = mid   # rate too high, need lower
        return (lo + hi) / 2

    # Per spec §10.8:
    # breakeven: post-refi CF = 0
    breakeven_rate = binary_search_rate(0.0)

    # recoup: monthly_pi_savings × 24 >= remaining_balance × refi_closing_cost_pct
    # Estimate remaining balance at month 1 (close approximation for trigger rate calc)
    refi_cost_pct = 0.02
    remaining_balance = loan_amount  # conservative: use current balance
    monthly_savings_needed = remaining_balance * refi_cost_pct / 24
    # Find rate where savings = monthly_savings_needed → new_pi = current_pi - savings
    recoup_target_cf = current_net_cf + monthly_savings_needed
    recoup_rate = binary_search_rate(recoup_target_cf)

    # CF target: post-refi CF = target_monthly_cf_margin (default $150)
    cf_target_rate = binary_search_rate(150.0)

    return RefiTriggers(
        breakeven_rate=round(breakeven_rate, 4),
        recoup_rate=round(recoup_rate, 4),
        cf_target_rate=round(cf_target_rate, 4),
    )


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def underwrite(inputs: UnderwritingInputs, portfolio_cf: Optional[float] = None) -> UnderwritingResult:
    """
    Run the full underwriting engine on one property.

    Args:
        inputs: UnderwritingInputs — all from structured data sources.
        portfolio_cf: current portfolio monthly CF (overrides inputs.current_portfolio_cf).

    Returns:
        UnderwritingResult with CF trace, IRR band, gate, refi triggers.
    """
    if portfolio_cf is not None:
        inputs.current_portfolio_cf = portfolio_cf

    result = UnderwritingResult(inputs=inputs)

    # --- Loan basics ---
    result.loan_amount = inputs.purchase_price * (1 - inputs.down_pct)
    result.monthly_pi = _monthly_payment(
        result.loan_amount, inputs.interest_rate, inputs.loan_term_months
    )

    # --- 10-year CF trace ---
    result.cf_trace = _build_cf_trace(inputs)

    # --- IRR band ---
    result.irr_10yr_low = round(_irr_10yr(inputs, inputs.appr_low_pct), 4)
    result.irr_10yr_base = round(_irr_10yr(inputs, inputs.appr_base_pct), 4)
    result.irr_10yr_high = round(_irr_10yr(inputs, inputs.appr_high_pct), 4)

    # --- §11.2a Gate ---
    cf_status, sustained_month = _gate_cf_status(result.cf_trace)
    worst_cf = min(s.net_cf for s in result.cf_trace)
    month_1_cf = result.cf_trace[0].net_cf if result.cf_trace else 0.0

    # Cond 1: monthly bleed <= -$75
    cond1_pass = worst_cf >= GATE_MAX_MONTHLY_BLEED

    # Cond 2: converges AND sustained_pos_month <= 36
    cond2_pass = (
        cf_status in ("converges", "always_positive")
        and (sustained_month is not None and sustained_month <= GATE_MAX_SUSTAINED_POS_MONTH)
    )

    # Cond 3: IRR (base) >= 11.0%
    cond3_pass = result.irr_10yr_base >= GATE_MIN_IRR_BASE

    # Cond 4: portfolio carry ceiling not breached
    portfolio_total = inputs.current_portfolio_cf + month_1_cf
    cond4_pass = portfolio_total >= GATE_PORTFOLIO_CARRY_CEILING

    fail_conditions = []
    if not cond1_pass:
        fail_conditions.append("cond1")
    if not cond2_pass:
        fail_conditions.append("cond2")
    if not cond3_pass:
        fail_conditions.append("cond3")
    if not cond4_pass:
        fail_conditions.append("cond4")

    if not fail_conditions:
        verdict = "PASS"
    else:
        verdict = "FAIL"

    # Gate notes
    notes_parts = []
    if not cond3_pass:
        gap = result.irr_10yr_base - GATE_MIN_IRR_BASE
        notes_parts.append(f"Cond3: IRR base {result.irr_10yr_base:.1%} vs floor {GATE_MIN_IRR_BASE:.1%} ({gap:+.2%})")
    if not cond2_pass:
        notes_parts.append(f"Cond2: status={cf_status}, sustained_month={sustained_month}")
    if not cond1_pass:
        notes_parts.append(f"Cond1: worst_cf=${worst_cf:.0f} < threshold ${GATE_MAX_MONTHLY_BLEED:.0f}")
    if not cond4_pass:
        notes_parts.append(f"Cond4: portfolio_total=${portfolio_total:.0f} < ceiling ${GATE_PORTFOLIO_CARRY_CEILING:.0f}")

    result.gate = GateResult(
        cond1_monthly_bleed=round(worst_cf, 2),
        cond2_cf_status=cf_status,
        cond2_sustained_pos_month=sustained_month,
        cond3_irr_base=result.irr_10yr_base,
        cond4_portfolio_carry=round(portfolio_total, 2),
        cond1_pass=cond1_pass,
        cond2_pass=cond2_pass,
        cond3_pass=cond3_pass,
        cond4_pass=cond4_pass,
        verdict=verdict,
        fail_conditions=fail_conditions,
        notes=" | ".join(notes_parts),
    )

    # --- §10.8 Refi triggers ---
    result.refi = _compute_refi_triggers(inputs, result.monthly_pi)

    # --- Source flags ---
    if not inputs.rent_source or inputs.rent_source.lower() in ("", "estimate", "unknown"):
        result.flags.append("rent_source_warn")
    if not inputs.insurance_source or inputs.insurance_source.lower() in ("", "estimate", "unknown"):
        result.flags.append("insurance_estimate_warn")

    return result


# ---------------------------------------------------------------------------
# Quick summary printer
# ---------------------------------------------------------------------------

def print_summary(result: UnderwritingResult) -> None:
    """Print a human-readable one-page summary."""
    inp = result.inputs
    g = result.gate
    r = result.refi

    print(f"\n{'='*60}")
    print(f"PropIntel Underwriting Summary  [{result.spec_version}]")
    print(f"{'='*60}")
    print(f"Purchase:    ${inp.purchase_price:,.0f}  |  Down: {inp.down_pct:.0%}  |  Rate: {inp.interest_rate:.2%}")
    print(f"Rent:        ${inp.monthly_rent:,.0f}/mo  |  Vacancy: {inp.vacancy_rate:.0%}  |  Mgmt: {inp.mgmt_rate:.0%}")
    print(f"Loan:        ${result.loan_amount:,.0f}  |  PI: ${result.monthly_pi:,.2f}/mo")
    print()
    print(f"IRR Band:    Low {result.irr_10yr_low:.1%}  |  Base {result.irr_10yr_base:.1%}  |  High {result.irr_10yr_high:.1%}")
    print(f"             Appr: {inp.appr_low_pct:.0%} / {inp.appr_base_pct:.0%} / {inp.appr_high_pct:.0%}")
    print()
    print(f"§11.2a Gate: {g.verdict}")
    cond_labels = {1: "Cond1 bleed", 2: "Cond2 converge", 3: "Cond3 IRR", 4: "Cond4 carry"}
    for i, (pass_val, label) in enumerate(zip(
        [g.cond1_pass, g.cond2_pass, g.cond3_pass, g.cond4_pass],
        ["Cond1 bleed", "Cond2 converge", "Cond3 IRR", "Cond4 carry"]
    ), 1):
        status = "✓" if pass_val else "✗"
        print(f"  {status} {label}")
    if g.notes:
        print(f"  Notes: {g.notes}")
    print()
    print(f"CF Status:   {g.cond2_cf_status}  (first positive: month {g.cond2_sustained_pos_month})")
    print(f"Worst CF:    ${g.cond1_monthly_bleed:,.2f}/mo")
    print()
    print(f"§10.8 Refi:  Breakeven {r.breakeven_rate:.2%}  |  Recoup {r.recoup_rate:.2%}  |  CF=0 {r.cf_target_rate:.2%}")
    if result.flags:
        print(f"\nFlags:       {', '.join(result.flags)}")
    print(f"{'='*60}\n")
