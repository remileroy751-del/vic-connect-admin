-- ============================================================
-- VIC-CONNECT V9 — Diffusion des communiqués + suppression Direction
-- À exécuter dans Supabase APRÈS les migrations V6, V7 et V8.
-- Cette migration peut être exécutée plusieurs fois.
-- ============================================================

-- 1) Corrige/actualise la liste des communiqués visibles par un parent.
--    Les nouveaux types V7 sont explicitement pris en compte :
--    all_parents, class_parents, parent, student, ainsi que les anciens
--    all/class conservés pour compatibilité.
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
    on sp.parent_id = p.id
   and sp.student_id = p_student_id
  join public.students s
    on s.id = sp.student_id
  join public.announcements a
    on (
      a.target_type in ('all', 'all_parents')
      or (a.target_type in ('class', 'class_parents') and a.class_id = s.class_id)
      or (a.target_type = 'student' and a.student_id = s.id)
      or (a.target_type = 'parent' and a.parent_id = p.id)
    )
  where p.access_code_hash = public.hash_code(p_code)
  order by a.created_at desc;
$$;

grant execute on function public.student_announcements(text, uuid)
to anon, authenticated;

-- 2) Suppression sécurisée des communiqués par la Direction.
--    La vérification is_admin() empêche un utilisateur normal de supprimer
--    des messages. ON DELETE CASCADE supprime automatiquement les accusés
--    de réception liés au communiqué.
create or replace function public.admin_delete_announcements(
  p_announcement_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Accès Direction requis.';
  end if;

  if p_announcement_ids is null
     or cardinality(p_announcement_ids) = 0 then
    raise exception 'Aucun message sélectionné.';
  end if;

  delete from public.announcements
  where id = any(p_announcement_ids);

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.admin_delete_announcements(uuid[]) from public;
grant execute on function public.admin_delete_announcements(uuid[])
to authenticated;

-- Index utile pour les consultations parent après publication/suppression.
create index if not exists idx_announcements_student_target
  on public.announcements(student_id, created_at desc);

create index if not exists idx_announcements_parent_target
  on public.announcements(parent_id, created_at desc);

-- ============================================================
-- FIN V9
-- ============================================================
