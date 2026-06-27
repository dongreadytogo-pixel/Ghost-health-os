-- Ghost Health OS — M1 schema: normalized health samples.
--
-- This table is the persistence target behind HealthSampleRepository. It stores
-- the canonical, provider-agnostic sample as JSONB plus the columns we filter
-- on (user, date, kind, provider). The `sample_key` column mirrors the domain's
-- `sampleKey()` and carries a UNIQUE constraint, so ingestion is idempotent via
-- ON CONFLICT — re-syncing a date range updates in place instead of duplicating.

create table if not exists health_samples (
  id           uuid primary key default gen_random_uuid(),
  user_id      text        not null,
  sample_key   text        not null,
  kind         text        not null check (kind in ('sleep','recovery','workout','blood_sugar')),
  provider     text        not null,
  sample_date  date        not null,
  recorded_at  timestamptz not null,
  payload      jsonb       not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint health_samples_sample_key_unique unique (sample_key)
);

-- Primary read path: a user's samples within a date range, newest stages first.
create index if not exists health_samples_user_date_idx
  on health_samples (user_id, sample_date);

create index if not exists health_samples_user_kind_date_idx
  on health_samples (user_id, kind, sample_date);

-- Keep updated_at honest on every upsert.
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists health_samples_set_updated_at on health_samples;
create trigger health_samples_set_updated_at
  before update on health_samples
  for each row execute function set_updated_at();

-- Row-level security: users own their data (spec: "Users own their data").
alter table health_samples enable row level security;

drop policy if exists health_samples_owner_rw on health_samples;
create policy health_samples_owner_rw on health_samples
  for all
  using (user_id = auth.uid()::text)
  with check (user_id = auth.uid()::text);

-- Idempotent upsert used by the Supabase repository implementation:
--
--   insert into health_samples (...)
--   values (...)
--   on conflict (sample_key)
--   do update set payload = excluded.payload,
--                 recorded_at = excluded.recorded_at;
