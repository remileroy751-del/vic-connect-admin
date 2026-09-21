-- VIC-CONNECT — MIGRATION V3
-- Mises à jour non destructives pour :
-- 1) historique des codes d'accès parent/enseignant visible par la Direction
-- 2) modification des affectations enseignant/classe/matière
--
-- À exécuter dans Supabase > SQL Editor en COPIANT LE CONTENU DE CE FICHIER.
-- Ne pas écrire le nom du fichier dans SQL Editor.
-- Cette migration ne supprime aucune table ni aucune donnée.

create extension if not exists pgcrypto with schema extensions;

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

create or replace function public.hash_code(p_code text)
returns text
language sql
immutable
strict
set search_path = public, extensions
as $$
  select encode(extensions.digest(convert_to(upper(trim(p_code)), 'UTF8'), 'sha256'::text), 'hex');
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid());
$$;

-- ============================================================
-- 1. REGISTRE ADMINISTRATIF DES CODES
-- ============================================================
create table if not exists public.access_code_records (
  id uuid primary key default gen_random_uuid(),
  role text not null check (role in ('parent','teacher')),
  parent_id uuid references public.parents(id) on delete cascade,
  teacher_id uuid references public.teachers(id) on delete cascade,
  full_name text not null,
  phone text,
  access_code text not null,
  generated_at timestamptz not null default now(),
  is_current boolean not null default true,
  constraint access_code_records_owner_check check (
    (role = 'parent' and parent_id is not null and teacher_id is null)
    or (role = 'teacher' and teacher_id is not null and parent_id is null)
  )
);

create index if not exists idx_access_code_records_role on public.access_code_records(role);
create index if not exists idx_access_code_records_parent on public.access_code_records(parent_id);
create index if not exists idx_access_code_records_teacher on public.access_code_records(teacher_id);
create index if not exists idx_access_code_records_generated on public.access_code_records(generated_at desc);

alter table public.access_code_records enable row level security;
drop policy if exists access_code_records_no_direct_select on public.access_code_records;
create policy access_code_records_no_direct_select on public.access_code_records
  for all to anon, authenticated using (false) with check (false);

create unique index if not exists ux_access_code_records_parent_current
  on public.access_code_records(parent_id) where is_current and parent_id is not null;
create unique index if not exists ux_access_code_records_teacher_current
  on public.access_code_records(teacher_id) where is_current and teacher_id is not null;

-- ============================================================
-- 2. FONCTION ADMIN : LIRE LES CODES
-- ============================================================
create or replace function public.admin_access_codes()
returns table (
  id uuid,
  role text,
  parent_id uuid,
  teacher_id uuid,
  full_name text,
  phone text,
  access_code text,
  generated_at timestamptz,
  is_current boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  return query
  select r.id, r.role, r.parent_id, r.teacher_id, r.full_name, r.phone,
         r.access_code, r.generated_at, r.is_current
  from public.access_code_records r
  order by r.role, r.is_current desc, r.full_name, r.generated_at desc;
end;
$$;

grant execute on function public.admin_access_codes() to authenticated;

-- ============================================================
-- 3. CRÉATION PARENT : ENREGISTRER LE CODE GÉNÉRÉ
-- ============================================================
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
      select 1 from public.parents where access_code_hash = public.hash_code(v_code)
    );
  end loop;

  insert into public.parents(full_name, phone, access_code_hash)
  values (trim(p_full_name), nullif(trim(p_phone), ''), public.hash_code(v_code))
  returning id into v_parent_id;

  insert into public.access_code_records(role, parent_id, full_name, phone, access_code)
  values ('parent', v_parent_id, trim(p_full_name), nullif(trim(p_phone), ''), v_code);

  return jsonb_build_object('success', true, 'parent_id', v_parent_id, 'parent_code', v_code);
end;
$$;

grant execute on function public.admin_create_parent(text, text) to authenticated;

-- ============================================================
-- 4. CRÉATION ÉLÈVE + PARENT : ENREGISTRER LE NOUVEAU CODE
-- ============================================================
create or replace function public.admin_create_student(
  p_student_full_name text,
  p_class_id uuid,
  p_parent_full_name text,
  p_parent_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student_id uuid;
  v_parent_id uuid;
  v_parent_code text;
  v_existing_parent boolean := false;
  v_parent_name text;
  v_parent_phone text;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if nullif(trim(p_student_full_name), '') is null then raise exception 'Nom de l''élève obligatoire.'; end if;
  if not exists (select 1 from public.classes where id = p_class_id) then raise exception 'Classe introuvable.'; end if;
  if nullif(trim(p_parent_full_name), '') is null then raise exception 'Nom du parent obligatoire.'; end if;

  if nullif(trim(p_parent_phone), '') is not null then
    select id, full_name, phone into v_parent_id, v_parent_name, v_parent_phone
    from public.parents where phone = trim(p_parent_phone) limit 1;
    if v_parent_id is not null then v_existing_parent := true; end if;
  end if;

  if v_parent_id is null then
    loop
      v_parent_code := public.make_code(4);
      exit when not exists (select 1 from public.parents where access_code_hash = public.hash_code(v_parent_code));
    end loop;
    v_parent_name := trim(p_parent_full_name);
    v_parent_phone := nullif(trim(p_parent_phone), '');
    insert into public.parents(full_name, phone, access_code_hash)
    values (v_parent_name, v_parent_phone, public.hash_code(v_parent_code))
    returning id into v_parent_id;

    insert into public.access_code_records(role, parent_id, full_name, phone, access_code)
    values ('parent', v_parent_id, v_parent_name, v_parent_phone, v_parent_code);
  end if;

  insert into public.students(full_name, class_id)
  values (trim(p_student_full_name), p_class_id)
  returning id into v_student_id;

  insert into public.student_parents(student_id, parent_id, relationship)
  values (v_student_id, v_parent_id, 'Parent');

  return jsonb_build_object(
    'success', true,
    'student_id', v_student_id,
    'parent_id', v_parent_id,
    'parent_code', v_parent_code,
    'parent_already_exists', v_existing_parent
  );
end;
$$;

grant execute on function public.admin_create_student(text, uuid, text, text) to authenticated;

-- ============================================================
-- 5. CRÉATION ENSEIGNANT : ENREGISTRER LE CODE GÉNÉRÉ
-- ============================================================
create or replace function public.admin_create_teacher(
  p_full_name text,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_teacher_id uuid;
  v_code text;
  v_phone text;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if nullif(trim(p_full_name), '') is null then raise exception 'Nom de l''enseignant obligatoire.'; end if;

  loop
    v_code := public.make_code(5);
    exit when not exists (select 1 from public.teachers where access_code_hash = public.hash_code(v_code));
  end loop;
  v_phone := nullif(trim(p_phone), '');

  insert into public.teachers(full_name, phone, access_code_hash)
  values (trim(p_full_name), v_phone, public.hash_code(v_code))
  returning id into v_teacher_id;

  insert into public.access_code_records(role, teacher_id, full_name, phone, access_code)
  values ('teacher', v_teacher_id, trim(p_full_name), v_phone, v_code);

  return jsonb_build_object('success', true, 'teacher_id', v_teacher_id, 'teacher_code', v_code);
end;
$$;

grant execute on function public.admin_create_teacher(text, text) to authenticated;

-- ============================================================
-- 6. RENOUVELLEMENT CODE PARENT : HISTORISER LE NOUVEAU CODE
-- ============================================================
create or replace function public.admin_reset_parent_code(p_parent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text;
  v_name text;
  v_phone text;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  select full_name, phone into v_name, v_phone from public.parents where id = p_parent_id;
  if v_name is null then raise exception 'Parent introuvable.'; end if;

  loop
    v_code := public.make_code(4);
    exit when not exists (select 1 from public.parents where access_code_hash = public.hash_code(v_code));
  end loop;

  update public.access_code_records set is_current = false where parent_id = p_parent_id and is_current;
  update public.parents set access_code_hash = public.hash_code(v_code), updated_at = now() where id = p_parent_id;
  insert into public.access_code_records(role, parent_id, full_name, phone, access_code)
  values ('parent', p_parent_id, v_name, v_phone, v_code);

  return jsonb_build_object('success', true, 'parent_id', p_parent_id, 'parent_code', v_code);
end;
$$;

grant execute on function public.admin_reset_parent_code(uuid) to authenticated;

-- ============================================================
-- 7. RENOUVELLEMENT CODE ENSEIGNANT : HISTORISER LE NOUVEAU CODE
-- ============================================================
create or replace function public.admin_reset_teacher_code(p_teacher_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text;
  v_name text;
  v_phone text;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  select full_name, phone into v_name, v_phone from public.teachers where id = p_teacher_id;
  if v_name is null then raise exception 'Enseignant introuvable.'; end if;

  loop
    v_code := public.make_code(5);
    exit when not exists (select 1 from public.teachers where access_code_hash = public.hash_code(v_code));
  end loop;

  update public.access_code_records set is_current = false where teacher_id = p_teacher_id and is_current;
  update public.teachers set access_code_hash = public.hash_code(v_code), updated_at = now() where id = p_teacher_id;
  insert into public.access_code_records(role, teacher_id, full_name, phone, access_code)
  values ('teacher', p_teacher_id, v_name, v_phone, v_code);

  return jsonb_build_object('success', true, 'teacher_id', p_teacher_id, 'teacher_code', v_code);
end;
$$;

grant execute on function public.admin_reset_teacher_code(uuid) to authenticated;

-- ============================================================
-- 8. MODIFIER UNE AFFECTATION ENSEIGNANT / CLASSE / MATIÈRE
-- ============================================================
create or replace function public.admin_update_teacher_assignment(
  p_assignment_id uuid,
  p_teacher_id uuid,
  p_class_id uuid,
  p_subject_id uuid,
  p_is_homeroom boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if not exists (select 1 from public.teacher_assignments where id = p_assignment_id) then raise exception 'Affectation introuvable.'; end if;
  if not exists (select 1 from public.teachers where id = p_teacher_id) then raise exception 'Enseignant introuvable.'; end if;
  if not exists (select 1 from public.classes where id = p_class_id) then raise exception 'Classe introuvable.'; end if;
  if not exists (select 1 from public.subjects where id = p_subject_id) then raise exception 'Matière introuvable.'; end if;

  if p_is_homeroom then
    update public.teacher_assignments set is_homeroom = false where class_id = p_class_id and id <> p_assignment_id;
  end if;

  update public.teacher_assignments
  set teacher_id = p_teacher_id,
      class_id = p_class_id,
      subject_id = p_subject_id,
      is_homeroom = p_is_homeroom
  where id = p_assignment_id
  returning id into v_id;

  return jsonb_build_object('success', true, 'assignment_id', v_id);
exception
  when unique_violation then
    raise exception 'Cette affectation existe déjà pour cet enseignant, cette classe et cette matière.';
end;
$$;

grant execute on function public.admin_update_teacher_assignment(uuid, uuid, uuid, boolean) to authenticated;

-- ============================================================
-- 9. NOTE DE COMPATIBILITÉ
-- Les codes créés avant V3 ne peuvent pas être reconstitués à partir
-- de leur hash SHA-256. Ils apparaîtront donc seulement lorsqu'un nouveau
-- code sera généré après cette migration (création ou renouvellement).
-- ============================================================
select 'VIC-CONNECT V3 installée.' as message;
