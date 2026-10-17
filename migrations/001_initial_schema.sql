-- PropIntel Initial Schema
-- Migration: 001_initial_schema.sql
-- Spec: v0.7.1
-- Applied to: Supabase project owdixnnwlezznaiyigjo

-- ============================================================
-- MARKETS
-- One row per tracked submarket. thesis_confidence drives
-- appreciation band position per §7.10.
-- ============================================================
CREATE TABLE IF NOT EXISTS markets (
    id                  SERIAL PRIMARY KEY,
    name                TEXT NOT NULL,                    -- e.g. "Madison County AL"
    state               TEXT NOT NULL,
    county              TEXT NOT NULL,
    region              TEXT,                             -- e.g. "Huntsville MSA"
    thesis_confidence   INTEGER NOT NULL DEFAULT 3        -- 1–5 per §7.10
                        CHECK (thesis_confidence BETWEEN 1 AND 5),
    anchor_status       TEXT NOT NULL DEFAULT 'operational'
                        CHECK (anchor_status IN ('operational','under_construction','announced','cancelled')),
    headwind_scope      TEXT NOT NULL DEFAULT 'none'
                        CHECK (headwind_scope IN ('none','local_adjacent','county','statewide')),
    appr_low_pct        NUMERIC(5,3) NOT NULL DEFAULT 2.0,   -- appreciation band low %
    appr_base_pct       NUMERIC(5,3) NOT NULL DEFAULT 3.0,   -- appreciation band base %
    appr_high_pct       NUMERIC(5,3) NOT NULL DEFAULT 4.0,   -- appreciation band high %
    appr_calibrated     BOOLEAN NOT NULL DEFAULT FALSE,      -- Phase 1 Blocker #2 flag
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- PROPERTIES
-- One row per property under watch. Links to its market.
-- ============================================================
CREATE TABLE IF NOT EXISTS properties (
    id                  SERIAL PRIMARY KEY,
    address             TEXT NOT NULL,
    city                TEXT NOT NULL,
    state               TEXT NOT NULL,
    zip                 TEXT,
    market_id           INTEGER REFERENCES markets(id),
    nickname            TEXT,                             -- e.g. "Cabot"
    bedrooms            INTEGER,
    bathrooms           NUMERIC(3,1),
    sqft                INTEGER,
    year_built          INTEGER,
    list_price          NUMERIC(12,2),
    target_price        NUMERIC(12,2),
    status              TEXT NOT NULL DEFAULT 'watching'
                        CHECK (status IN ('watching','under_contract','closed','passed','expired')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- UNDERWRITING_RUNS
-- One row per engine execution. Immutable — never UPDATE.
-- Captures all inputs and outputs for audit trail.
-- ============================================================
CREATE TABLE IF NOT EXISTS underwriting_runs (
    id                  SERIAL PRIMARY KEY,
    property_id         INTEGER NOT NULL REFERENCES properties(id),
    run_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    spec_version        TEXT NOT NULL DEFAULT 'v0.7.1',

    -- Inputs (all from structured sources, never LLM-derived)
    purchase_price      NUMERIC(12,2) NOT NULL,
    down_pct            NUMERIC(5,3) NOT NULL,
    interest_rate       NUMERIC(6,4) NOT NULL,
    loan_term_months    INTEGER NOT NULL DEFAULT 360,
    monthly_rent        NUMERIC(10,2) NOT NULL,
    vacancy_rate        NUMERIC(5,3) NOT NULL,
    mgmt_rate           NUMERIC(5,3) NOT NULL,
    insurance_annual    NUMERIC(10,2) NOT NULL,
    tax_annual          NUMERIC(10,2) NOT NULL,
    hoa_monthly         NUMERIC(8,2) NOT NULL DEFAULT 0,
    appr_low_pct        NUMERIC(5,3) NOT NULL,
    appr_base_pct       NUMERIC(5,3) NOT NULL,
    appr_high_pct       NUMERIC(5,3) NOT NULL,
    rent_source         TEXT,                            -- e.g. "Rentcast", "Zillow"
    insurance_source    TEXT,                            -- e.g. "bound quote", "estimate ⚠"

    -- §11.2a Gate outputs
    gate_monthly_bleed  NUMERIC(10,2),                  -- Cond 1 value
    gate_cf_status      TEXT,                            -- converges / exceeds_horizon / always_positive
    gate_sustained_pos_month INTEGER,                   -- Cond 2 month
    gate_irr_base       NUMERIC(6,4),                   -- Cond 3 value
    gate_portfolio_carry NUMERIC(10,2),                 -- Cond 4 value at time of run
    gate_verdict        TEXT NOT NULL DEFAULT 'FAIL'
                        CHECK (gate_verdict IN ('PASS','FAIL','CONDITIONAL')),
    gate_fail_conditions TEXT[],                        -- e.g. ARRAY['cond3']

    -- IRR outputs
    irr_10yr_low        NUMERIC(6,4),
    irr_10yr_base       NUMERIC(6,4),
    irr_10yr_high       NUMERIC(6,4),

    -- §10.8 Refi triggers
    refi_breakeven_rate NUMERIC(6,4),
    refi_recoup_rate    NUMERIC(6,4),
    refi_cf_target_rate NUMERIC(6,4),

    -- Notes
    flags               TEXT[],                         -- e.g. ARRAY['rent_source_warn','insurance_estimate']
    notes               TEXT
);

-- ============================================================
-- PORTFOLIO_STATE
-- Single-row snapshot of current portfolio carry.
-- Updated each time a property is added/closed/passed.
-- ============================================================
CREATE TABLE IF NOT EXISTS portfolio_state (
    id                  SERIAL PRIMARY KEY,
    snapshot_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    active_properties   INTEGER NOT NULL DEFAULT 0,
    total_monthly_cf    NUMERIC(10,2) NOT NULL DEFAULT 0,   -- current bleed (negative = cost)
    carry_ceiling       NUMERIC(10,2) NOT NULL DEFAULT -350, -- §11.2c ceiling
    carry_headroom      NUMERIC(10,2),                      -- ceiling - total_cf
    equity_deployed     NUMERIC(12,2) NOT NULL DEFAULT 0,
    notes               TEXT
);

-- Seed the initial portfolio state (Cabot closed, −$4/mo)
INSERT INTO portfolio_state (active_properties, total_monthly_cf, equity_deployed, notes)
VALUES (1, -4.00, 400000.00, 'Seed: Cabot (116 Birds Nest Dr) only. IRR base 10.6%, gate FAIL Cond3 by −40bp.');

-- ============================================================
-- SIGNALS
-- Event log for thesis driver signals and market alerts.
-- Immutable — append only.
-- ============================================================
CREATE TABLE IF NOT EXISTS signals (
    id                  SERIAL PRIMARY KEY,
    signal_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    market_id           INTEGER REFERENCES markets(id),
    property_id         INTEGER REFERENCES properties(id),
    signal_type         TEXT NOT NULL
                        CHECK (signal_type IN (
                            'thesis_anchor_change',
                            'headwind_escalation',
                            'thesis_confidence_decrement',
                            'thesis_confidence_restore',
                            'price_cut',
                            'rent_change',
                            'rate_change',
                            'portfolio_carry_warning',
                            'refi_trigger_hit',
                            'data_refresh',
                            'manual_note'
                        )),
    severity            TEXT NOT NULL DEFAULT 'info'
                        CHECK (severity IN ('info','warn','alert')),
    headline            TEXT NOT NULL,
    body                TEXT,
    source_url          TEXT,
    source_name         TEXT,
    agent_run_id        TEXT,                           -- links to GitHub Actions run
    acknowledged        BOOLEAN NOT NULL DEFAULT FALSE
);

-- Seed the Alabama DC protest signal (from prior session analysis)
INSERT INTO signals (signal_type, severity, headline, body, source_name)
VALUES (
    'headwind_escalation',
    'warn',
    'Alabama DC protests — Birmingham/Bessemer; local_adjacent for Madison County',
    'Protests against hyperscale industrial development concentrated in Jefferson and Shelby counties. headwind_scope set to local_adjacent for Madison County. No thesis_confidence decrement triggered. Escalation criteria: statewide legislation OR Alabama Power statewide surcharge.',
    'Manual entry — PropIntel seed'
);

-- ============================================================
-- MARKET ANCHORS
-- One row per thesis anchor per market (many anchors per market).
-- ============================================================
CREATE TABLE IF NOT EXISTS market_anchors (
    id                  SERIAL PRIMARY KEY,
    market_id           INTEGER NOT NULL REFERENCES markets(id),
    anchor_name         TEXT NOT NULL,                  -- e.g. "Meta DC (Staggered)"
    anchor_type         TEXT NOT NULL
                        CHECK (anchor_type IN ('data_center','military','manufacturing','employer','infrastructure')),
    status              TEXT NOT NULL DEFAULT 'operational'
                        CHECK (status IN ('operational','under_construction','announced','cancelled')),
    confidence          INTEGER NOT NULL DEFAULT 5
                        CHECK (confidence BETWEEN 1 AND 5),
    jobs_created        INTEGER,
    investment_usd      BIGINT,                         -- total announced investment $
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_properties_market     ON properties(market_id);
CREATE INDEX IF NOT EXISTS idx_uw_runs_property      ON underwriting_runs(property_id);
CREATE INDEX IF NOT EXISTS idx_signals_market        ON signals(market_id);
CREATE INDEX IF NOT EXISTS idx_signals_property      ON signals(property_id);
CREATE INDEX IF NOT EXISTS idx_signals_type_sev      ON signals(signal_type, severity);
CREATE INDEX IF NOT EXISTS idx_market_anchors_market ON market_anchors(market_id);

-- ============================================================
-- UPDATED_AT trigger helper
-- ============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_markets_updated_at
    BEFORE UPDATE ON markets
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_properties_updated_at
    BEFORE UPDATE ON properties
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
