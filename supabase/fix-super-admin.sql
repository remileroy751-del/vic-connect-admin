-- VIC-CONNECT - Correctif sécurisé du Super Admin
-- À exécuter APRÈS le schéma principal (schema-corrige.sql).
-- Ce script ne supprime aucune table ni aucune donnée.

create or replace function public.bootstrap_admin(p_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  mail text := coalesce(p_email, '');
  admin_count integer;
begin
  if uid is null then
    raise exception 'Vous devez être connecté avec un compte Supabase Auth.';
  end if;

  select count(*) into admin_count from public.admin_users;

  -- Le bootstrap est autorisé uniquement lorsqu'aucun compte Direction
  -- n'existe encore, ou si l'utilisateur connecté est déjà administrateur.
  if admin_count > 0 and not exists (
    select 1 from public.admin_users where user_id = uid
  ) then
    raise exception 'Un compte Direction existe déjà. Seul un administrateur peut activer un autre compte Direction.';
  end if;

  insert into public.admin_users(user_id, email)
  values (uid, nullif(mail, ''))
  on conflict (user_id) do update
    set email = coalesce(excluded.email, public.admin_users.email);

  return jsonb_build_object(
    'success', true,
    'message', 'Compte Direction activé.'
  );
end;
$$;

grant execute on function public.bootstrap_admin(text) to authenticated;

-- Vérification facultative :
-- select * from public.admin_users;
