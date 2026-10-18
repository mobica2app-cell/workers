# MOOD security rollout — schema-compatible update

## What this package changes

- `mood-auth` now uses the existing `employees_auth.password` column. It does not select or require `password_hash` and does not require a database migration.
- Legacy plaintext passwords are accepted once and upgraded to bcrypt hashes in the existing `password` column after a successful login. New/changed passwords are stored as bcrypt hashes in that same column.
- Flutter login uses the `mood-auth` function and stores only the issued session token in `sessionStorage`; it no longer stores a password in `localStorage`.
- MOOD AI uses the server-issued session token.
- Employee writes are limited to manager roles; employees can change only their own password.

## Important existing-schema compatibility

Your current `employees_auth` table has a `password varchar NOT NULL` column and no `password_hash` column. This update is designed for that schema. **Do not apply the old migration `202610110001_secure_manual_auth_and_ai.sql` from previous packages**: it adds `password_hash`, attempts to set `password = NULL`, and changes RLS/permissions. That migration is not needed for this version and is incompatible with `password NOT NULL` as currently defined.

## Deploy

1. Back up the project before deploying.
2. Confirm Edge Function secrets `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `MOOD_SESSION_SECRET` are configured. `MOOD_SESSION_SECRET` must be a random value at least 32 characters long. Never put the service-role key or session secret in Flutter.
3. Ensure `supabase/config.toml` includes `verify_jwt = false` for `mood-auth` and `mood-ai`; these functions validate the MOOD session token themselves.
4. Deploy from the extracted `mood_security_work` folder:

   ```powershell
   supabase functions deploy mood-auth --no-verify-jwt
   supabase functions deploy mood-ai --no-verify-jwt
   ```

5. Rebuild and test the Flutter app. Test login, employee directory, create/update employee, self password change, AI chat, and logout.

## Security note

This avoids storing plaintext passwords after a successful login, but the `password` column temporarily contains legacy plaintext values for users who have not logged in since deployment. Ask all employees to sign in once, and consider forcing a password reset. Keep `employees_auth` inaccessible directly to `anon`/`authenticated` clients through correctly configured RLS/grants, but do not apply unrelated schema changes without reviewing their effects.

## Remaining work

The current Flutter app still makes direct PostgREST calls to business tables. This function does not automatically secure those other tables. Inventory and migrate each business-table operation before enabling restrictive RLS there.
