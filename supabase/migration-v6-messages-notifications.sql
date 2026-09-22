-- ============================================================
-- VIC-CONNECT V6 — Messages Direction + notifications + session
-- ============================================================
-- Migration non destructive.
-- À exécuter sur la base VIC-CONNECT existante.
-- ============================================================

-- 1) Étendre les destinataires des messages de la Direction.
do $$
declare
  r record;
begin
  -- Supprimer les anciens CHECK qui encadrent target_type / les anciennes cibles.
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
  (target_type = 'all' and class_id is null and student_id is null and parent_id is null)
  or (target_type = 'class' and class_id is not null and student_id is null and parent_id is null)
  or (target_type = 'student' and student_id is not null and parent_id is null)
  or (target_type = 'parent' and parent_id is not null)
  or (target_type = 'all_parents' and class_id is null and student_id is null and parent_id is null)
  or (target_type = 'class_parents' and class_id is not null and student_id is null and parent_id is null)
  or (target_type = 'all_teachers' and class_id is null and student_id is null and parent_id is null)
);

-- 2) Recréer l'outil Direction avec les 3 nouveaux choix.
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

  if p_target_type not in ('all_parents','class_parents','all_teachers') then
    raise exception 'Destinataire invalide.';
  end if;

  if p_target_type = 'all_parents'
     and (p_class_id is not null or p_student_id is not null or p_parent_id is not null) then
    raise exception 'Le message à tous les parents ne doit pas avoir de cible précise.';
  end if;

  if p_target_type = 'class_parents' and p_class_id is null then
    raise exception 'La classe est obligatoire.';
  end if;

  if p_target_type = 'all_teachers'
     and (p_class_id is not null or p_student_id is not null or p_parent_id is not null) then
    raise exception 'Le message à tous les enseignants ne doit pas avoir de cible précise.';
  end if;

  insert into public.announcements(
    title, body, importance, target_type,
    class_id, student_id, parent_id, created_by
  )
  values (
    trim(p_title), trim(p_body), p_importance, p_target_type,
    p_class_id, null, null, auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object(
    'success', true,
    'announcement_id', v_id
  );
end;
$$;

grant execute on function public.admin_create_announcement(text,text,text,text,uuid,uuid,uuid) to authenticated;

-- 3) Messages Direction visibles dans le compte enseignant.
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
  where t.access_code_hash = public.hash_code(p_code)
  order by a.created_at desc;
$$;

grant execute on function public.teacher_announcements(text) to anon, authenticated;

-- 4) Le compte parent continue à recevoir les anciens communiqués,
--    mais reçoit aussi les nouveaux messages « à tous les parents »
--    et « aux parents d'une classe ».
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
      a.target_type in ('all','all_parents')
      or (a.target_type in ('class','class_parents') and a.class_id = s.class_id)
      or (a.target_type = 'student' and a.student_id = s.id)
      or (a.target_type = 'parent' and a.parent_id = p.id)
    )
  where p.access_code_hash = public.hash_code(p_code)
  order by a.created_at desc;
$$;

grant execute on function public.student_announcements(text,uuid) to anon, authenticated;

-- 5) Flux commun pour les notifications Android.
--    Parent : Direction + messages enseignant reçus.
--    Enseignant : Direction + messages parent reçus.
--    p_since est un timestamp UTC conservé localement par l'application.
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
    -- Parents : messages de la Direction
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

    -- Parent : messages d'un enseignant
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

    -- Enseignant : message de la Direction
    select
      'direction-teacher-' || a.id::text,
      'Message de la Direction'::text,
      a.body,
      a.created_at
    from public.teachers t
    join public.announcements a on a.target_type = 'all_teachers'
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

-- 6) Index utiles pour la surveillance des nouveaux événements.
create index if not exists idx_announcements_target_created
  on public.announcements(target_type, created_at desc);

create index if not exists idx_messages_created
  on public.messages(created_at desc);

-- ============================================================
-- FIN V6
-- ============================================================
