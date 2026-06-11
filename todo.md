## What to do, mapped to your OWASP list:

1. A01:2025 - Broken Access Control
  - Replace allow-all RLS with owner-only policies.
  - Add a user ownership column on games (for example, owner_id linked to auth user id).
  - Enforce select/update/delete where owner_id equals auth user id.
  - Keep anon key in frontend, but rely on strict RLS for protection.

2. A07:2025 - Authentication Failures
  - Require sign-in before cloud save/load/delete.
  - Disable anonymous write operations.
  - Add session timeout and re-auth for destructive actions (delete).

3. A02:2025 - Security Misconfiguration
  - Remove demo/open policy from production migrations.
  - Use separate Supabase projects for dev and prod.
  - Restrict allowed redirect URLs and auth providers.
  - Add strict frontend headers on hosting (CSP, frame-ancestors none, X-Content-Type-Options, Referrer-Policy).

4. A05:2025 - Injection - DONE
  - Keep using Supabase query builder (good).
  - Add server-side validation constraints in SQL for lengths and allowed values:
    - team names max length, non-empty
    - score and shot counts non-negative
    - score_events schema validation (timestamp format and enum for team)

5. A10:2025 - Mishandling of Exceptional Conditions
  - Stop showing raw database error messages directly to users in App.vue; map to safe user-friendly text.
  - Add request timeout/retry handling and a clear fallback state when Supabase is unavailable.
  - Add rate limiting for write operations (via edge function or proxy).

6. A09:2025 - Security Logging and Alerting Failures
  - Enable and review Supabase audit logs for table writes and auth events.
  - Add alerts for unusual patterns (high delete rate, repeated denied RLS attempts).
  - Record key client events (save/delete failures) with non-sensitive metadata.

7. A03:2025 - Software Supply Chain Failures
  - Commit and enforce lockfile in CI.
  - Run npm audit in CI and block high/critical on production branch.
  - Enable Dependabot/Renovate for regular dependency updates.
  - Pin deployment action versions if using CI deploy.

8. A08:2025 - Software or Data Integrity Failures
  - Protect main branch with required checks before deploy.
  - Use signed commits/tags for releases.
  - Prefer CI-driven deploy over local npm run deploy from developer machine.

9. A04:2025 - Cryptographic Failures
  - Ensure all access is HTTPS only.
  - Keep secrets out of repo and rotate keys periodically.
  - If any user-sensitive data is added later, classify and encrypt where needed.

10. A06:2025 - Insecure Design
  - Define simple threat model for this app:
    - Who can read/write games
    - What happens if a key leaks
    - Abuse cases (bulk deletion, spam writes)
  - Add security acceptance checks before new features.