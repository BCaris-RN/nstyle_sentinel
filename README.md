# nstyle_sentinel

NStyle Sentinel is a high-integrity booking workflow prototype for NStyle by Toney.

This repository now includes:

- Flutter (Riverpod) approval dashboard with a 12-month `SfCalendar` view
- `shared_preferences` draft recovery for Toney's manual approval step
- Node.js Sentinel middleware for AI-agent `book/cancel/modify` orchestration
- PostgreSQL schema for `clients`, `appointments`, and `availability_overrides`

## Quick Start (Flutter)

```bash
flutter pub get
flutter run
```

## Backend Sentinel

See `backend/sentinel/` for the Node middleware package and `database/schema/nstyle_sentinel.sql` for the database schema.
