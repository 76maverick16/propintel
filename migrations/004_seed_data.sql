-- PropIntel Seed Data
-- Migration: 004_seed_data.sql
-- Populates all known markets, anchors, properties, underwriting runs,
-- and data_points from session research as of 2026-10-17.
-- Engine outputs from v0.7.1 — all calculated values tagged accordingly.

-- ============================================================
-- MARKETS (11 target markets + 1 active)
-- ============================================================

INSERT INTO markets (name, state, county, region, thesis_confidence,
    anchor_status, headwind_scope,
    appr_low_pct, appr_base_pct, appr_high_pct, appr_calibrated, notes)
VALUES
-- Active / researched markets
('Madison County AL',   'AL', 'Madison',   'Huntsville MSA',            4,
    'operational', 'local_adjacent', 2.0, 3.0, 4.0, FALSE,
    'Primary active market. Cabot (closed). Data center + defense anchor. headwind: Birmingham DC protests (local_adjacent only).'),

('Greenville-Spartanburg SC', 'SC', 'Greenville', 'Upstate SC',         3,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'Target market. BMW / Michelin / manufacturing base. Growing tech presence.'),

('Columbus OH',         'OH', 'Franklin',  'Columbus MSA',              3,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'Target market. Intel chip fab under construction (New Albany). Large state university anchor.'),

('Richmond VA',         'VA', 'Henrico',   'Richmond MSA',              3,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'Target market. Major data center corridor (Prince William County adjacent). State capital stability.'),

('Grand Rapids MI',     'MI', 'Kent',      'Grand Rapids MSA',          3,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'Target market. Diversified manufacturing + healthcare. Tight rental supply.'),

('Ocala FL',            'FL', 'Marion',    'North Central FL',          2,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'Target market. FL supply/demand caution noted. Lower confidence until supply data confirmed.'),

('Jacksonville FL',     'FL', 'Duval',     'Jacksonville MSA',          2,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'Target market. FL supply/demand caution noted. Logistics + military anchors.'),

('Indianapolis IN',     'IN', 'Marion',    'Indianapolis MSA',          3,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'Target market. Midwest distribution hub. Amazon + pharma presence.'),

('Knoxville TN',        'TN', 'Knox',      'Knoxville MSA',             3,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'Target market. TVA + ORNL anchor. University of Tennessee. Low cost basis.'),

('Des Moines IA',       'IA', 'Polk',      'Des Moines MSA',            3,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'Target market. Major data center hub (Google, Microsoft, Meta). Insurance sector stable.'),

('Kansas City MO',      'MO', 'Jackson',   'Kansas City MSA',           3,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'Target market. Crossroads logistics + tech growth. Bi-state market (MO/KS).'),

-- TX market for Cibola
('Texas (general)',     'TX', 'Various',   'TX Statewide Watch',        2,
    'operational', 'none',           2.0, 3.0, 4.0, FALSE,
    'TX supply/demand caution noted. Cibola property analyzed here. High property tax drag.');

-- ============================================================
-- MARKET ANCHORS — Madison County AL (most researched)
-- ============================================================

INSERT INTO market_anchors (market_id, anchor_name, anchor_type, status, confidence, jobs_created, investment_usd, notes)
SELECT m.id, a.anchor_name, a.anchor_type, a.status, a.confidence, a.jobs_created, a.investment_usd, a.notes
FROM markets m
CROSS JOIN (VALUES
    ('Redstone Arsenal',        'military',       'operational', 5,  40000, NULL,
        'Largest employer in Madison County. Missile Defense Agency HQ. Secular demand anchor.'),
    ('Meta Data Center (Staggered)', 'data_center', 'operational', 5, 1500, 800000000,
        'Huntsville area. Staggered build-out. Direct housing demand driver.'),
    ('Google Data Center',      'data_center',    'announced',   4,   500, 600000000,
        'Announced Huntsville MSA. Construction timeline TBD.'),
    ('Toyota Manufacturing',    'manufacturing',  'operational', 5,  2000, NULL,
        'Huntsville plant. Long-tenure employer. Stable blue-collar demand.'),
    ('Mazda-Toyota JV',         'manufacturing',  'operational', 4,  4000, 1600000000,
        'Huntsville area. Opened 2021. Incremental population draw.')
) AS a(anchor_name, anchor_type, status, confidence, jobs_created, investment_usd, notes)
WHERE m.name = 'Madison County AL';

-- Columbus OH anchor (Intel)
INSERT INTO market_anchors (market_id, anchor_name, anchor_type, status, confidence, jobs_created, investment_usd, notes)
SELECT m.id, 'Intel Chip Fab (New Albany)', 'manufacturing', 'under_construction', 4, 7000, 20000000000,
    '$20B fab complex. Largest private investment in OH history. Will drive multi-year housing demand.'
FROM markets m WHERE m.name = 'Columbus OH';

-- Des Moines anchors
INSERT INTO market_anchors (market_id, anchor_name, anchor_type, status, confidence, jobs_created, investment_usd, notes)
SELECT m.id, a.anchor_name, a.anchor_type, a.status, a.confidence, a.jobs_created, a.investment_usd, a.notes
FROM markets m
CROSS JOIN (VALUES
    ('Google Data Center (Altoona)', 'data_center', 'operational', 5, 200,  600000000, 'Operational since 2009. Expanding.'),
    ('Microsoft Data Center',        'data_center', 'operational', 5, 300, 1000000000, 'Multiple facilities in Des Moines metro.'),
    ('Meta Data Center',             'data_center', 'operational', 5, 200,  750000000, 'Altoona campus. Operational.')
) AS a(anchor_name, anchor_type, status, confidence, jobs_created, investment_usd, notes)
WHERE m.name = 'Des Moines IA';

-- ============================================================
-- PROPERTIES
-- ============================================================

INSERT INTO properties (address, city, state, zip, market_id, nickname,
    bedrooms, bathrooms, sqft, year_built, list_price, target_price, status)
SELECT
    '116 Birds Nest Dr', 'Cabot', 'AL', '35023',
    m.id, 'Cabot',
    3, 2.0, 1650, 2018, 249900.00, 244888.00, 'closed'
FROM markets m WHERE m.name = 'Madison County AL';

INSERT INTO properties (address, city, state, zip, market_id, nickname,
    bedrooms, bathrooms, sqft, year_built, list_price, target_price, status)
SELECT
    'Cibola Dr (address TBC)', 'San Antonio', 'TX', NULL,
    m.id, 'Cibola',
    3, 2.0, NULL, NULL, 184900.00, 181999.00, 'passed'
FROM markets m WHERE m.name = 'Texas (general)';

-- ============================================================
-- UNDERWRITING RUNS — engine v0.7.1 outputs
-- ============================================================

-- CABOT run
INSERT INTO underwriting_runs (
    property_id, spec_version,
    purchase_price, down_pct, interest_rate, loan_term_months,
    monthly_rent, vacancy_rate, mgmt_rate,
    insurance_annual, tax_annual, hoa_monthly,
    appr_low_pct, appr_base_pct, appr_high_pct,
    rent_source, insurance_source,
    gate_monthly_bleed, gate_cf_status, gate_sustained_pos_month,
    gate_irr_base, gate_portfolio_carry,
    gate_verdict, gate_fail_conditions,
    irr_10yr_low, irr_10yr_base, irr_10yr_high,
    refi_breakeven_rate, refi_recoup_rate, refi_cf_target_rate,
    flags, notes
)
SELECT
    p.id, 'v0.7.1',
    244888.00, 0.200, 0.0650, 360,
    1900.00, 0.050, 0.080,
    1296.00, 1787.64, 123.96,
    2.0, 3.0, 4.0,
    'Rentcast', 'estimate',
    -4.22, 'converges', 13,
    0.1069, -187.22,
    'FAIL', ARRAY['cond3'],
    0.0838, 0.1069, 0.1279,
    0.0647, 0.0519, 0.0527,
    ARRAY['insurance_estimate_warn'],
    'Gate FAIL Cond3 only: IRR base 10.7% vs floor 11.0% (-0.31pp). Yr1 CF -$4.22/mo. Converges month 13.'
FROM properties p WHERE p.nickname = 'Cabot';

-- CIBOLA run
INSERT INTO underwriting_runs (
    property_id, spec_version,
    purchase_price, down_pct, interest_rate, loan_term_months,
    monthly_rent, vacancy_rate, mgmt_rate,
    insurance_annual, tax_annual, hoa_monthly,
    appr_low_pct, appr_base_pct, appr_high_pct,
    rent_source, insurance_source,
    gate_monthly_bleed, gate_cf_status, gate_sustained_pos_month,
    gate_irr_base, gate_portfolio_carry,
    gate_verdict, gate_fail_conditions,
    irr_10yr_low, irr_10yr_base, irr_10yr_high,
    refi_breakeven_rate, refi_recoup_rate, refi_cf_target_rate,
    flags, notes
)
SELECT
    p.id, 'v0.7.1',
    181999.00, 0.200, 0.0650, 360,
    1875.00, 0.050, 0.080,
    2496.00, 4787.04, 160.18,
    2.0, 3.0, 4.0,
    'Zillow', 'estimate',
    -93.64, 'exceeds_horizon', NULL,
    0.0836, -276.64,
    'FAIL', ARRAY['cond1','cond2','cond3'],
    0.0583, 0.0836, 0.1063,
    0.0550, 0.0519, 0.0378,
    ARRAY['insurance_estimate_warn'],
    'Gate FAIL Cond1+2+3. Yr1 CF -$93.64/mo. Never converges in 10yr horizon. High TX property tax drag ($398/mo).'
FROM properties p WHERE p.nickname = 'Cibola';

-- ============================================================
-- DATA_POINTS — tag every input/output by provenance
-- ============================================================

-- Helper: insert data points for Cabot
INSERT INTO data_points (scope, property_id, scope_label, category, field_name,
    value_numeric, unit, kind, source_name, underwriting_run_id, needs_validation, notes)
SELECT 'property', p.id, 'Cabot', dp.category, dp.field_name,
    dp.value_numeric, dp.unit, dp.kind, dp.source_name, r.id,
    dp.needs_validation, dp.notes
FROM properties p
JOIN underwriting_runs r ON r.property_id = p.id
CROSS JOIN (VALUES
    -- Verified inputs
    ('purchase',      'purchase_price',       244888.00, '$',    'verified',      'MLS / contract',       FALSE, 'Closed price per contract'),
    ('purchase',      'down_pct',             0.20,      '%',    'assumed',       NULL,                   FALSE, 'Standard 20% — matches $2M budget / 20% down strategy'),
    ('purchase',      'interest_rate',        0.065,     '%',    'verified',      'lender quote',         FALSE, '6.5% rate at time of underwriting'),
    ('purchase',      'closing_pct',          0.03,      '%',    'assumed',       NULL,                   TRUE,  'Phase 1 Blocker #1 assumption — 3% closing cost used in IRR equity base. Needs verification against actual closing statement.'),
    ('rent',          'monthly_rent',         1900.00,   '$/mo', 'agent_fetched', 'Rentcast',             TRUE,  'Single source. Spec requires corroboration (Phase 1 Blocker #4).'),
    ('expenses',      'insurance_annual',     1296.00,   '$/yr', 'assumed',       'estimate',             TRUE,  'AL midpoint estimate $108/mo. Phase 1 Blocker #3 — needs bound quote.'),
    ('expenses',      'tax_annual',           1787.64,   '$/yr', 'verified',      'AL Dept of Revenue',   FALSE, '0.73% of $244,888 = $148.97/mo. Madison County effective rate.'),
    ('expenses',      'hoa_monthly',          123.96,    '$/mo', 'assumed',       NULL,                   TRUE,  'HOA $50 + turnover reserve $73.96. HOA from listing; turnover is assumed.'),
    ('expenses',      'vacancy_rate',         0.05,      '%',    'assumed',       NULL,                   TRUE,  '5% vacancy — market assumption. Needs Madison County vacancy data.'),
    ('expenses',      'mgmt_rate',            0.08,      '%',    'assumed',       NULL,                   FALSE, '8% PM rate — standard for remote investor. Reasonable.'),
    ('appr',          'appr_base_pct',        0.03,      '%',    'assumed',       NULL,                   TRUE,  'Phase 1 Blocker #2 — placeholder 3%. Needs HPI calibration for Madison County.'),
    -- Calculated outputs
    ('underwriting',  'irr_10yr_base',        0.1069,    '%',    'calculated',    'engine v0.7.1',        FALSE, 'IRR base using down+3% closing equity. Gate threshold 11.0% (-0.31pp gap).'),
    ('underwriting',  'irr_10yr_low',         0.0838,    '%',    'calculated',    'engine v0.7.1',        FALSE, NULL),
    ('underwriting',  'irr_10yr_high',        0.1279,    '%',    'calculated',    'engine v0.7.1',        FALSE, NULL),
    ('underwriting',  'gate_monthly_bleed',   -4.22,     '$/mo', 'calculated',    'engine v0.7.1',        FALSE, 'Yr1 avg CF. Cond1 PASS (threshold -$75).'),
    ('underwriting',  'gate_cf_status',       NULL,      NULL,   'calculated',    'engine v0.7.1',        FALSE, NULL),
    ('underwriting',  'gate_sustained_month', 13,        'mo',   'calculated',    'engine v0.7.1',        FALSE, 'Converges month 13. Cond2 PASS (threshold ≤36).'),
    ('underwriting',  'refi_breakeven_rate',  0.0647,    '%',    'calculated',    'engine v0.7.1',        FALSE, 'Rate at which post-refi CF = $0'),
    ('underwriting',  'refi_recoup_rate',     0.0519,    '%',    'calculated',    'engine v0.7.1',        FALSE, 'Rate at which savings×24 ≥ balance×2%'),
    ('underwriting',  'refi_cf_target_rate',  0.0527,    '%',    'calculated',    'engine v0.7.1',        FALSE, 'Rate at which post-refi CF = $150/mo')
) AS dp(category, field_name, value_numeric, unit, kind, source_name, needs_validation, notes)
WHERE p.nickname = 'Cabot';

-- Data points for Cibola
INSERT INTO data_points (scope, property_id, scope_label, category, field_name,
    value_numeric, unit, kind, source_name, underwriting_run_id, needs_validation, notes)
SELECT 'property', p.id, 'Cibola', dp.category, dp.field_name,
    dp.value_numeric, dp.unit, dp.kind, dp.source_name, r.id,
    dp.needs_validation, dp.notes
FROM properties p
JOIN underwriting_runs r ON r.property_id = p.id
CROSS JOIN (VALUES
    ('purchase',      'purchase_price',       181999.00, '$',    'verified',      'MLS listing',          FALSE, 'Listing price used as purchase price — not contracted.'),
    ('purchase',      'down_pct',             0.20,      '%',    'assumed',       NULL,                   FALSE, 'Standard 20%'),
    ('purchase',      'interest_rate',        0.065,     '%',    'assumed',       NULL,                   TRUE,  'Same rate as Cabot assumed — needs current TX lender quote.'),
    ('purchase',      'closing_pct',          0.03,      '%',    'assumed',       NULL,                   TRUE,  '3% closing cost assumption — see IRR discrepancy task.'),
    ('rent',          'monthly_rent',         1875.00,   '$/mo', 'agent_fetched', 'Zillow',               TRUE,  'Single source. Phase 1 Blocker #4 — needs Rentcast corroboration.'),
    ('expenses',      'insurance_annual',     2496.00,   '$/yr', 'assumed',       'estimate',             TRUE,  'TX midpoint estimate $208/mo. Phase 1 Blocker #3 — needs bound quote. TX wind/hail adds significant variance.'),
    ('expenses',      'tax_annual',           4787.04,   '$/yr', 'assumed',       'estimate',             TRUE,  'Assessed $196,999 × 2.43% TX effective rate = $398.92/mo. Needs county assessor confirmation. TX tax is primary drag.'),
    ('expenses',      'hoa_monthly',          160.18,    '$/mo', 'assumed',       NULL,                   TRUE,  'HOA $87 + turnover $73.18. HOA from listing; turnover assumed.'),
    ('expenses',      'vacancy_rate',         0.05,      '%',    'assumed',       NULL,                   TRUE,  '5% vacancy — market assumption. TX supply caution noted.'),
    ('expenses',      'mgmt_rate',            0.08,      '%',    'assumed',       NULL,                   FALSE, '8% PM — standard'),
    ('appr',          'appr_base_pct',        0.03,      '%',    'assumed',       NULL,                   TRUE,  'Phase 1 Blocker #2 — placeholder. TX has high supply; appreciation may be lower.'),
    ('underwriting',  'irr_10yr_base',        0.0836,    '%',    'calculated',    'engine v0.7.1',        TRUE,  'Phase 1 Blocker #1 — discrepancy vs spec estimate 6.2%. See validation task.'),
    ('underwriting',  'irr_10yr_low',         0.0583,    '%',    'calculated',    'engine v0.7.1',        FALSE, NULL),
    ('underwriting',  'irr_10yr_high',        0.1063,    '%',    'calculated',    'engine v0.7.1',        FALSE, NULL),
    ('underwriting',  'gate_monthly_bleed',   -93.64,    '$/mo', 'calculated',    'engine v0.7.1',        FALSE, 'Cond1 FAIL: exceeds -$75 threshold.'),
    ('underwriting',  'gate_sustained_month', NULL,      'mo',   'calculated',    'engine v0.7.1',        FALSE, 'Cond2 FAIL: never converges in 10yr horizon.'),
    ('underwriting',  'refi_breakeven_rate',  0.0550,    '%',    'calculated',    'engine v0.7.1',        FALSE, NULL),
    ('underwriting',  'refi_recoup_rate',     0.0519,    '%',    'calculated',    'engine v0.7.1',        FALSE, NULL),
    ('underwriting',  'refi_cf_target_rate',  0.0378,    '%',    'calculated',    'engine v0.7.1',        FALSE, NULL)
) AS dp(category, field_name, value_numeric, unit, kind, source_name, needs_validation, notes)
WHERE p.nickname = 'Cibola';

-- ============================================================
-- VALIDATION TASKS — one per unverified assumption
-- (Cibola IRR task already seeded in migration 003)
-- ============================================================

INSERT INTO validation_tasks (
    scope, property_id, scope_label, category, headline, body,
    priority, status, created_by
)
SELECT 'property', p.id, 'Cabot',
    'insurance_estimate',
    'Cabot: get bound insurance quote (currently $1,296/yr estimate)',
    E'Engine uses $1,296/yr ($108/mo) — AL midpoint estimate.\n'
    'Action: contact 2-3 insurers for a bound quote on 116 Birds Nest Dr, Cabot AL.\n'
    'Impact: every $100/mo change in insurance moves Yr1 CF by $100/mo and IRR by ~0.3pp.',
    'high', 'open', 'system'
FROM properties p WHERE p.nickname = 'Cabot'
UNION ALL
SELECT 'property', p.id, 'Cabot',
    'rent_corroboration',
    'Cabot: get second rent estimate (currently Rentcast only)',
    E'Spec requires 2 sources. Currently: Rentcast = $1,900/mo.\n'
    'Action: pull Zillow Rent Zestimate or ApartmentList comp for comparable 3BR in Cabot/Meridianville AL.\n'
    'Impact: if second source is >5% off, flag for manual review before next run.',
    'high', 'open', 'system'
FROM properties p WHERE p.nickname = 'Cabot'
UNION ALL
SELECT 'property', p.id, 'Cabot',
    'appr_calibration',
    'Cabot: calibrate appreciation band using Madison County HPI data',
    E'Engine uses placeholder 2/3/4% band.\n'
    'Action: pull FHFA HPI for Madison County AL (5-year and 10-year CAGR).\n'
    'Cross-check with Zillow Home Value Index for Huntsville MSA.\n'
    'Update appr_base_pct in markets table and re-run underwriting.',
    'normal', 'open', 'system'
FROM properties p WHERE p.nickname = 'Cabot'
UNION ALL
SELECT 'property', p.id, 'Cibola',
    'insurance_estimate',
    'Cibola: get bound insurance quote (currently $2,496/yr estimate)',
    E'Engine uses $2,496/yr ($208/mo) — TX midpoint estimate.\n'
    'TX has significant wind/hail exposure — actual quote may be materially higher.\n'
    'Action: get quotes from State Farm, Farmers, and a TX surplus lines broker.\n'
    'Impact: every $100/mo change moves Yr1 CF by $100/mo (already at -$94/mo).',
    'high', 'open', 'system'
FROM properties p WHERE p.nickname = 'Cibola'
UNION ALL
SELECT 'property', p.id, 'Cibola',
    'tax_verification',
    'Cibola: confirm property tax with county assessor',
    E'Engine uses $4,787.04/yr ($398.92/mo) based on assessed $196,999 × 2.43% TX effective rate.\n'
    'TX property taxes are the single largest drag on Cibola CF.\n'
    'Action: look up actual assessed value and tax bill on Bexar County (or relevant county) assessor site.\n'
    'Verify: assessed value, exemptions available (homestead not applicable for rental), actual rate.',
    'blocker', 'open', 'system'
FROM properties p WHERE p.nickname = 'Cibola'
UNION ALL
SELECT 'property', p.id, 'Cibola',
    'rent_corroboration',
    'Cibola: get second rent estimate (currently Zillow only)',
    E'Spec requires 2 sources. Currently: Zillow = $1,875/mo.\n'
    'Action: pull Rentcast comp for comparable 3BR in same TX submarket.\n'
    'TX has elevated supply — rent may be under pressure.',
    'high', 'open', 'system'
FROM properties p WHERE p.nickname = 'Cibola';

-- Link validation tasks to property data points where applicable
-- (data_point_id foreign key — update after insert)
UPDATE validation_tasks vt
SET data_point_id = dp.id
FROM data_points dp
WHERE dp.scope_label = vt.scope_label
  AND dp.field_name = 'insurance_annual'
  AND vt.category = 'insurance_estimate';

UPDATE validation_tasks vt
SET data_point_id = dp.id
FROM data_points dp
WHERE dp.scope_label = vt.scope_label
  AND dp.field_name = 'monthly_rent'
  AND vt.category = 'rent_corroboration';

UPDATE validation_tasks vt
SET data_point_id = dp.id
FROM data_points dp
WHERE dp.scope_label = 'Cibola'
  AND dp.field_name = 'tax_annual'
  AND vt.category = 'tax_verification';

-- ============================================================
-- AUDIT: log task creation for all new tasks
-- ============================================================
INSERT INTO validation_audit (task_id, action, actor, note)
SELECT id, 'task_created', 'system', 'Auto-created during migration 004 seed'
FROM validation_tasks
WHERE created_by = 'system'
  AND id NOT IN (SELECT task_id FROM validation_audit WHERE action = 'task_created');

-- ============================================================
-- Link the existing Cibola IRR validation task to property
-- ============================================================
UPDATE validation_tasks
SET property_id = (SELECT id FROM properties WHERE nickname = 'Cibola')
WHERE scope_label = 'Cibola' AND category = 'irr_discrepancy';

-- ============================================================
-- Update portfolio_state signal market_id now that markets exist
-- ============================================================
UPDATE signals
SET market_id = (SELECT id FROM markets WHERE name = 'Madison County AL')
WHERE headline LIKE 'Alabama DC protests%';
