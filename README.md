# PropIntel

Market-intelligence and underwriting system for remote real estate investment.

## Architecture

| Layer | Path | Purpose |
|---|---|---|
| Engine | `engine/` | Python underwriting core — CF trace, IRR band, §11.2a gate |
| Agent | `agent/` | Weekly scheduled agent — fetches signals, runs engine, writes to Supabase |
| Dashboard | `dashboard/` | FastAPI + HTML/JS UI — Watchlist, Property Deep Dive, Market Health |
| Migrations | `migrations/` | Versioned SQL schema for Supabase |

## Design Principles

**#1 — Agents extract and narrate. Code computes.**
No number that enters a calculation may originate from a language model.
All inputs to `underwriting.py` come from structured data sources (MLS, Rentcast, BLS, census).

## Stack

- Python 3.12
- Supabase (Postgres) — property/market/signal store
- FastAPI — dashboard API
- GitHub Actions — weekly scheduler
- Render.com — dashboard hosting

## Spec

Requirements locked at v0.7.1 in `requirements.md` (not committed — internal doc).
