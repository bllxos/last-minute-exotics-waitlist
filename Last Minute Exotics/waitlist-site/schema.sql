-- Last Minute Exotics — Waitlist schema
-- Live Supabase project: "Last Minute Exotics" (kcrwbyyeszrfipfqqjoz)
create extension if not exists pgcrypto;

create table if not exists lme_waitlist (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  first_name text,
  last_name text,
  name text not null,                 -- combined "first last", kept for backward compatibility
  email text not null unique,
  phone text,
  city text,                          -- legacy, unused in current 5-question flow
  quiz_brand text,                    -- "If you could drive one today..."
  quiz_reason text,                   -- "What would most likely bring you to LME?"
  quiz_priorities text[],             -- "What matters most..." — up to 2 selections
  quiz_frequency text,                -- "How often do you rent luxury/exotic vehicles?"
  quiz_founder_interest text,         -- "If offered Founder Access, what interests you most?"
  quiz_action text,                   -- legacy, unused in current flow
  referral_code text not null unique,
  referred_by text,
  entries int not null default 1,
  source text default 'direct',       -- 'direct' | 'referral'
  qr_source text default 'Poster',    -- 'Poster' | 'Referral'
  location text default 'La Jolla Launch',
  tags text[] default array['Founding Waitlist'],
  confirmed boolean not null default false,   -- true once lead replies to the welcome email
  confirmed_at timestamptz,
  user_agent text
);

create index if not exists idx_lme_waitlist_referred_by on lme_waitlist(referred_by);
create index if not exists idx_lme_waitlist_created_at on lme_waitlist(created_at);
create index if not exists idx_lme_waitlist_confirmed on lme_waitlist(confirmed);

alter table lme_waitlist enable row level security;

-- Public can insert their own signup, nothing else.
create policy "public insert waitlist"
  on lme_waitlist for insert
  to anon
  with check (true);

-- Trigger: crediting the referrer with +1 entry when someone signs up using their code.
create or replace function lme_credit_referral()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.referred_by is not null then
    update lme_waitlist
      set entries = entries + 1
      where referral_code = new.referred_by;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lme_credit_referral on lme_waitlist;
create trigger trg_lme_credit_referral
  after insert on lme_waitlist
  for each row execute function lme_credit_referral();

-- RPC: safely return a signup's own stats (entries + waitlist position) without exposing the table via SELECT.
create or replace function lme_get_signup_stats(p_code text)
returns table(entries int, position bigint)
language sql
security definer
set search_path = public
as $$
  select w.entries,
         (select count(*) from lme_waitlist w2 where w2.created_at <= w.created_at)
  from lme_waitlist w
  where w.referral_code = p_code;
$$;

revoke all on function lme_get_signup_stats(text) from public;
grant execute on function lme_get_signup_stats(text) to anon;

revoke all on function lme_credit_referral() from public;

-- ---------------------------------------------------------------------------
-- Admin views for ops (query in Supabase Table Editor / SQL Editor)
-- ---------------------------------------------------------------------------

-- Leads awaiting reply-confirmation
create or replace view lme_waitlist_unconfirmed as
  select id, created_at, first_name, last_name, email, phone, referral_code, entries
  from lme_waitlist
  where confirmed = false
  order by created_at asc;

-- Mark a lead confirmed once their reply email is received (manual for now — see
-- waitlist-site/EMAIL_SETUP.md for wiring this to an inbound-email webhook).
-- Example:
--   update lme_waitlist set confirmed = true, confirmed_at = now() where email = 'someone@example.com';
