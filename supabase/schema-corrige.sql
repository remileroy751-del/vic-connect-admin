-- VIC-CONNECT — Schéma Supabase CORRIGÉ
-- Lycée technique et moderne VIC-INTELLIGENTSIA
-- Version complète prête à coller dans Supabase SQL Editor.
-- IMPORTANT : ce script réinitialise uniquement les objets VIC-CONNECT
-- du schéma public. Utilisez-le maintenant sur la base VIC-CONNECT.

create extension if not exists pgcrypto;

-- ============================================================
-- 1. NETTOYAGE DES OBJETS VIC-CONNECT
-- ============================================================

drop function if exists public.teacher_send_parent_message(text, uuid, uuid, text);
drop function if exists public.teacher_save_note(text, uuid, uuid, text, text, numeric, text);
drop function if exists public.teacher_student_notes(text, uuid, uuid, text);
drop function if exists public.teacher_students(text, uuid);
drop function if exists public.teacher_classes(text);
drop function if exists public.send_parent_message(text, uuid, uuid, text);
drop function if exists public.conversation_messages(text, uuid, uuid);
drop function if exists public.acknowledge_announcement(text, uuid, uuid);
drop function if exists public.student_announcements(text, uuid);
drop function if exists public.student_notes(text, uuid, text);
drop function if exists public.parent_child_teachers(text, uuid);
drop function if exists public.parent_children(text);
drop function if exists public.login_with_access_code(text);
drop function if exists public.admin_create_announcement(text, text, text, text, uuid, uuid, uuid);
drop function if exists public.admin_reset_teacher_code(uuid);
drop function if exists public.admin_reset_parent_code(uuid);
drop function if exists public.admin_assign_teacher(uuid, uuid, uuid, boolean);
drop function if exists public.admin_create_teacher(text, text);
drop function if exists public.admin_create_student(text, uuid, text, text);
drop function if exists public.admin_create_parent(text, text);
drop function if exists public.bootstrap_admin(text);
drop function if exists public.is_admin();
drop function if exists public.hash_code(text);
drop function if exists public.make_code(integer);

drop table if exists public.messages cascade;
drop table if exists public.conversations cascade;
drop table if exists public.announcement_receipts cascade;
drop table if exists public.announcements cascade;
drop table if exists public.notes cascade;
drop table if exists public.teacher_assignments cascade;
drop table if exists public.student_parents cascade;
drop table if exists public.students cascade;
drop table if exists public.teachers cascade;
drop table if exists public.parents cascade;
drop table if exists public.subjects cascade;
drop table if exists public.classes cascade;
drop table if exists public.admin_users cascade;

-- ============================================================
-- 2. TABLES
-- ============================================================

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text not null unique,
  created_at timestamptz not null default now()
);

create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.parents (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  access_code_hash text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.teachers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  access_code_hash text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  class_id uuid not null references public.classes(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.student_parents (
  student_id uuid not null references public.students(id) on delete cascade,
  parent_id uuid not null references public.parents(id) on delete cascade,
  relationship text,
  primary key (student_id, parent_id)
);

create table public.teacher_assignments (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  is_homeroom boolean not null default false,
  created_at timestamptz not null default now(),
  unique (teacher_id, class_id, subject_id)
);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  teacher_assignment_id uuid not null references public.teacher_assignments(id) on delete cascade,
  term text not null check (term in ('1er trimestre','2e trimestre','3e trimestre')),
  note_type text not null check (note_type in ('devoir','moyenne_classe','composition')),
  value numeric(5,2) not null check (value >= 0 and value <= 20),
  title text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  importance text not null check (importance in ('vert','orange','rouge')),
  target_type text not null check (target_type in ('all','class','student','parent')),
  class_id uuid references public.classes(id) on delete cascade,
  student_id uuid references public.students(id) on delete cascade,
  parent_id uuid references public.parents(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (
    (target_type = 'all' and class_id is null and student_id is null and parent_id is null)
    or (target_type = 'class' and class_id is not null and student_id is null and parent_id is null)
    or (target_type = 'student' and student_id is not null and parent_id is null)
    or (target_type = 'parent' and parent_id is not null)
  )
);

create table public.announcement_receipts (
  id uuid primary key default gen_random_uuid(),
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  parent_id uuid not null references public.parents(id) on delete cascade,
  student_id uuid references public.students(id) on delete cascade,
  acknowledged_at timestamptz not null default now(),
  unique (announcement_id, parent_id, student_id)
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references public.parents(id) on delete cascade,
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (parent_id, teacher_id, student_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_role text not null check (sender_role in ('parent','teacher')),
  body text not null,
  created_at timestamptz not null default now()
);

create table public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 3. INDEX
-- ============================================================

create index idx_students_class on public.students(class_id);
create index idx_student_parents_parent on public.student_parents(parent_id);
create index idx_teacher_assignments_teacher on public.teacher_assignments(teacher_id);
create index idx_teacher_assignments_class on public.teacher_assignments(class_id);
create index idx_notes_student_term on public.notes(student_id, term);
create index idx_notes_assignment_term on public.notes(teacher_assignment_id, term);
create index idx_announcements_created on public.announcements(created_at desc);
create index idx_receipts_parent on public.announcement_receipts(parent_id);
create index idx_conversations_parent on public.conversations(parent_id);
create index idx_conversations_teacher on public.conversations(teacher_id);
create index idx_messages_conversation on public.messages(conversation_id, created_at);

create unique index uq_notes_class_average
on public.notes(student_id, teacher_assignment_id, term)
where note_type = 'moyenne_classe';

create unique index uq_notes_composition
on public.notes(student_id, teacher_assignment_id, term)
where note_type = 'composition';

-- ============================================================
-- 4. DONNÉES DE BASE
-- ============================================================

insert into public.classes (name, code) values
  ('6ième', '6E'),
  ('5ième', '5E'),
  ('4ième', '4E'),
  ('3ième', '3E');

insert into public.subjects (name) values
  ('Français'),
  ('Anglais'),
  ('Mathématiques'),
  ('Sciences Physiques'),
  ('SVT'),
  ('Histoire-Géographie'),
  ('Informatique'),
  ('EPS'),
  ('Technologie'),
  ('Éducation Civique');

-- ============================================================
-- 5. CODES D'ACCÈS
-- ============================================================

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
    result := result ||
      substr(alphabet, floor(random() * length(alphabet) + 1)::integer, 1);
  end loop;

  return result;
end;
$$;

-- CORRECTION DE L'ERREUR DIGEST :
-- digest() reçoit explicitement un bytea grâce à convert_to().
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

-- ============================================================
-- 6. RLS ET ADMIN
-- ============================================================

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

alter table public.classes enable row level security;
alter table public.subjects enable row level security;
alter table public.parents enable row level security;
alter table public.teachers enable row level security;
alter table public.students enable row level security;
alter table public.student_parents enable row level security;
alter table public.teacher_assignments enable row level security;
alter table public.notes enable row level security;
alter table public.announcements enable row level security;
alter table public.announcement_receipts enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.admin_users enable row level security;

create policy anon_deny_classes on public.classes
  for all to anon using (false) with check (false);
create policy anon_deny_subjects on public.subjects
  for all to anon using (false) with check (false);
create policy anon_deny_parents on public.parents
  for all to anon using (false) with check (false);
create policy anon_deny_teachers on public.teachers
  for all to anon using (false) with check (false);
create policy anon_deny_students on public.students
  for all to anon using (false) with check (false);
create policy anon_deny_student_parents on public.student_parents
  for all to anon using (false) with check (false);
create policy anon_deny_assignments on public.teacher_assignments
  for all to anon using (false) with check (false);
create policy anon_deny_notes on public.notes
  for all to anon using (false) with check (false);
create policy anon_deny_announcements on public.announcements
  for all to anon using (false) with check (false);
create policy anon_deny_receipts on public.announcement_receipts
  for all to anon using (false) with check (false);
create policy anon_deny_conversations on public.conversations
  for all to anon using (false) with check (false);
create policy anon_deny_messages on public.messages
  for all to anon using (false) with check (false);
create policy anon_deny_admin_users on public.admin_users
  for all to anon using (false) with check (false);

create policy admin_all_classes on public.classes
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_subjects on public.subjects
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_parents on public.parents
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_teachers on public.teachers
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_students on public.students
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_student_parents on public.student_parents
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_assignments on public.teacher_assignments
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_notes on public.notes
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_announcements on public.announcements
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_receipts on public.announcement_receipts
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_conversations on public.conversations
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_all_messages on public.messages
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_self on public.admin_users
  for select to authenticated using (user_id = auth.uid());

-- ============================================================
-- 7. COMPTE DIRECTION
-- ============================================================

create or replace function public.bootstrap_admin(p_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  mail text := coalesce(p_email, '');
begin
  if uid is null then
    raise exception 'Vous devez être connecté avec un compte Supabase Auth.';
  end if;

  insert into public.admin_users(user_id, email)
  values (uid, nullif(mail, ''))
  on conflict (user_id) do update
  set email = coalesce(excluded.email, public.admin_users.email);

  return jsonb_build_object('success', true, 'message', 'Compte Direction activé.');
end;
$$;

-- ============================================================
-- 8. PARENT SEUL
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

-- ============================================================
-- 9. ÉLÈVE + PARENT
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
set search_path = public
as $$
declare
  v_student_id uuid;
  v_parent_id uuid;
  v_parent_code text;
  v_existing_parent boolean := false;
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if nullif(trim(p_student_full_name), '') is null then
    raise exception 'Nom de l''élève obligatoire.';
  end if;

  if not exists (select 1 from public.classes where id = p_class_id) then
    raise exception 'Classe introuvable.';
  end if;

  if nullif(trim(p_parent_full_name), '') is null then
    raise exception 'Nom du parent obligatoire.';
  end if;

  if nullif(trim(p_parent_phone), '') is not null then
    select id into v_parent_id
    from public.parents
    where phone = trim(p_parent_phone)
    limit 1;

    if v_parent_id is not null then
      v_existing_parent := true;
    end if;
  end if;

  if v_parent_id is null then
    loop
      v_parent_code := public.make_code(4);
      exit when not exists (
        select 1 from public.parents
        where access_code_hash = public.hash_code(v_parent_code)
      );
    end loop;

    insert into public.parents(full_name, phone, access_code_hash)
    values (
      trim(p_parent_full_name),
      nullif(trim(p_parent_phone), ''),
      public.hash_code(v_parent_code)
    )
    returning id into v_parent_id;
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

-- ============================================================
-- 10. ENSEIGNANT
-- ============================================================

create or replace function public.admin_create_teacher(
  p_full_name text,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher_id uuid;
  v_code text;
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if nullif(trim(p_full_name), '') is null then
    raise exception 'Nom de l''enseignant obligatoire.';
  end if;

  loop
    v_code := public.make_code(5);
    exit when not exists (
      select 1 from public.teachers
      where access_code_hash = public.hash_code(v_code)
    );
  end loop;

  insert into public.teachers(full_name, phone, access_code_hash)
  values (trim(p_full_name), nullif(trim(p_phone), ''), public.hash_code(v_code))
  returning id into v_teacher_id;

  return jsonb_build_object(
    'success', true,
    'teacher_id', v_teacher_id,
    'teacher_code', v_code
  );
end;
$$;

-- ============================================================
-- 11. AFFECTATION ENSEIGNANT / CLASSE / MATIÈRE
-- ============================================================

create or replace function public.admin_assign_teacher(
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
  v_assignment_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if not exists (select 1 from public.teachers where id = p_teacher_id) then
    raise exception 'Enseignant introuvable.';
  end if;

  if not exists (select 1 from public.classes where id = p_class_id) then
    raise exception 'Classe introuvable.';
  end if;

  if not exists (select 1 from public.subjects where id = p_subject_id) then
    raise exception 'Matière introuvable.';
  end if;

  if p_is_homeroom then
    update public.teacher_assignments
    set is_homeroom = false
    where class_id = p_class_id;
  end if;

  insert into public.teacher_assignments(
    teacher_id, class_id, subject_id, is_homeroom
  )
  values (
    p_teacher_id, p_class_id, p_subject_id, p_is_homeroom
  )
  on conflict (teacher_id, class_id, subject_id)
  do update set is_homeroom = excluded.is_homeroom
  returning id into v_assignment_id;

  return jsonb_build_object(
    'success', true,
    'assignment_id', v_assignment_id
  );
end;
$$;

-- ============================================================
-- 12. NOUVEAUX CODES
-- ============================================================

create or replace function public.admin_reset_parent_code(p_parent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if not exists (select 1 from public.parents where id = p_parent_id) then
    raise exception 'Parent introuvable.';
  end if;

  loop
    v_code := public.make_code(4);
    exit when not exists (
      select 1 from public.parents
      where access_code_hash = public.hash_code(v_code)
    );
  end loop;

  update public.parents
  set access_code_hash = public.hash_code(v_code), updated_at = now()
  where id = p_parent_id;

  return jsonb_build_object(
    'success', true,
    'parent_id', p_parent_id,
    'parent_code', v_code
  );
end;
$$;

create or replace function public.admin_reset_teacher_code(p_teacher_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if not exists (select 1 from public.teachers where id = p_teacher_id) then
    raise exception 'Enseignant introuvable.';
  end if;

  loop
    v_code := public.make_code(5);
    exit when not exists (
      select 1 from public.teachers
      where access_code_hash = public.hash_code(v_code)
    );
  end loop;

  update public.teachers
  set access_code_hash = public.hash_code(v_code), updated_at = now()
  where id = p_teacher_id;

  return jsonb_build_object(
    'success', true,
    'teacher_id', p_teacher_id,
    'teacher_code', v_code
  );
end;
$$;

-- ============================================================
-- 13. COMMUNIQUÉS
-- ============================================================

create or replace function public.admin_create_announcement(
  p_title text,
  p_body text,
  p_importance text,
  p_target_type text,
  p_class_id uuid default null,
  p_student_id uuid default null,
  p_parent_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if nullif(trim(p_title), '') is null then
    raise exception 'Titre obligatoire.';
  end if;

  if nullif(trim(p_body), '') is null then
    raise exception 'Message obligatoire.';
  end if;

  if p_importance not in ('vert','orange','rouge') then
    raise exception 'Importance invalide.';
  end if;

  if p_target_type not in ('all','class','student','parent') then
    raise exception 'Cible invalide.';
  end if;

  if p_target_type = 'all'
     and (p_class_id is not null or p_student_id is not null or p_parent_id is not null) then
    raise exception 'Une annonce générale ne doit pas avoir de cible précise.';
  end if;

  if p_target_type = 'class' and p_class_id is null then
    raise exception 'La classe est obligatoire.';
  end if;

  if p_target_type = 'student' and p_student_id is null then
    raise exception 'L''élève est obligatoire.';
  end if;

  if p_target_type = 'parent' and p_parent_id is null then
    raise exception 'Le parent est obligatoire.';
  end if;

  insert into public.announcements(
    title, body, importance, target_type,
    class_id, student_id, parent_id, created_by
  )
  values (
    trim(p_title), trim(p_body), p_importance, p_target_type,
    p_class_id, p_student_id, p_parent_id, auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object(
    'success', true,
    'announcement_id', v_id
  );
end;
$$;

-- ============================================================
-- 14. CONNEXION PAR CODE
-- ============================================================

create or replace function public.login_with_access_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text;
  v_parent record;
  v_teacher record;
begin
  if nullif(trim(p_code), '') is null then
    raise exception 'Code d''accès obligatoire.';
  end if;

  v_hash := public.hash_code(p_code);

  select id, full_name, phone
  into v_parent
  from public.parents
  where access_code_hash = v_hash
  limit 1;

  if v_parent.id is not null then
    return jsonb_build_object(
      'success', true,
      'role', 'parent',
      'id', v_parent.id,
      'full_name', v_parent.full_name,
      'phone', v_parent.phone
    );
  end if;

  select id, full_name, phone
  into v_teacher
  from public.teachers
  where access_code_hash = v_hash
  limit 1;

  if v_teacher.id is not null then
    return jsonb_build_object(
      'success', true,
      'role', 'teacher',
      'id', v_teacher.id,
      'full_name', v_teacher.full_name,
      'phone', v_teacher.phone
    );
  end if;

  return jsonb_build_object(
    'success', false,
    'message', 'Code d''accès incorrect.'
  );
end;
$$;

-- ============================================================
-- 15. PARENT : ENFANTS
-- ============================================================

create or replace function public.parent_children(p_code text)
returns table (
  student_id uuid,
  student_name text,
  class_id uuid,
  class_name text
)
language sql
security definer
set search_path = public
as $$
  select s.id, s.full_name, c.id, c.name
  from public.parents p
  join public.student_parents sp on sp.parent_id = p.id
  join public.students s on s.id = sp.student_id
  join public.classes c on c.id = s.class_id
  where p.access_code_hash = public.hash_code(p_code)
  order by s.full_name;
$$;

create or replace function public.parent_child_teachers(
  p_code text,
  p_student_id uuid
)
returns table (
  teacher_id uuid,
  teacher_name text,
  subject_id uuid,
  subject_name text,
  is_homeroom boolean
)
language sql
security definer
set search_path = public
as $$
  select distinct
    t.id, t.full_name, su.id, su.name, ta.is_homeroom
  from public.parents p
  join public.student_parents sp
    on sp.parent_id = p.id and sp.student_id = p_student_id
  join public.students s on s.id = sp.student_id
  join public.teacher_assignments ta on ta.class_id = s.class_id
  join public.teachers t on t.id = ta.teacher_id
  join public.subjects su on su.id = ta.subject_id
  where p.access_code_hash = public.hash_code(p_code)
  order by ta.is_homeroom desc, t.full_name, su.name;
$$;

-- ============================================================
-- 15. NOTES ET MOYENNES
-- ============================================================

create or replace function public.student_notes(
  p_code text,
  p_student_id uuid,
  p_term text
)
returns table (
  subject_id uuid,
  subject_name text,
  devoirs jsonb,
  moyenne_classe numeric,
  composition numeric,
  moyenne_matiere numeric
)
language sql
security definer
set search_path = public
as $$
  with authorized_student as (
    select s.id, s.class_id
    from public.parents p
    join public.student_parents sp
      on sp.parent_id = p.id and sp.student_id = p_student_id
    join public.students s on s.id = sp.student_id
    where p.access_code_hash = public.hash_code(p_code)
  ),
  subject_rows as (
    select
      su.id as subject_id,
      su.name as subject_name,
      max(n.value) filter (where n.note_type = 'moyenne_classe') as moyenne_classe,
      max(n.value) filter (where n.note_type = 'composition') as composition,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', n.id,
            'value', n.value,
            'title', n.title,
            'created_at', n.created_at
          )
          order by n.created_at
        ) filter (where n.note_type = 'devoir'),
        '[]'::jsonb
      ) as devoirs
    from authorized_student a
    cross join public.subjects su
    left join public.teacher_assignments ta
      on ta.class_id = a.class_id
     and ta.subject_id = su.id
    left join public.notes n
      on n.teacher_assignment_id = ta.id
     and n.student_id = a.id
     and n.term = p_term
    group by su.id, su.name
  )
  select
    subject_id,
    subject_name,
    devoirs,
    round(moyenne_classe, 2),
    round(composition, 2),
    case
      when moyenne_classe is not null and composition is not null
      then round((moyenne_classe + composition) / 2, 2)
      else null
    end
  from subject_rows
  where moyenne_classe is not null
     or composition is not null
     or jsonb_array_length(devoirs) > 0
  order by subject_name;
$$;

-- ============================================================
-- 16. COMMUNIQUÉS PARENT
-- ============================================================

create or replace function public.student_announcements(
  p_code text,
  p_student_id uuid
)
returns table (
  announcement_id uuid,
  title text,
  body text,
  importance text,
  target_type text,
  created_at timestamptz,
  acknowledged boolean
)
language sql
security definer
set search_path = public
as $$
  select
    a.id,
    a.title,
    a.body,
    a.importance,
    a.target_type,
    a.created_at,
    exists (
      select 1
      from public.announcement_receipts ar
      where ar.announcement_id = a.id
        and ar.parent_id = p.id
        and (ar.student_id = p_student_id or ar.student_id is null)
    ) as acknowledged
  from public.parents p
  join public.student_parents sp
    on sp.parent_id = p.id and sp.student_id = p_student_id
  join public.students s on s.id = sp.student_id
  join public.announcements a
    on (
      a.target_type = 'all'
      or (a.target_type = 'class' and a.class_id = s.class_id)
      or (a.target_type = 'student' and a.student_id = s.id)
      or (a.target_type = 'parent' and a.parent_id = p.id)
    )
  where p.access_code_hash = public.hash_code(p_code)
  order by a.created_at desc;
$$;

create or replace function public.acknowledge_announcement(
  p_code text,
  p_announcement_id uuid,
  p_student_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_id uuid;
begin
  select p.id into v_parent_id
  from public.parents p
  join public.student_parents sp
    on sp.parent_id = p.id and sp.student_id = p_student_id
  where p.access_code_hash = public.hash_code(p_code)
  limit 1;

  if v_parent_id is null then
    raise exception 'Parent ou élève non autorisé.';
  end if;

  if not exists (
    select 1
    from public.announcements a
    join public.students s on s.id = p_student_id
    where a.id = p_announcement_id
      and (
        a.target_type = 'all'
        or (a.target_type = 'class' and a.class_id = s.class_id)
        or (a.target_type = 'student' and a.student_id = s.id)
        or (a.target_type = 'parent' and a.parent_id = v_parent_id)
      )
  ) then
    raise exception 'Communiqué non accessible.';
  end if;

  insert into public.announcement_receipts(
    announcement_id, parent_id, student_id, acknowledged_at
  )
  values (p_announcement_id, v_parent_id, p_student_id, now())
  on conflict (announcement_id, parent_id, student_id)
  do update set acknowledged_at = now();

  return jsonb_build_object('success', true, 'acknowledged', true);
end;
$$;

-- ============================================================
-- 17. MESSAGERIE PARENT ↔ ENSEIGNANT
-- ============================================================

create or replace function public.conversation_messages(
  p_code text,
  p_teacher_id uuid,
  p_student_id uuid
)
returns table (
  message_id uuid,
  sender_role text,
  body text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select m.id, m.sender_role, m.body, m.created_at
  from public.parents p
  join public.student_parents sp
    on sp.parent_id = p.id and sp.student_id = p_student_id
  join public.conversations c
    on c.parent_id = p.id
   and c.teacher_id = p_teacher_id
   and c.student_id = p_student_id
  join public.messages m on m.conversation_id = c.id
  where p.access_code_hash = public.hash_code(p_code)
  order by m.created_at;
$$;

create or replace function public.send_parent_message(
  p_code text,
  p_teacher_id uuid,
  p_student_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_id uuid;
  v_conversation_id uuid;
  v_message_id uuid;
begin
  if nullif(trim(p_body), '') is null then
    raise exception 'Le message est vide.';
  end if;

  select p.id into v_parent_id
  from public.parents p
  join public.student_parents sp
    on sp.parent_id = p.id and sp.student_id = p_student_id
  where p.access_code_hash = public.hash_code(p_code)
  limit 1;

  if v_parent_id is null then
    raise exception 'Parent non autorisé.';
  end if;

  if not exists (
    select 1
    from public.teacher_assignments ta
    join public.students s on s.class_id = ta.class_id
    where ta.teacher_id = p_teacher_id and s.id = p_student_id
  ) then
    raise exception 'Cet enseignant n''intervient pas dans la classe de cet élève.';
  end if;

  insert into public.conversations(parent_id, teacher_id, student_id)
  values (v_parent_id, p_teacher_id, p_student_id)
  on conflict (parent_id, teacher_id, student_id)
  do update set parent_id = excluded.parent_id
  returning id into v_conversation_id;

  insert into public.messages(conversation_id, sender_role, body)
  values (v_conversation_id, 'parent', trim(p_body))
  returning id into v_message_id;

  return jsonb_build_object(
    'success', true,
    'message_id', v_message_id,
    'conversation_id', v_conversation_id
  );
end;
$$;

create or replace function public.teacher_send_parent_message(
  p_code text,
  p_student_id uuid,
  p_parent_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher_id uuid;
  v_conversation_id uuid;
  v_message_id uuid;
begin
  if nullif(trim(p_body), '') is null then
    raise exception 'Le message est vide.';
  end if;

  select id into v_teacher_id
  from public.teachers
  where access_code_hash = public.hash_code(p_code)
  limit 1;

  if v_teacher_id is null then
    raise exception 'Code enseignant invalide.';
  end if;

  if not exists (
    select 1
    from public.student_parents sp
    where sp.student_id = p_student_id and sp.parent_id = p_parent_id
  ) then
    raise exception 'Ce parent n''est pas lié à cet élève.';
  end if;

  if not exists (
    select 1
    from public.teacher_assignments ta
    join public.students s on s.class_id = ta.class_id
    where ta.teacher_id = v_teacher_id and s.id = p_student_id
  ) then
    raise exception 'Cet enseignant n''est pas affecté à la classe de cet élève.';
  end if;

  insert into public.conversations(parent_id, teacher_id, student_id)
  values (p_parent_id, v_teacher_id, p_student_id)
  on conflict (parent_id, teacher_id, student_id)
  do update set teacher_id = excluded.teacher_id
  returning id into v_conversation_id;

  insert into public.messages(conversation_id, sender_role, body)
  values (v_conversation_id, 'teacher', trim(p_body))
  returning id into v_message_id;

  return jsonb_build_object(
    'success', true,
    'message_id', v_message_id,
    'conversation_id', v_conversation_id
  );
end;
$$;

-- ============================================================
-- 18. ESPACE ENSEIGNANT
-- ============================================================

create or replace function public.teacher_classes(p_code text)
returns table (
  class_id uuid,
  class_name text,
  subject_id uuid,
  subject_name text,
  assignment_id uuid,
  is_homeroom boolean
)
language sql
security definer
set search_path = public
as $$
  select c.id, c.name, su.id, su.name, ta.id, ta.is_homeroom
  from public.teachers t
  join public.teacher_assignments ta on ta.teacher_id = t.id
  join public.classes c on c.id = ta.class_id
  join public.subjects su on su.id = ta.subject_id
  where t.access_code_hash = public.hash_code(p_code)
  order by c.name, su.name;
$$;

create or replace function public.teacher_students(
  p_code text,
  p_class_id uuid
)
returns table (
  student_id uuid,
  student_name text,
  class_name text
)
language sql
security definer
set search_path = public
as $$
  select distinct s.id, s.full_name, c.name
  from public.teachers t
  join public.teacher_assignments ta on ta.teacher_id = t.id
  join public.classes c on c.id = ta.class_id
  join public.students s on s.class_id = c.id
  where t.access_code_hash = public.hash_code(p_code)
    and c.id = p_class_id
  order by s.full_name;
$$;

create or replace function public.teacher_student_notes(
  p_code text,
  p_student_id uuid,
  p_assignment_id uuid,
  p_term text
)
returns table (
  note_id uuid,
  note_type text,
  value numeric,
  title text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select n.id, n.note_type, n.value, n.title, n.created_at
  from public.teachers t
  join public.teacher_assignments ta on ta.teacher_id = t.id
  join public.students s on s.class_id = ta.class_id
  join public.notes n
    on n.teacher_assignment_id = ta.id
   and n.student_id = s.id
  where t.access_code_hash = public.hash_code(p_code)
    and s.id = p_student_id
    and ta.id = p_assignment_id
    and n.term = p_term
  order by
    case n.note_type
      when 'devoir' then 1
      when 'moyenne_classe' then 2
      when 'composition' then 3
      else 4
    end,
    n.created_at;
$$;

create or replace function public.teacher_save_note(
  p_code text,
  p_student_id uuid,
  p_assignment_id uuid,
  p_term text,
  p_note_type text,
  p_value numeric,
  p_title text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher_id uuid;
  v_note_id uuid;
  v_existing_id uuid;
begin
  select id into v_teacher_id
  from public.teachers
  where access_code_hash = public.hash_code(p_code)
  limit 1;

  if v_teacher_id is null then
    raise exception 'Code enseignant invalide.';
  end if;

  if p_term not in ('1er trimestre','2e trimestre','3e trimestre') then
    raise exception 'Trimestre invalide.';
  end if;

  if p_note_type not in ('devoir','moyenne_classe','composition') then
    raise exception 'Type de note invalide.';
  end if;

  if p_value is null or p_value < 0 or p_value > 20 then
    raise exception 'La note doit être comprise entre 0 et 20.';
  end if;

  if not exists (
    select 1
    from public.teacher_assignments ta
    join public.students s on s.class_id = ta.class_id
    where ta.id = p_assignment_id
      and ta.teacher_id = v_teacher_id
      and s.id = p_student_id
  ) then
    raise exception 'Vous n''êtes pas autorisé à saisir cette note.';
  end if;

  if p_note_type = 'devoir' then
    insert into public.notes(
      student_id, teacher_assignment_id, term,
      note_type, value, title, updated_at
    )
    values (
      p_student_id, p_assignment_id, p_term,
      'devoir', p_value, nullif(trim(p_title), ''), now()
    )
    returning id into v_note_id;
  else
    select id into v_existing_id
    from public.notes
    where student_id = p_student_id
      and teacher_assignment_id = p_assignment_id
      and term = p_term
      and note_type = p_note_type
    limit 1;

    if v_existing_id is null then
      insert into public.notes(
        student_id, teacher_assignment_id, term,
        note_type, value, title, updated_at
      )
      values (
        p_student_id, p_assignment_id, p_term,
        p_note_type, p_value, nullif(trim(p_title), ''), now()
      )
      returning id into v_note_id;
    else
      update public.notes
      set value = p_value,
          title = nullif(trim(p_title), ''),
          updated_at = now()
      where id = v_existing_id
      returning id into v_note_id;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'note_id', v_note_id
  );
end;
$$;

-- ============================================================
-- 19. DROITS D'EXÉCUTION DES RPC
-- ============================================================

grant execute on function public.login_with_access_code(text) to anon, authenticated;

grant execute on function public.parent_children(text) to anon, authenticated;
grant execute on function public.parent_child_teachers(text, uuid) to anon, authenticated;
grant execute on function public.student_notes(text, uuid, text) to anon, authenticated;
grant execute on function public.student_announcements(text, uuid) to anon, authenticated;
grant execute on function public.acknowledge_announcement(text, uuid, uuid) to anon, authenticated;
grant execute on function public.conversation_messages(text, uuid, uuid) to anon, authenticated;
grant execute on function public.send_parent_message(text, uuid, uuid, text) to anon, authenticated;

grant execute on function public.teacher_classes(text) to anon, authenticated;
grant execute on function public.teacher_students(text, uuid) to anon, authenticated;
grant execute on function public.teacher_student_notes(text, uuid, uuid, text) to anon, authenticated;
grant execute on function public.teacher_save_note(text, uuid, uuid, text, text, numeric, text) to anon, authenticated;
grant execute on function public.teacher_send_parent_message(text, uuid, uuid, text) to anon, authenticated;

grant execute on function public.bootstrap_admin(text) to authenticated;
grant execute on function public.admin_create_student(text, uuid, text, text) to authenticated;
grant execute on function public.admin_create_teacher(text, text) to authenticated;
grant execute on function public.admin_assign_teacher(uuid, uuid, uuid, boolean) to authenticated;
grant execute on function public.admin_reset_parent_code(uuid) to authenticated;
grant execute on function public.admin_reset_teacher_code(uuid) to authenticated;
grant execute on function public.admin_create_announcement(text, text, text, text, uuid, uuid, uuid) to authenticated;
grant execute on function public.admin_create_parent(text, text) to authenticated;

-- ============================================================
-- FIN DU SCHÉMA VIC-CONNECT
-- ============================================================

-- ============================================================
-- VIC-CONNECT — MIGRATION V5
-- Statistiques enseignant + messagerie parent/enseignant + quota
-- ============================================================
-- Migration NON destructive.
-- À exécuter dans Supabase SQL Editor avant d'utiliser la nouvelle APK.
-- Quota : 5 messages maximum par compte et par jour civil GMT,
-- toutes directions confondues (envoyés + reçus). Remise à zéro à 00h GMT.

-- ------------------------------------------------------------
-- 1. Messagerie : envoi parent avec quota journalier GMT
-- ------------------------------------------------------------
create or replace function public.send_parent_message(
  p_code text,
  p_teacher_id uuid,
  p_student_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_id uuid;
  v_conversation_id uuid;
  v_message_id uuid;
  v_day_start timestamptz;
  v_used integer;
begin
  if nullif(trim(p_body), '') is null then
    raise exception 'Le message est vide.';
  end if;

  v_day_start := timezone('UTC', date_trunc('day', now() at time zone 'UTC'));

  select p.id into v_parent_id
  from public.parents p
  join public.student_parents sp
    on sp.parent_id = p.id and sp.student_id = p_student_id
  where p.access_code_hash = public.hash_code(p_code)
  limit 1;

  if v_parent_id is null then
    raise exception 'Parent non autorisé.';
  end if;

  if not exists (
    select 1
    from public.teacher_assignments ta
    join public.students s on s.class_id = ta.class_id
    where ta.teacher_id = p_teacher_id and s.id = p_student_id
  ) then
    raise exception 'Cet enseignant n''intervient pas dans la classe de cet élève.';
  end if;

  select count(*)::integer into v_used
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  where c.parent_id = v_parent_id
    and m.created_at >= v_day_start;

  if v_used >= 5 then
    raise exception 'Quota atteint : ce compte a déjà envoyé ou reçu 5 messages aujourd''hui. Nouveau quota à 00h GMT.';
  end if;

  insert into public.conversations(parent_id, teacher_id, student_id)
  values (v_parent_id, p_teacher_id, p_student_id)
  on conflict (parent_id, teacher_id, student_id)
  do update set parent_id = excluded.parent_id
  returning id into v_conversation_id;

  insert into public.messages(conversation_id, sender_role, body)
  values (v_conversation_id, 'parent', trim(p_body))
  returning id into v_message_id;

  return jsonb_build_object('success', true, 'message_id', v_message_id, 'conversation_id', v_conversation_id);
end;
$$;

-- ------------------------------------------------------------
-- 2. Messagerie : envoi enseignant avec quota journalier GMT
-- ------------------------------------------------------------
create or replace function public.teacher_send_parent_message(
  p_code text,
  p_student_id uuid,
  p_parent_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher_id uuid;
  v_conversation_id uuid;
  v_message_id uuid;
  v_day_start timestamptz;
  v_used integer;
begin
  if nullif(trim(p_body), '') is null then
    raise exception 'Le message est vide.';
  end if;

  v_day_start := timezone('UTC', date_trunc('day', now() at time zone 'UTC'));

  select id into v_teacher_id
  from public.teachers
  where access_code_hash = public.hash_code(p_code)
  limit 1;

  if v_teacher_id is null then
    raise exception 'Code enseignant invalide.';
  end if;

  if not exists (
    select 1 from public.student_parents sp
    where sp.student_id = p_student_id and sp.parent_id = p_parent_id
  ) then
    raise exception 'Ce parent n''est pas lié à cet élève.';
  end if;

  if not exists (
    select 1
    from public.teacher_assignments ta
    join public.students s on s.class_id = ta.class_id
    where ta.teacher_id = v_teacher_id and s.id = p_student_id
  ) then
    raise exception 'Cet enseignant n''est pas affecté à la classe de cet élève.';
  end if;

  select count(*)::integer into v_used
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  where c.teacher_id = v_teacher_id
    and m.created_at >= v_day_start;

  if v_used >= 5 then
    raise exception 'Quota atteint : ce compte a déjà envoyé ou reçu 5 messages aujourd''hui. Nouveau quota à 00h GMT.';
  end if;

  insert into public.conversations(parent_id, teacher_id, student_id)
  values (p_parent_id, v_teacher_id, p_student_id)
  on conflict (parent_id, teacher_id, student_id)
  do update set teacher_id = excluded.teacher_id
  returning id into v_conversation_id;

  insert into public.messages(conversation_id, sender_role, body)
  values (v_conversation_id, 'teacher', trim(p_body))
  returning id into v_message_id;

  return jsonb_build_object('success', true, 'message_id', v_message_id, 'conversation_id', v_conversation_id);
end;
$$;

-- ------------------------------------------------------------
-- 3. Boîte de réception enseignant
-- ------------------------------------------------------------
create or replace function public.teacher_conversations(p_code text)
returns table (
  parent_id uuid,
  parent_name text,
  student_id uuid,
  student_name text,
  class_name text,
  last_message text,
  last_sender_role text,
  last_message_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    p.id,
    p.full_name,
    s.id,
    s.full_name,
    cclass.name,
    lm.body,
    lm.sender_role,
    lm.created_at
  from public.teachers t
  join public.conversations c on c.teacher_id = t.id
  join public.parents p on p.id = c.parent_id
  join public.students s on s.id = c.student_id
  join public.classes cclass on cclass.id = s.class_id
  join lateral (
    select m.body, m.sender_role, m.created_at
    from public.messages m
    where m.conversation_id = c.id
    order by m.created_at desc
    limit 1
  ) lm on true
  where t.access_code_hash = public.hash_code(p_code)
  order by lm.created_at desc;
$$;

-- ------------------------------------------------------------
-- 4. Lecture d'une conversation côté enseignant
-- ------------------------------------------------------------
create or replace function public.teacher_conversation_messages(
  p_code text,
  p_student_id uuid,
  p_parent_id uuid
)
returns table (
  message_id uuid,
  sender_role text,
  body text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select m.id, m.sender_role, m.body, m.created_at
  from public.teachers t
  join public.conversations c
    on c.teacher_id = t.id
   and c.student_id = p_student_id
   and c.parent_id = p_parent_id
  join public.messages m on m.conversation_id = c.id
  where t.access_code_hash = public.hash_code(p_code)
  order by m.created_at;
$$;

-- ------------------------------------------------------------
-- 5. Statistiques : classes + effectifs
-- ------------------------------------------------------------
create or replace function public.teacher_class_statistics(
  p_code text,
  p_term text
)
returns table (
  class_id uuid,
  class_name text,
  effectif bigint
)
language sql
security definer
set search_path = public
as $$
  select
    c.id,
    c.name,
    count(distinct s.id)
  from public.teachers t
  join public.teacher_assignments ta on ta.teacher_id = t.id
  join public.classes c on c.id = ta.class_id
  left join public.students s on s.class_id = c.id
  where t.access_code_hash = public.hash_code(p_code)
  group by c.id, c.name
  order by c.name;
$$;

-- ------------------------------------------------------------
-- 6. Statistiques : classement par moyenne générale du trimestre
--    La moyenne générale utilise uniquement les moyennes de matières
--    calculées avec Moyenne de classe + Composition. Les devoirs sont exclus.
-- ------------------------------------------------------------
create or replace function public.teacher_student_rankings(
  p_code text,
  p_class_id uuid,
  p_term text
)
returns table (
  student_id uuid,
  student_name text,
  moyenne_generale numeric
)
language sql
security definer
set search_path = public
as $$
  with authorized_teacher as (
    select distinct ta.class_id
    from public.teachers t
    join public.teacher_assignments ta on ta.teacher_id = t.id
    where t.access_code_hash = public.hash_code(p_code)
      and ta.class_id = p_class_id
  ),
  assignment_subjects as (
    select
      s.id as student_id,
      ta.subject_id,
      ta.id as assignment_id,
      max(n.value) filter (where n.note_type = 'moyenne_classe') as moyenne_classe,
      max(n.value) filter (where n.note_type = 'composition') as composition
    from public.students s
    join authorized_teacher at on at.class_id = s.class_id
    join public.teacher_assignments ta on ta.class_id = s.class_id
    left join public.notes n
      on n.student_id = s.id
     and n.teacher_assignment_id = ta.id
     and n.term = p_term
    group by s.id, ta.subject_id, ta.id
  ),
  subject_averages as (
    select
      student_id,
      subject_id,
      avg((moyenne_classe + composition) / 2.0) as subject_average
    from assignment_subjects
    where moyenne_classe is not null
      and composition is not null
    group by student_id, subject_id
  )
  select
    s.id,
    s.full_name,
    round(avg(sa.subject_average), 2)
  from public.students s
  join authorized_teacher at on at.class_id = s.class_id
  left join subject_averages sa on sa.student_id = s.id
  group by s.id, s.full_name
  order by
    avg(sa.subject_average) desc nulls last,
    s.full_name asc;
$$;

-- ------------------------------------------------------------
-- 7. Droits RPC
-- ------------------------------------------------------------
grant execute on function public.send_parent_message(text, uuid, uuid, text) to anon, authenticated;
grant execute on function public.teacher_send_parent_message(text, uuid, uuid, text) to anon, authenticated;
grant execute on function public.teacher_conversations(text) to anon, authenticated;
grant execute on function public.teacher_conversation_messages(text, uuid, uuid) to anon, authenticated;
grant execute on function public.teacher_class_statistics(text, text) to anon, authenticated;
grant execute on function public.teacher_student_rankings(text, uuid, text) to anon, authenticated;

-- ============================================================
-- FIN MIGRATION V5
-- ============================================================
