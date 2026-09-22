-- ============================================================
-- VIC-CONNECT V7 — Ciblage Direction + importance simplifiée
-- ============================================================
-- À exécuter APRÈS migration-v6-messages-notifications.sql.
-- Cette migration est non destructive pour les anciens messages :
-- les anciennes importances sont converties vers les 2 nouvelles.
-- ============================================================

-- 1) Un message de la Direction peut désormais cibler un enseignant précis.
alter table public.announcements
  add column if not exists teacher_id uuid references public.teachers(id) on delete cascade;

-- 2) Normaliser les anciennes importances.
update public.announcements
set importance = case
  when lower(trim(importance)) in ('urgent', 'rouge') then 'urgent'
  else 'pas_urgent'
end
where importance is distinct from case
  when lower(trim(importance)) in ('urgent', 'rouge') then 'urgent'
  else 'pas_urgent'
end;

-- 3) Remplacer l'ancien CHECK d'importance par les 2 valeurs officielles.
do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.announcements'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%importance%'
  loop
    execute format('alter table public.announcements drop constraint if exists %I', r.conname);
  end loop;
end $$;

alter table public.announcements
  add constraint announcements_importance_check
  check (importance in ('urgent', 'pas_urgent'));

-- 4) Remplacer le CHECK des destinataires en ajoutant "un enseignant".
do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.announcements'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%target_type%'
  loop
    execute format('alter table public.announcements drop constraint if exists %I', r.conname);
  end loop;
end $$;

alter table public.announcements
  add constraint announcements_target_type_check check (
    (target_type = 'all' and class_id is null and student_id is null and parent_id is null and teacher_id is null)
    or (target_type = 'class' and class_id is not null and student_id is null and parent_id is null and teacher_id is null)
    or (target_type = 'student' and student_id is not null and parent_id is null and teacher_id is null)
    or (target_type = 'parent' and parent_id is not null and student_id is null and teacher_id is null)
    or (target_type = 'all_parents' and class_id is null and student_id is null and parent_id is null and teacher_id is null)
    or (target_type = 'class_parents' and class_id is not null and student_id is null and parent_id is null and teacher_id is null)
    or (target_type = 'all_teachers' and class_id is null and student_id is null and parent_id is null and teacher_id is null)
    or (target_type = 'teacher' and teacher_id is not null and class_id is null and student_id is null and parent_id is null)
  );

-- 5) Fonction Direction : exactement 4 cibles utilisables.
drop function if exists public.admin_create_announcement(text,text,text,text,uuid,uuid,uuid);

create or replace function public.admin_create_announcement(
  p_title text,
  p_body text,
  p_importance text,
  p_target_type text,
  p_class_id uuid default null,
  p_student_id uuid default null,
  p_parent_id uuid default null,
  p_teacher_id uuid default null
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

  if p_importance not in ('urgent','pas_urgent') then
    raise exception 'Importance invalide. Choisissez Urgent ou Pas urgent.';
  end if;

  if p_target_type not in ('all_parents','class_parents','all_teachers','teacher') then
    raise exception 'Destinataire invalide.';
  end if;

  if p_target_type = 'all_parents'
     and (p_class_id is not null or p_student_id is not null or p_parent_id is not null or p_teacher_id is not null) then
    raise exception 'Le message à tous les parents ne doit pas avoir de cible précise.';
  end if;

  if p_target_type = 'class_parents' and (p_class_id is null or p_student_id is not null or p_parent_id is not null or p_teacher_id is not null) then
    raise exception 'La classe est obligatoire et doit être la seule cible.';
  end if;

  if p_target_type = 'all_teachers'
     and (p_class_id is not null or p_student_id is not null or p_parent_id is not null or p_teacher_id is not null) then
    raise exception 'Le message à tous les enseignants ne doit pas avoir de cible précise.';
  end if;

  if p_target_type = 'teacher'
     and (p_teacher_id is null or p_class_id is not null or p_student_id is not null or p_parent_id is not null) then
    raise exception 'Un enseignant précis doit être sélectionné.';
  end if;

  if p_target_type = 'teacher' and not exists (select 1 from public.teachers where id = p_teacher_id) then
    raise exception 'Enseignant introuvable.';
  end if;

  insert into public.announcements(
    title, body, importance, target_type,
    class_id, student_id, parent_id, teacher_id, created_by
  )
  values (
    trim(p_title), trim(p_body), p_importance, p_target_type,
    case when p_target_type = 'class_parents' then p_class_id else null end,
    null,
    null,
    case when p_target_type = 'teacher' then p_teacher_id else null end,
    auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object('success', true, 'announcement_id', v_id);
end;
$$;

grant execute on function public.admin_create_announcement(text,text,text,text,uuid,uuid,uuid,uuid) to authenticated;

-- 6) Les enseignants reçoivent les messages qui leur sont destinés :
--    à tous les enseignants OU à leur compte précis.
create or replace function public.teacher_announcements(
  p_code text
)
returns table (
  announcement_id uuid,
  title text,
  body text,
  importance text,
  created_at timestamptz
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
    a.created_at
  from public.teachers t
  join public.announcements a
    on a.target_type = 'all_teachers'
    or (a.target_type = 'teacher' and a.teacher_id = t.id)
  where t.access_code_hash = public.hash_code(p_code)
  order by a.created_at desc;
$$;

grant execute on function public.teacher_announcements(text) to anon, authenticated;

-- 7) Notifications Android : l'enseignant reçoit aussi les messages ciblés sur lui.
create or replace function public.mobile_notifications(
  p_code text,
  p_role text,
  p_since timestamptz
)
returns table (
  notification_id text,
  title text,
  body text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  with incoming as (
    -- Parent : messages de la Direction
    select
      'direction-' || a.id::text as notification_id,
      'Message de la Direction'::text as title,
      a.body,
      a.created_at
    from public.parents p
    join public.student_parents sp on sp.parent_id = p.id
    join public.students s on s.id = sp.student_id
    join public.announcements a
      on (
        a.target_type in ('all','all_parents')
        or (a.target_type in ('class','class_parents') and a.class_id = s.class_id)
        or (a.target_type = 'student' and a.student_id = s.id)
        or (a.target_type = 'parent' and a.parent_id = p.id)
      )
    where p_role = 'parent'
      and p.access_code_hash = public.hash_code(p_code)
      and a.created_at > p_since

    union all

    -- Parent : messages d'un enseignant reçus dans la messagerie
    select
      'teacher-message-' || m.id::text,
      'Message de votre enseignant'::text,
      m.body,
      m.created_at
    from public.parents p
    join public.conversations c on c.parent_id = p.id
    join public.messages m on m.conversation_id = c.id
    where p_role = 'parent'
      and p.access_code_hash = public.hash_code(p_code)
      and m.sender_role = 'teacher'
      and m.created_at > p_since

    union all

    -- Enseignant : messages de la Direction à tous ou à cet enseignant
    select
      'direction-teacher-' || a.id::text,
      'Message de la Direction'::text,
      a.body,
      a.created_at
    from public.teachers t
    join public.announcements a
      on a.target_type = 'all_teachers'
      or (a.target_type = 'teacher' and a.teacher_id = t.id)
    where p_role = 'teacher'
      and t.access_code_hash = public.hash_code(p_code)
      and a.created_at > p_since

    union all

    -- Enseignant : message d'un parent
    select
      'parent-message-' || m.id::text,
      'Message d''un parent'::text,
      m.body,
      m.created_at
    from public.teachers t
    join public.conversations c on c.teacher_id = t.id
    join public.messages m on m.conversation_id = c.id
    where p_role = 'teacher'
      and t.access_code_hash = public.hash_code(p_code)
      and m.sender_role = 'parent'
      and m.created_at > p_since
  )
  select distinct on (notification_id)
    notification_id, title, body, created_at
  from incoming
  order by notification_id, created_at asc;
$$;

grant execute on function public.mobile_notifications(text,text,timestamptz) to anon, authenticated;

create index if not exists idx_announcements_teacher_created
  on public.announcements(teacher_id, created_at desc);

-- ============================================================
-- FIN V7
-- ============================================================
