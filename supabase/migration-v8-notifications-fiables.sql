-- ============================================================
-- VIC-CONNECT V8 — Notifications fiables et plus claires
-- ============================================================
-- À exécuter APRÈS migration-v6 et migration-v7 (une seule fois, sans risque
-- si exécutée plusieurs fois : aucune donnée n'est modifiée ni supprimée).
--
-- Ce que fait cette migration :
--  1) mobile_server_time()      : heure officielle du serveur, utilisée par l'app
--                                 pour ne jamais rater un message (même si l'horloge
--                                 du téléphone est décalée).
--  2) mobile_notifications()    : notifications plus explicites
--       - « URGENT • Message de la Direction » pour les messages urgents
--       - titre du message + texte pour la Direction
--       - nom de l'enseignant + nom de l'élève pour les parents
--       - « Message du parent de <élève> » pour les enseignants
--     + marge de sécurité de 10 s (l'app ignore les doublons) et 30 max par appel.
-- ============================================================

-- Sécurité : vérifier que V7 a bien été exécutée.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'announcements' and column_name = 'teacher_id'
  ) then
    raise exception 'Exécutez d''abord migration-v6-messages-notifications.sql puis migration-v7-direction-targets-importance.sql.';
  end if;
end $$;

-- 1) Heure du serveur -------------------------------------------------------
create or replace function public.mobile_server_time()
returns timestamptz
language sql
security definer
set search_path = public
as $$
  select clock_timestamp();
$$;

grant execute on function public.mobile_server_time() to anon, authenticated;

-- 2) Flux de notifications Android -----------------------------------------
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
    -- Parent : message de la Direction (à tous, à sa classe, ou ciblé)
    select
      'direction-' || a.id::text as notification_id,
      case when a.importance = 'urgent'
           then 'URGENT • Message de la Direction'
           else 'Message de la Direction' end as title,
      (a.title || ' : ' || a.body) as body,
      a.created_at as created_at
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
      and a.created_at > (p_since - interval '10 seconds')

    union all

    -- Parent : message reçu d'un enseignant
    select
      'teacher-message-' || m.id::text,
      ('Message de ' || t.full_name || ' (' || s.full_name || ')'),
      m.body,
      m.created_at
    from public.parents p
    join public.conversations c on c.parent_id = p.id
    join public.teachers t on t.id = c.teacher_id
    join public.students s on s.id = c.student_id
    join public.messages m on m.conversation_id = c.id
    where p_role = 'parent'
      and p.access_code_hash = public.hash_code(p_code)
      and m.sender_role = 'teacher'
      and m.created_at > (p_since - interval '10 seconds')

    union all

    -- Enseignant : message de la Direction (à tous les enseignants ou à lui seul)
    select
      'direction-teacher-' || a.id::text,
      case when a.importance = 'urgent'
           then 'URGENT • Message de la Direction'
           else 'Message de la Direction' end,
      (a.title || ' : ' || a.body),
      a.created_at
    from public.teachers t
    join public.announcements a
      on a.target_type = 'all_teachers'
      or (a.target_type = 'teacher' and a.teacher_id = t.id)
    where p_role = 'teacher'
      and t.access_code_hash = public.hash_code(p_code)
      and a.created_at > (p_since - interval '10 seconds')

    union all

    -- Enseignant : message reçu d'un parent
    select
      'parent-message-' || m.id::text,
      ('Message du parent de ' || s.full_name),
      m.body,
      m.created_at
    from public.teachers t
    join public.conversations c on c.teacher_id = t.id
    join public.students s on s.id = c.student_id
    join public.messages m on m.conversation_id = c.id
    where p_role = 'teacher'
      and t.access_code_hash = public.hash_code(p_code)
      and m.sender_role = 'parent'
      and m.created_at > (p_since - interval '10 seconds')
  )
  select n.notification_id, n.title, n.body, n.created_at
  from (
    select distinct on (i.notification_id)
      i.notification_id, i.title, i.body, i.created_at
    from incoming i
    order by i.notification_id, i.created_at asc
  ) n
  order by n.created_at asc
  limit 30;
$$;

grant execute on function public.mobile_notifications(text, text, timestamptz) to anon, authenticated;

-- ============================================================
-- FIN V8
-- ============================================================
