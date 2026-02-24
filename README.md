# NStyle Sentinel: High-Integrity Booking Ecosystem

**NStyle Sentinel** is a high-integrity, multi-platform booking ecosystem designed for Nstyle by Toney. Its defining feature is a **"Dual-Handshake Confirmation"** workflow: an AI agent (orchestrated via Twilio or VAPI) greets clients and proposes appointment times; once a client agrees, a push notification is sent to Toney's app. Toney must manually approve the appointment before the system fires a confirmation webhook back to the client.

"Built on The Caris Stack Protocol, strictly adhering to the following mandated blueprints:
• Automated Governance: Engineered alongside an AST-Aware Semantic Bundler and automated Pre-Flight Audit routing for AI agents.
• The 'Horror Path' Defense: Remote calls are wrapped in active recovery policies, and client drafts are persisted via local storage before mutation to prevent data loss during upstream failures.
• Design Token Enforcement: The UI rejects generic defaults, utilizing strictly enforced 'Exponential Typography' scaling and a locked 'Bold' visual profile."

---

## Core System Architecture

Here is how the system was built across its core layers:

### 1. The Database Layer (PostgreSQL / Supabase)

To handle high concurrency and prevent millisecond race conditions (e.g., two AI agents booking the same slot), the database was hardened with an **optimistic locking pattern** using a version integer. The schema includes tables for `clients`, `appointments`, and `availability_overrides`. To ensure highly performant reads for the 12-month calendar dashboard, it relies on B-Tree indexing and **Keyset Pagination** rather than standard linear offset scans.

### 2. The Backend Middleware (Node.js)

The server-side logic acts as a "Sentinel" to orchestrate the AI agent's Book, Cancel, and Modify requests while enforcing Toney's approval-first rule.

*   **Conflict Resolution:** To keep cyclomatic complexity low, scheduling logic was decoupled into a discrete `AvailabilityService` that performs "Look-Ahead Queries" to automatically find the next free opening when a requested slot is booked.
*   **Horror Path Hardening:** The API uses `p-retry` to automatically handle transient database failures and features tiered audit-route signature verification to reject unauthorized or oversized payloads (poisoned JSON blobs).

### 3. The Frontend Client (Flutter)

The frontend is a cross-platform application utilizing Riverpod for global state management and a custom 12-month `SfCalendar` dashboard.

*   **Aesthetic Strictness (The NStyle Profile):** The UI enforces a bold "Exponential Typography" scale and a locked Dark, Gold, and Steel color palette. Crucially, it strictly enforces a **44px minimum touch target** designed specifically for a barber’s fast-paced, hands-free environment, explicitly rejecting requests for smaller 18pt targets. A custom splash screen was also developed to initialize the secure system.
*   **State Restoration:** To prevent data loss during network drops, the app uses a `DraftStore` interface backed by `shared_preferences`. This temporarily saves Toney's approval inputs locally *before* attempting the network mutation, allowing for active recovery if the request fails.
*   **Zero-Cost Prototyping:** The current frontend is wired to a **Mock Sentinel repository**. This architectural "Inversion of Control" allows Toney to test a fully interactive, clickable prototype (complete with simulated approval queues and notifications) without incurring any external database or telephony API costs.

### 4. Automated Verification (Testing)

Per the stack's "Iron Law of TDD," the system includes rigorous automated testing. A Jest test harness was built for the Node.js backend to verify its handling of race conditions and mid-transaction database collapses. On the Flutter side, a Patrol E2E integration test simulates a network collapse to guarantee the `DraftStore` successfully recovers the pending appointment state.

---

## Next Steps / Known Gaps

While the initial build successfully passed CI hard gates and was merged into GitHub, the next phases of development will involve swapping the mock architecture for production services. This includes wiring up the real Supabase client, integrating actual Twilio/VAPI webhook routing, implementing Firebase Cloud Messaging (FCM) or APNs for push notifications, and adding formal Auth/RBAC to secure Toney's approval endpoint.


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
