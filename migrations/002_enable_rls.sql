-- PropIntel RLS Migration (DO NOT APPLY until dashboard auth is implemented)
-- Enabling RLS without policies blocks ALL access including the dashboard.
-- Apply this only after adding appropriate policies for your service role.
--
-- For a single-user system using service_role key: RLS is bypassed entirely
-- by the service role, so enabling it is optional until you add users/anon access.

ALTER TABLE "public"."markets"           ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."properties"        ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."underwriting_runs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."portfolio_state"   ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."signals"           ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."market_anchors"    ENABLE ROW LEVEL SECURITY;

-- Example policies (customize as needed):
-- CREATE POLICY "service role full access" ON markets USING (true);
