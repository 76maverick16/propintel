-- PropIntel Data Integrity Migration
-- Migration: 003_data_integrity.sql
-- Spec: v0.7.1
-- Adds: data_points, validation_tasks, validation_audit

-- ============================================================
-- DATA_POINTS
-- Every input and output used in underwriting, tagged by
-- provenance. One row per named datum per entity.
-- Scope: property | community | county | city | market
-- Kind:
--   verified     — confirmed from primary source (tax record,
--                  bound quote, MLS, signed lease)
--   agent_fetched — pulled by scheduled agent from a live API
--                  (Rentcast, BLS, FRED, Zillow); trusted but
--                  not human-verified
--   calculated   — engine output derived from other data points
--                  (IRR, CF, gate verdict)
--   assumed      — placeholder used in calculation, no source
--                  (e.g. closing_cost_pct=3%, maint curve)
-- ============================================================
CREATE TABLE IF NOT EXISTS data_points (
    id              SERIAL PRIMARY KEY,

    -- What entity does this datum describe?
    scope           TEXT NOT NULL
                    CHECK (scope IN ('property','community','county','city','market')),
    property_id     INTEGER REFERENCES properties(id),
    market_id       INTEGER REFERENCES markets(id),
    scope_label     TEXT,                           -- e.g. "Cabot", "Madison County AL", "Huntsville"

    -- What is the datum?
    category        TEXT NOT NULL,                  -- e.g. "rent", "insurance", "irr", "appr_band"
    field_name      TEXT NOT NULL,                  -- e.g. "monthly_rent", "irr_10yr_base", "appr_base_pct"
    value_numeric   NUMERIC,                        -- use for numbers
    value_text      TEXT,                           -- use for strings / labels
    unit            TEXT,                           -- e.g. "$/mo", "%", "months"

    -- Provenance
    kind            TEXT NOT NULL
                    CHECK (kind IN ('verified','agent_fetched','calculated','assumed')),
    source_name     TEXT,                           -- e.g. "Rentcast", "AL Dept of Revenue", "engine v0.7.1"
    source_url      TEXT,
    fetched_at      TIMESTAMPTZ,                    -- when agent pulled it (null if manual/assumed)
    underwriting_run_id INTEGER REFERENCES underwriting_runs(id),  -- links calculated values to a run

    -- Verification state
    needs_validation BOOLEAN NOT NULL DEFAULT FALSE,  -- true = task should exist in validation_tasks
    validated       BOOLEAN NOT NULL DEFAULT FALSE,
    validated_by    TEXT,                           -- email or name of approver
    validated_at    TIMESTAMPTZ,
    override_value  NUMERIC,                        -- if approver overrides, engine uses this
    override_note   TEXT,

    -- Notes
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- VALIDATION_TASKS
-- Manual validation queue. Created automatically by the engine
-- or agent when a datum is assumed, unverified, or flagged as
-- discrepant. You resolve tasks here; the audit log captures
-- every action.
-- Scope mirrors data_points; a task can cover a data_point or
-- a freeform concern (e.g. "reconcile Cibola IRR 6.2% vs 8.4%").
-- ============================================================
CREATE TABLE IF NOT EXISTS validation_tasks (
    id              SERIAL PRIMARY KEY,

    -- Scope
    scope           TEXT NOT NULL
                    CHECK (scope IN ('property','community','county','city','market','portfolio')),
    property_id     INTEGER REFERENCES properties(id),
    market_id       INTEGER REFERENCES markets(id),
    scope_label     TEXT,                           -- human-readable: "Cibola", "Madison County AL"

    -- Link to the specific data point (optional — task can be freeform)
    data_point_id   INTEGER REFERENCES data_points(id),

    -- Task description
    category        TEXT NOT NULL,                  -- e.g. "irr_discrepancy", "insurance_estimate",
                                                    --      "rent_corroboration", "appr_calibration"
    headline        TEXT NOT NULL,                  -- one-line summary shown in dashboard
    body            TEXT,                           -- full description, what to check, what to provide

    -- Priority
    priority        TEXT NOT NULL DEFAULT 'normal'
                    CHECK (priority IN ('blocker','high','normal','low')),

    -- Values in question (makes the task self-contained without joining data_points)
    engine_value    NUMERIC,                        -- what the engine calculated
    engine_value_label TEXT,                        -- e.g. "IRR base (engine v0.7.1)"
    reference_value NUMERIC,                        -- alternative / expected value
    reference_label TEXT,                           -- e.g. "spec estimate", "prior spreadsheet"
    discrepancy_pct NUMERIC,                        -- abs(engine - reference) / reference

    -- Resolution
    status          TEXT NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open','in_review','resolved','overridden','dismissed')),
    resolution_note TEXT,                           -- what you found / decided
    resolved_by     TEXT,
    resolved_at     TIMESTAMPTZ,

    -- Traceability
    created_by      TEXT NOT NULL DEFAULT 'system', -- 'system', 'agent', or your name
    underwriting_run_id INTEGER REFERENCES underwriting_runs(id),

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- VALIDATION_AUDIT
-- Immutable append-only log of every action taken on a
-- validation task or data point override.
-- Never UPDATE or DELETE rows here.
-- ============================================================
CREATE TABLE IF NOT EXISTS validation_audit (
    id              SERIAL PRIMARY KEY,
    event_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- What was acted on
    task_id         INTEGER REFERENCES validation_tasks(id),
    data_point_id   INTEGER REFERENCES data_points(id),

    -- What happened
    action          TEXT NOT NULL
                    CHECK (action IN (
                        'task_created',
                        'task_assigned',
                        'status_changed',
                        'value_overridden',
                        'value_confirmed',
                        'task_dismissed',
                        'note_added',
                        'agent_refetch'
                    )),
    actor           TEXT NOT NULL DEFAULT 'system',     -- 'system', 'agent', or your name
    from_value      TEXT,                               -- previous value (serialized)
    to_value        TEXT,                               -- new value (serialized)
    note            TEXT,
    agent_run_id    TEXT                                -- GitHub Actions run id if agent-triggered
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_dp_property      ON data_points(property_id);
CREATE INDEX IF NOT EXISTS idx_dp_market        ON data_points(market_id);
CREATE INDEX IF NOT EXISTS idx_dp_category      ON data_points(category, field_name);
CREATE INDEX IF NOT EXISTS idx_dp_needs_val     ON data_points(needs_validation) WHERE needs_validation = TRUE;
CREATE INDEX IF NOT EXISTS idx_dp_kind          ON data_points(kind);

CREATE INDEX IF NOT EXISTS idx_vtask_property   ON validation_tasks(property_id);
CREATE INDEX IF NOT EXISTS idx_vtask_status     ON validation_tasks(status);
CREATE INDEX IF NOT EXISTS idx_vtask_priority   ON validation_tasks(priority, status);
CREATE INDEX IF NOT EXISTS idx_vtask_category   ON validation_tasks(category);

CREATE INDEX IF NOT EXISTS idx_vaudit_task      ON validation_audit(task_id);
CREATE INDEX IF NOT EXISTS idx_vaudit_dp        ON validation_audit(data_point_id);
CREATE INDEX IF NOT EXISTS idx_vaudit_event_at  ON validation_audit(event_at);

-- ============================================================
-- UPDATED_AT triggers
-- ============================================================
CREATE TRIGGER trg_dp_updated_at
    BEFORE UPDATE ON data_points
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_vtask_updated_at
    BEFORE UPDATE ON validation_tasks
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- SEED: Cibola IRR discrepancy — first manual validation task
-- Created by system; you resolve it when you reconcile the
-- 6.2% spec estimate vs 8.4% engine output.
-- ============================================================
INSERT INTO validation_tasks (
    scope, scope_label, category, headline, body,
    priority, engine_value, engine_value_label,
    reference_value, reference_label, discrepancy_pct,
    status, created_by
) VALUES (
    'property',
    'Cibola',
    'irr_discrepancy',
    'Cibola IRR: engine 8.4% vs spec estimate 6.2% — reconcile equity base assumption',
    E'Engine produces IRR_base = 8.4% using equity_invested = purchase_price × (down_pct + closing_pct).\n'
    'Spec requirements.md cites "~6.2%" with no sourcing note.\n\n'
    'Most likely cause: spec estimate used down-only equity (20% × $181,999 = $36,400) rather than '
    'down + 3% closing costs ($181,999 × 23% = $41,860).\n\n'
    'To resolve:\n'
    '  1. Find the original spreadsheet or calculation that produced 6.2%.\n'
    '  2. Check whether closing costs were included in the equity base.\n'
    '  3. If down-only: update spec comment to "~8.4% (down+closing)" and dismiss this task.\n'
    '  4. If something else: override engine closing_pct or flag as Phase 1 Blocker.',
    'blocker',
    0.084, 'IRR base — engine v0.7.1 (down + 3% closing costs)',
    0.062, 'spec requirements.md estimate (source unverified)',
    0.355,  -- (8.4 - 6.2) / 6.2 = 35.5% discrepancy
    'open',
    'system'
);

-- Log the task creation in the audit trail
INSERT INTO validation_audit (task_id, action, actor, note)
VALUES (
    (SELECT id FROM validation_tasks WHERE headline LIKE 'Cibola IRR%' LIMIT 1),
    'task_created',
    'system',
    'Auto-created during migration 003; engine v0.7.1 IRR cross-check (Phase 1 Blocker #1)'
);
