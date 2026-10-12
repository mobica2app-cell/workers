# MOOD AI — read-only orders assistant

This package intentionally contains **no SQL migration**, does not change `supabase/config.toml`, and does not edit the existing login implementation.

## What it adds
- A floating MOOD AI button in `MainShell`, shown only when the locally logged-in employee role is exactly `head` (and not guest mode).
- `lib/pages/ai_assistant_page.dart`, a bilingual chat screen.
- `supabase/functions/mood-ai/index.ts`, which verifies the submitted credentials against the existing `employees_auth` table, requires an active `head`, reads only `sap_main_orders` and `sap_done_orders` for AI business data, then calls Gemini.
- The Gemini API key and Supabase service-role key remain in Edge Function secrets, not in Flutter.

## Important security notes
- The original login code is untouched. This function uses the existing username/password column as it currently exists.
- Do **not** put `GEMINI_API_KEY` or `SUPABASE_SERVICE_ROLE_KEY` in Flutter or commit them to source control.
- This implementation reads at most 1,500 rows from each table per question and uses an explicit column allowlist. It can therefore answer based on a limited sample if a table has more rows; the assistant is instructed not to present sample totals as guaranteed global totals.
- The floating button is a UI restriction; the Edge Function independently checks credentials and exact `head` role.
- The Edge Function receives the password over HTTPS and compares it to the existing plaintext password column because the current login implementation does the same. This preserves current behavior but is not ideal password storage. No password/schema changes are made here.
- Supabase's normal Edge Function JWT verification is left at its default; no `config.toml` override is included.
- Review before production. I could not deploy to your Supabase project or run a Flutter build from this `lib`-only upload.

## Deploy
From the root of your full Flutter project, copy the included `lib/pages/ai_assistant_page.dart` and `lib/pages/main_shell.dart` into your project (backup your current `main_shell.dart` first). Copy `supabase/functions/mood-ai/index.ts` to the same path in your project.

Set secrets in Supabase Dashboard → Edge Functions → Secrets:
- `GEMINI_API_KEY` = your Gemini API key
- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are normally supplied by Supabase to Edge Functions.
- Optional `GEMINI_MODEL` = `gemini-2.5-flash`

Then deploy only this function:
```powershell
supabase functions deploy mood-ai --project-ref tcztkkexgzxlurvhibmc
```
This deploys an Edge Function only. It does not push a database migration or change the login implementation.

## Verify
1. Sign in normally with an active `head` account.
2. Click the MOOD AI floating button.
3. Ask: `Summarize current orders` or `لخص حالة الطلبات الحالية`.
4. Test a non-head account: it should not see the button and the function should return HTTP 403.
