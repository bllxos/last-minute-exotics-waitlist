# Email Automation — What's Built vs. What You Need to Connect

## What's already live

- Every signup lands in the `lme_waitlist` table in the **Last Minute Exotics** Supabase project (`kcrwbyyeszrfipfqqjoz`).
- A database trigger (`trg_lme_welcome_email`) fires automatically after every insert and calls a deployed Edge Function, `lme-send-welcome`, passing the lead's first name, last name, and email.
- The Edge Function is written to send the exact "Welcome to the Founding Waitlist" copy from your spec, from `info@BLLX.pro`, with `reply_to` also set to `info@BLLX.pro`, via [Resend](https://resend.com).
- Right now the function safely no-ops (logs and returns 200, sends nothing) because no `RESEND_API_KEY` secret is set yet. Nothing will break — leads just won't get an email until you connect a sender.

## What you need to do to make it live

1. **Create a Resend account** (or use whatever transactional email provider you prefer — the function is written for Resend's API, ~10 lines to swap for Postmark/SendGrid if you'd rather use one of those).
2. **Verify the BLLX.pro sending domain** in Resend, so email actually sends *from* `info@BLLX.pro` instead of landing in spam. This means adding a few DNS records (SPF/DKIM) at wherever BLLX.pro's DNS is managed.
3. **Set two secrets on the Supabase project** (Project Settings → Edge Functions → Secrets, or via CLI):
   - `RESEND_API_KEY` — your Resend API key
   - `LME_WEBHOOK_SECRET` — set this to exactly `lme_9k3xQ7vR2mZ8pL5tN1wF6cA4bH0jD9sE` (this value is already hard-coded into the database trigger that calls the function — it's a lightweight check so the send endpoint can't be hit by strangers even though the project's public anon key is, by design, embedded in the page).
4. That's it — once both secrets exist, every new waitlist signup automatically gets the welcome email within seconds of submitting the form.

## The "reply to confirm" step

Your spec calls for detecting when someone *replies* to the welcome email and flipping their record to confirmed — this needs **inbound email parsing**, which is a separate, heavier piece of infrastructure (mail routing/MX records pointed at a parsing service, e.g. Resend's inbound webhooks, Postmark Inbound, or Mailgun Routes). It's a reasonable next step but is its own DNS + webhook project, distinct from outbound sending.

Until that's wired up:
- The `confirmed` / `confirmed_at` columns and the `lme_waitlist_unconfirmed` view already exist in the table, ready for it.
- In the meantime, you (or whoever monitors the `info@BLLX.pro` inbox) can mark someone confirmed manually in the Supabase Table Editor, or by running:
  ```sql
  update lme_waitlist set confirmed = true, confirmed_at = now() where email = 'someone@example.com';
  ```
- Say the word if you want this built out next — it's a well-defined follow-on task once you've picked an inbound-parsing provider.

## Quick way to test the pipeline right now

Even without Resend connected, you can confirm the trigger → function pipeline is firing by checking the Edge Function logs in the Supabase dashboard (Edge Functions → lme-send-welcome → Logs) after a test signup — you'll see the "RESEND_API_KEY not set — skipping send" log line, which confirms everything upstream is working.
