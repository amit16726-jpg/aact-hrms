-- Minimal stand-in for the Supabase platform objects, for running the migrations
-- and tests on plain Postgres. NOT applied to Supabase.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

create schema if not exists extensions;
create schema if not exists auth;
create schema if not exists storage;
grant usage on schema public, storage, extensions to anon, authenticated;
grant usage on schema auth to anon, authenticated;

create table if not exists auth.users (
  instance_id uuid,
  id uuid primary key,
  aud varchar, role varchar,
  email text,
  encrypted_password varchar,
  email_confirmed_at timestamptz,
  raw_app_meta_data jsonb,
  raw_user_meta_data jsonb default '{}'::jsonb,
  confirmation_token varchar, recovery_token varchar, email_change_token_new varchar, email_change varchar,
  created_at timestamptz default now(),
  updated_at timestamptz
);
create table if not exists auth.identities (
  id uuid primary key default gen_random_uuid(),
  provider_id text not null, user_id uuid not null references auth.users(id), identity_data jsonb not null,
  provider text not null, last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz,
  unique (provider_id, provider)
);

create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant execute on function auth.uid() to anon, authenticated;

create table if not exists storage.buckets (
  id text primary key, name text, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[]
);
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text,
  owner uuid,
  created_at timestamptz default now()
);
alter table storage.objects enable row level security;
grant select, insert on storage.objects to authenticated;

-- Supabase's default: functions in public executable by anon/authenticated
alter default privileges in schema public grant execute on functions to anon, authenticated;

-- two-step sign-in (as on Supabase): factors and the JWT claims of the request
create table if not exists auth.mfa_factors (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id), friendly_name text,
  factor_type text not null default 'totp', status text not null default 'unverified', created_at timestamptz default now(), updated_at timestamptz default now()
);
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
grant execute on function auth.jwt() to anon, authenticated;
