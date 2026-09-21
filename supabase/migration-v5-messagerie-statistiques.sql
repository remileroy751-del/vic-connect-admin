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
