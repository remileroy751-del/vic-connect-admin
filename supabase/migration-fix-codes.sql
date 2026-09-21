-- VIC-CONNECT — MIGRATION CORRECTIVE CODES D'ACCÈS
-- À COLLER DIRECTEMENT dans Supabase > SQL Editor.
-- NE PAS écrire le nom du fichier dans l'éditeur.
-- Migration non destructive : aucune table ni donnée n'est supprimée.

-- 1) Activer pgcrypto dans le schéma extensions de Supabase.
create extension if not exists pgcrypto with schema extensions;

-- 2) Générateur de codes (4 caractères pour les parents, 5 pour les enseignants).
create or replace function public.make_code(p_length integer)
returns text
language plpgsql
volatile
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i integer;
begin
  if p_length is null or p_length < 1 then
    raise exception 'La longueur du code doit être supérieure à 0';
  end if;
  for i in 1..p_length loop
    result := result || substr(alphabet, floor(random() * length(alphabet) + 1)::integer, 1);
  end loop;
  return result;
end;
$$;

-- 3) CORRECTION PRINCIPALE de l'erreur :
--    function digest(bytea, unknown) does not exist
--    On force le schéma extensions et le type bytea.
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

-- 4) Fonction d'identification Direction utilisée par les RPC admin.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users where user_id = auth.uid()
  );
$$;

-- 5) Création d'un parent seul + génération d'un code parent de 4 caractères.
create or replace function public.admin_create_parent(
  p_full_name text,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_parent_id uuid;
  v_code text;
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if nullif(trim(p_full_name), '') is null then
    raise exception 'Nom du parent obligatoire.';
  end if;

  loop
    v_code := public.make_code(4);
    exit when not exists (
      select 1 from public.parents
      where access_code_hash = public.hash_code(v_code)
    );
  end loop;

  insert into public.parents(full_name, phone, access_code_hash)
  values (trim(p_full_name), nullif(trim(p_phone), ''), public.hash_code(v_code))
  returning id into v_parent_id;

  return jsonb_build_object(
    'success', true,
    'parent_id', v_parent_id,
    'parent_code', v_code
  );
end;
$$;

grant execute on function public.hash_code(text) to anon, authenticated;
grant execute on function public.make_code(integer) to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.admin_create_parent(text, text) to authenticated;

-- 6) Test direct du correctif.
--    Le résultat doit être une chaîne hexadécimale de 64 caractères.
select public.hash_code('7BTM') as test_hash;
