-- ============================================================
-- VIC-CONNECT — MIGRATION V4
-- ============================================================
-- À COPIER ENTIÈREMENT dans Supabase > SQL Editor > New query.
-- Cette migration est non destructive : elle ne supprime aucune
-- table ni aucune donnée existante.
--
-- Ajout principal : protection par mot de passe de la création
-- des nouvelles classes depuis l'interface Super Admin.
-- Mot de passe configuré : Jesuistyros007@
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ------------------------------------------------------------
-- 1. Paramètre de sécurité privé
-- ------------------------------------------------------------
create table if not exists public.admin_security_settings (
  setting_key text primary key,
  class_creation_password_hash text not null,
  updated_at timestamptz not null default now()
);

alter table public.admin_security_settings enable row level security;

drop policy if exists admin_security_settings_no_direct_access
on public.admin_security_settings;

create policy admin_security_settings_no_direct_access
on public.admin_security_settings
for all
to anon, authenticated
using (false)
with check (false);

-- Le mot de passe n'est pas enregistré en clair : seul son hash est stocké.
insert into public.admin_security_settings(
  setting_key,
  class_creation_password_hash
)
values (
  'class_creation',
  extensions.crypt('Jesuistyros007@', extensions.gen_salt('bf'))
)
on conflict (setting_key) do nothing;


-- ------------------------------------------------------------
-- 2. Création d'une classe protégée
-- ------------------------------------------------------------
create or replace function public.admin_create_class(
  p_name text,
  p_code text,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
  v_id uuid;
begin

  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if nullif(trim(p_name), '') is null then
    raise exception 'Nom de la classe obligatoire.';
  end if;

  if nullif(trim(p_code), '') is null then
    raise exception 'Code de la classe obligatoire.';
  end if;

  select class_creation_password_hash
  into v_hash
  from public.admin_security_settings
  where setting_key = 'class_creation';

  if v_hash is null then
    raise exception 'Protection de création des classes non configurée.';
  end if;

  if p_password is null
     or extensions.crypt(p_password, v_hash) <> v_hash then
    raise exception 'Mot de passe incorrect. Création de la classe refusée.';
  end if;

  insert into public.classes(name, code)
  values (trim(p_name), trim(p_code))
  returning id into v_id;

  return jsonb_build_object(
    'success', true,
    'class_id', v_id,
    'name', trim(p_name),
    'code', trim(p_code)
  );

exception
  when unique_violation then
    raise exception 'Cette classe ou ce code existe déjà.';
end;
$$;

grant execute on function public.admin_create_class(text, text, text)
to authenticated;


-- ------------------------------------------------------------
-- 3. Correction robuste du hash des codes d'accès
-- ------------------------------------------------------------
create or replace function public.hash_code(p_code text)
returns text
language sql
immutable
strict
set search_path = public, extensions
as $$
  select encode(
    extensions.digest(
      convert_to(upper(trim(p_code)), 'UTF8'),
      'sha256'::text
    ),
    'hex'
  );
$$;


-- ------------------------------------------------------------
-- 4. Vérification finale
-- ------------------------------------------------------------
select
  'VIC-CONNECT V4 installée avec succès.' as message;
