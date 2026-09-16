-- VIC-CONNECT / VIC-INTELLIGENTSIA
-- Supabase PostgreSQL schema + security + RPC API
create extension if not exists pgcrypto;

create table if not exists classes (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  level_code text not null unique check (level_code in ('6E','5E','4E','3E')),
  created_at timestamptz not null default now()
);

insert into classes(name, level_code) values
('6ième','6E'),('5ième','5E'),('4ième','4E'),('3ième','3E')
on conflict do nothing;

create table if not exists subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

insert into subjects(name) values
('Français'),('Anglais'),('Mathématiques'),('Sciences Physiques'),
('SVT'),('Histoire-Géographie'),('Informatique'),('Éducation Physique et Sportive'),
('Technologie'),('Éducation Civique')
on conflict do nothing;

create table if not exists parents (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  email text,
  access_code_hash text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists teachers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  email text,
  primary_subject_id uuid references subjects(id),
  access_code_hash text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists students (
  id uuid primary key default gen_random_uuid(),
  first_name text not null,
  last_name text not null,
  matricule text unique,
  class_id uuid not null references classes(id),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists student_parents (
  student_id uuid references students(id) on delete cascade,
  parent_id uuid references parents(id) on delete cascade,
  relationship text not null default 'parent',
  primary key(student_id,parent_id)
);

create table if not exists teacher_assignments (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references teachers(id) on delete cascade,
  class_id uuid not null references classes(id) on delete cascade,
  subject_id uuid not null references subjects(id),
  is_homeroom boolean not null default false,
  unique(teacher_id,class_id,subject_id)
);

create table if not exists notes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  teacher_assignment_id uuid not null references teacher_assignments(id) on delete cascade,
  term text not null check(term in ('1er trimestre','2e trimestre','3e trimestre')),
  note_type text not null check(note_type in ('devoir','moyenne_classe','composition')),
  label text not null default '',
  value numeric(5,2) not null check(value >= 0 and value <= 20),
  entered_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_class_avg on notes(student_id,teacher_assignment_id,term,note_type) where note_type='moyenne_classe';
create unique index if not exists uq_composition on notes(student_id,teacher_assignment_id,term,note_type) where note_type='composition';

create table if not exists announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  importance text not null check(importance in ('jaune','orange','rouge')),
  target_type text not null check(target_type in ('all','class','student','parent')),
  class_id uuid references classes(id),
  student_id uuid references students(id),
  parent_id uuid references parents(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check (
    (target_type='all' and class_id is null and student_id is null and parent_id is null) or
    (target_type='class' and class_id is not null and student_id is null and parent_id is null) or
    (target_type='student' and student_id is not null and parent_id is null) or
    (target_type='parent' and parent_id is not null and student_id is null)
  )
);

create table if not exists announcement_receipts (
  announcement_id uuid references announcements(id) on delete cascade,
  parent_id uuid references parents(id) on delete cascade,
  acknowledged_at timestamptz not null default now(),
  primary key(announcement_id,parent_id)
);

create table if not exists conversations (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references parents(id) on delete cascade,
  teacher_id uuid not null references teachers(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(parent_id,teacher_id,student_id)
);

create table if not exists messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_role text not null check(sender_role in ('parent','teacher')),
  sender_parent_id uuid references parents(id),
  sender_teacher_id uuid references teachers(id),
  body text not null check(length(trim(body))>0),
  created_at timestamptz not null default now()
);

create table if not exists admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'Direction générale',
  created_at timestamptz not null default now()
);

create index if not exists idx_students_class on students(class_id);
create index if not exists idx_assignments_teacher on teacher_assignments(teacher_id);
create index if not exists idx_notes_student_term on notes(student_id,term);
create index if not exists idx_announcements_created on announcements(created_at desc);
create index if not exists idx_messages_conversation on messages(conversation_id,created_at);

alter table classes enable row level security;
alter table subjects enable row level security;
alter table parents enable row level security;
alter table teachers enable row level security;
alter table students enable row level security;
alter table student_parents enable row level security;
alter table teacher_assignments enable row level security;
alter table notes enable row level security;
alter table announcements enable row level security;
alter table announcement_receipts enable row level security;
alter table conversations enable row level security;
alter table messages enable row level security;
alter table admin_users enable row level security;

-- Direct table access is intentionally restricted. Mobile clients use the SECURITY DEFINER RPC API.
do $$ declare t text; begin
  foreach t in array array[
    'classes','subjects','parents','teachers','students','student_parents',
    'teacher_assignments','notes','announcements','announcement_receipts',
    'conversations','messages','admin_users'
  ] loop
    execute format('drop policy if exists deny_all_%s on %I', t, t);
    execute format('create policy deny_all_%s on %I for all to anon using(false) with check(false)', t, t);
  end loop;
end $$;

create or replace function is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from admin_users where user_id=auth.uid()) $$;

create or replace function make_code(p_len integer)
returns text language plpgsql security definer set search_path=public as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i integer;
begin
  for i in 1..p_len loop
    result := result || substr(alphabet, floor(random()*length(alphabet))::int+1, 1);
  end loop;
  return result;
end $$;

create or replace function hash_code(p_code text)
returns text language sql immutable security definer set search_path=public
as $$ select encode(digest(upper(trim(p_code)), 'sha256'), 'hex') $$;

-- First direction account can bootstrap itself after signing up in Supabase Auth.
create or replace function bootstrap_admin(p_full_name text default 'Direction générale')
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  if exists(select 1 from admin_users) then
    raise exception 'Le compte direction est déjà initialisé';
  end if;
  insert into admin_users(user_id,full_name) values(auth.uid(),coalesce(nullif(trim(p_full_name),''),'Direction générale'));
  return jsonb_build_object('ok',true);
end $$;
grant execute on function bootstrap_admin(text) to authenticated;

create or replace function admin_create_student(
  p_first_name text,p_last_name text,p_matricule text,p_class_id uuid,
  p_parent_name text,p_parent_phone text,p_parent_email text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_parent uuid; v_code text; v_student uuid; v_hash text;
begin
  if not is_admin() then raise exception 'Accès direction requis'; end if;
  select p.id into v_parent from parents p
  where (p_parent_phone is not null and p.phone=p_parent_phone)
     or (p_parent_email is not null and lower(p.email)=lower(p_parent_email))
  limit 1;

  if v_parent is null then
    loop
      v_code := make_code(4); v_hash := hash_code(v_code);
      exit when not exists(select 1 from parents where access_code_hash=v_hash);
    end loop;
    insert into parents(full_name,phone,email,access_code_hash)
    values(trim(p_parent_name),nullif(trim(p_parent_phone),''),nullif(trim(p_parent_email),''),v_hash)
    returning id into v_parent;
  end if;

  insert into students(first_name,last_name,matricule,class_id)
  values(trim(p_first_name),trim(p_last_name),nullif(trim(p_matricule),''),p_class_id)
  returning id into v_student;
  insert into student_parents(student_id,parent_id) values(v_student,v_parent);

  return jsonb_build_object('student_id',v_student,'parent_id',v_parent,
    'new_parent_code',case when v_code is null then null else v_code end);
end $$;
grant execute on function admin_create_student(text,text,text,uuid,text,text,text) to authenticated;

create or replace function admin_create_teacher(
  p_full_name text,p_phone text,p_email text,p_subject_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_code text; v_hash text;
begin
  if not is_admin() then raise exception 'Accès direction requis'; end if;
  loop
    v_code := make_code(5); v_hash := hash_code(v_code);
    exit when not exists(select 1 from teachers where access_code_hash=v_hash);
  end loop;
  insert into teachers(full_name,phone,email,primary_subject_id,access_code_hash)
  values(trim(p_full_name),nullif(trim(p_phone),''),nullif(trim(p_email),''),p_subject_id,v_hash)
  returning id into v_id;
  return jsonb_build_object('teacher_id',v_id,'access_code',v_code);
end $$;
grant execute on function admin_create_teacher(text,text,text,uuid) to authenticated;

create or replace function admin_assign_teacher(
  p_teacher_id uuid,p_class_id uuid,p_subject_id uuid,p_is_homeroom boolean default false
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not is_admin() then raise exception 'Accès direction requis'; end if;
  insert into teacher_assignments(teacher_id,class_id,subject_id,is_homeroom)
  values(p_teacher_id,p_class_id,p_subject_id,p_is_homeroom)
  on conflict(teacher_id,class_id,subject_id) do update set is_homeroom=excluded.is_homeroom
  returning id into v_id;
  return jsonb_build_object('assignment_id',v_id);
end $$;
grant execute on function admin_assign_teacher(uuid,uuid,uuid,boolean) to authenticated;

create or replace function admin_reset_parent_code(p_parent_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_code text; v_hash text;
begin
  if not is_admin() then raise exception 'Accès direction requis'; end if;
  loop v_code:=make_code(4); v_hash:=hash_code(v_code); exit when not exists(select 1 from parents where access_code_hash=v_hash); end loop;
  update parents set access_code_hash=v_hash where id=p_parent_id;
  return jsonb_build_object('parent_id',p_parent_id,'access_code',v_code);
end $$;
grant execute on function admin_reset_parent_code(uuid) to authenticated;

create or replace function admin_reset_teacher_code(p_teacher_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_code text; v_hash text;
begin
  if not is_admin() then raise exception 'Accès direction requis'; end if;
  loop v_code:=make_code(5); v_hash:=hash_code(v_code); exit when not exists(select 1 from teachers where access_code_hash=v_hash); end loop;
  update teachers set access_code_hash=v_hash where id=p_teacher_id;
  return jsonb_build_object('teacher_id',p_teacher_id,'access_code',v_code);
end $$;
grant execute on function admin_reset_teacher_code(uuid) to authenticated;

create or replace function admin_create_announcement(
  p_title text,p_body text,p_importance text,p_target_type text,
  p_class_id uuid default null,p_student_id uuid default null,p_parent_id uuid default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not is_admin() then raise exception 'Accès direction requis'; end if;
  insert into announcements(title,body,importance,target_type,class_id,student_id,parent_id,created_by)
  values(p_title,p_body,p_importance,p_target_type,p_class_id,p_student_id,p_parent_id,auth.uid())
  returning id into v_id;
  return v_id;
end $$;
grant execute on function admin_create_announcement(text,text,text,text,uuid,uuid,uuid) to authenticated;

create or replace function login_with_access_code(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_parent parents%rowtype; v_teacher teachers%rowtype;
begin
  select * into v_parent from parents where access_code_hash=hash_code(p_code) and active=true limit 1;
  if found then return jsonb_build_object('role','parent','id',v_parent.id,'name',v_parent.full_name); end if;
  select * into v_teacher from teachers where access_code_hash=hash_code(p_code) and active=true limit 1;
  if found then return jsonb_build_object('role','teacher','id',v_teacher.id,'name',v_teacher.full_name); end if;
  raise exception 'Code invalide';
end $$;
grant execute on function login_with_access_code(text) to anon,authenticated;

create or replace function parent_children(p_code text)
returns table(id uuid,first_name text,last_name text,class_name text)
language sql security definer set search_path=public as $$
select s.id,s.first_name,s.last_name,c.name
from students s join student_parents sp on sp.student_id=s.id
join parents p on p.id=sp.parent_id join classes c on c.id=s.class_id
where p.access_code_hash=hash_code(p_code) and p.active=true and s.active=true
order by s.last_name,s.first_name
$$;
grant execute on function parent_children(text) to anon,authenticated;

create or replace function parent_child_teachers(p_code text,p_student_id uuid)
returns table(id uuid,name text)
language sql security definer set search_path=public as $$
select distinct t.id,t.full_name
from teachers t join teacher_assignments ta on ta.teacher_id=t.id
join students s on s.class_id=ta.class_id
join student_parents sp on sp.student_id=s.id
join parents p on p.id=sp.parent_id
where p.access_code_hash=hash_code(p_code) and s.id=p_student_id and t.active=true
order by t.full_name
$$;
grant execute on function parent_child_teachers(text,uuid) to anon,authenticated;

create or replace function student_notes(p_code text,p_student_id uuid,p_term text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_parent uuid; v_notes jsonb; v_avg numeric;
begin
  select p.id into v_parent from parents p join student_parents sp on sp.parent_id=p.id
  where sp.student_id=p_student_id and p.access_code_hash=hash_code(p_code) and p.active=true limit 1;
  if v_parent is null then raise exception 'Accès refusé'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'subject',sub.name,'note_type',n.note_type,'label',n.label,'value',n.value,'term',n.term,
    'subject_average',sa.subject_average
  ) order by sub.name,n.note_type,n.label),'[]'::jsonb)
  into v_notes
  from notes n
  join teacher_assignments ta on ta.id=n.teacher_assignment_id
  join subjects sub on sub.id=ta.subject_id
  left join lateral (
    select round((max(case when n2.note_type='moyenne_classe' then n2.value end)+max(case when n2.note_type='composition' then n2.value end))/2,2) subject_average
    from notes n2 where n2.student_id=n.student_id and n2.teacher_assignment_id=n.teacher_assignment_id and n2.term=n.term
  ) sa on true
  where n.student_id=p_student_id and n.term=p_term;

  select round(avg(x.subject_average),2) into v_avg
  from (
    select ta.subject_id, (max(case when n.note_type='moyenne_classe' then n.value end)+max(case when n.note_type='composition' then n.value end))/2 subject_average
    from notes n join teacher_assignments ta on ta.id=n.teacher_assignment_id
    where n.student_id=p_student_id and n.term=p_term
    group by ta.subject_id,ta.id
    having max(case when n.note_type='moyenne_classe' then n.value end) is not null
       and max(case when n.note_type='composition' then n.value end) is not null
  ) x;
  return jsonb_build_object('notes',v_notes,'general_average',v_avg);
end $$;
grant execute on function student_notes(text,uuid,text) to anon,authenticated;

create or replace function student_announcements(p_code text,p_student_id uuid)
returns table(id uuid,title text,body text,importance text,created_at timestamptz,acknowledged boolean)
language sql security definer set search_path=public as $$
select a.id,a.title,a.body,a.importance,a.created_at,
exists(select 1 from announcement_receipts r where r.announcement_id=a.id and r.parent_id=p.id)
from announcements a
join students s on (a.target_type='all' or (a.target_type='class' and a.class_id=s.class_id) or (a.target_type='student' and a.student_id=s.id))
join student_parents sp on sp.student_id=s.id
join parents p on p.id=sp.parent_id
where s.id=p_student_id and p.access_code_hash=hash_code(p_code) and
(a.target_type <> 'parent' or a.parent_id=p.id)
or (a.target_type='parent' and a.parent_id=p.id)
order by a.created_at desc
$$;
grant execute on function student_announcements(text,uuid) to anon,authenticated;

create or replace function acknowledge_announcement(p_code text,p_announcement_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_parent uuid;
begin
  select id into v_parent from parents where access_code_hash=hash_code(p_code) and active=true limit 1;
  if v_parent is null then raise exception 'Accès refusé'; end if;
  if not exists(select 1 from announcements a where a.id=p_announcement_id and (
    a.target_type='all' or a.target_type='parent' and a.parent_id=v_parent or
    a.target_type='student' and exists(select 1 from student_parents sp where sp.student_id=a.student_id and sp.parent_id=v_parent) or
    a.target_type='class' and exists(select 1 from student_parents sp join students s on s.id=sp.student_id where sp.parent_id=v_parent and s.class_id=a.class_id)
  )) then raise exception 'Message non destiné à ce parent'; end if;
  insert into announcement_receipts values(p_announcement_id,v_parent,now()) on conflict do nothing;
  return true;
end $$;
grant execute on function acknowledge_announcement(text,uuid) to anon,authenticated;

create or replace function conversation_messages(p_code text,p_student_id uuid,p_teacher_id uuid)
returns table(id uuid,sender_role text,body text,created_at timestamptz)
language sql security definer set search_path=public as $$
select m.id,m.sender_role,m.body,m.created_at
from messages m join conversations c on c.id=m.conversation_id
join parents p on p.id=c.parent_id
where p.access_code_hash=hash_code(p_code) and c.student_id=p_student_id and c.teacher_id=p_teacher_id
order by m.created_at
$$;
grant execute on function conversation_messages(text,uuid,uuid) to anon,authenticated;

create or replace function send_parent_message(p_code text,p_student_id uuid,p_teacher_id uuid,p_body text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_parent uuid; v_conv uuid; v_id uuid;
begin
  select id into v_parent from parents where access_code_hash=hash_code(p_code) and active=true limit 1;
  if v_parent is null then raise exception 'Accès refusé'; end if;
  if not exists(select 1 from students s join student_parents sp on sp.student_id=s.id where s.id=p_student_id and sp.parent_id=v_parent) then raise exception 'Enfant non autorisé'; end if;
  if not exists(select 1 from teacher_assignments ta where ta.teacher_id=p_teacher_id and ta.class_id=(select class_id from students where id=p_student_id)) then raise exception 'Enseignant non autorisé'; end if;
  insert into conversations(parent_id,teacher_id,student_id) values(v_parent,p_teacher_id,p_student_id)
  on conflict(parent_id,teacher_id,student_id) do update set parent_id=excluded.parent_id
  returning id into v_conv;
  insert into messages(conversation_id,sender_role,sender_parent_id,body) values(v_conv,'parent',v_parent,trim(p_body)) returning id into v_id;
  return v_id;
end $$;
grant execute on function send_parent_message(text,uuid,uuid,text) to anon,authenticated;

create or replace function teacher_classes(p_code text)
returns table(class_id uuid,class_name text)
language sql security definer set search_path=public as $$
select distinct c.id,c.name from classes c join teacher_assignments ta on ta.class_id=c.id
join teachers t on t.id=ta.teacher_id where t.access_code_hash=hash_code(p_code) and t.active=true order by c.name
$$;
grant execute on function teacher_classes(text) to anon,authenticated;

create or replace function teacher_students(p_code text,p_class_id uuid)
returns table(student_id uuid,first_name text,last_name text)
language sql security definer set search_path=public as $$
select s.id,s.first_name,s.last_name from students s
where s.class_id=p_class_id and s.active and exists(
 select 1 from teacher_assignments ta join teachers t on t.id=ta.teacher_id
 where ta.class_id=p_class_id and t.access_code_hash=hash_code(p_code) and t.active=true
) order by s.last_name,s.first_name
$$;
grant execute on function teacher_students(text,uuid) to anon,authenticated;

create or replace function teacher_student_notes(p_code text,p_class_id uuid,p_term text,p_student_id uuid)
returns table(subject text,note_type text,label text,value numeric)
language sql security definer set search_path=public as $$
select sub.name,n.note_type,n.label,n.value from notes n
join teacher_assignments ta on ta.id=n.teacher_assignment_id join subjects sub on sub.id=ta.subject_id
join teachers t on t.id=ta.teacher_id
where n.student_id=p_student_id and ta.class_id=p_class_id and t.access_code_hash=hash_code(p_code) and n.term=p_term
order by sub.name,n.note_type,n.label
$$;
grant execute on function teacher_student_notes(text,uuid,text,uuid) to anon,authenticated;

create or replace function teacher_save_note(
 p_code text,p_class_id uuid,p_student_id uuid,p_term text,p_note_type text,p_label text,p_value numeric
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_teacher uuid; v_assignment uuid; v_id uuid;
begin
 select id into v_teacher from teachers where access_code_hash=hash_code(p_code) and active=true limit 1;
 if v_teacher is null then raise exception 'Accès refusé'; end if;
 if not exists(select 1 from students where id=p_student_id and class_id=p_class_id) then raise exception 'Élève hors classe'; end if;
 select ta.id into v_assignment from teacher_assignments ta
 where ta.teacher_id=v_teacher and ta.class_id=p_class_id limit 1;
 if v_assignment is null then raise exception 'Classe non autorisée'; end if;
 if p_value < 0 or p_value > 20 then raise exception 'Note invalide'; end if;
 if p_note_type in ('moyenne_classe','composition') then
   insert into notes(student_id,teacher_assignment_id,term,note_type,label,value)
   values(p_student_id,v_assignment,p_term,p_note_type,p_label,p_value)
   on conflict do nothing;
   update notes set value=p_value,label=p_label,updated_at=now()
   where student_id=p_student_id and teacher_assignment_id=v_assignment and term=p_term and note_type=p_note_type
   returning id into v_id;
 else
   insert into notes(student_id,teacher_assignment_id,term,note_type,label,value)
   values(p_student_id,v_assignment,p_term,'devoir',coalesce(nullif(trim(p_label),''),'Devoir'),p_value)
   returning id into v_id;
 end if;
 return v_id;
end $$;
grant execute on function teacher_save_note(text,uuid,uuid,text,text,text,numeric) to anon,authenticated;

-- Allow admin web direct SELECT/INSERT/UPDATE through authenticated policies.
create policy admin_all_classes on classes for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all_subjects on subjects for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all_parents on parents for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all_teachers on teachers for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all_students on students for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all_student_parents on student_parents for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all_assignments on teacher_assignments for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all_notes on notes for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all_announcements on announcements for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all_receipts on announcement_receipts for select to authenticated using(is_admin());
create policy admin_all_conversations on conversations for select to authenticated using(is_admin());
create policy admin_all_messages on messages for select to authenticated using(is_admin());
create policy admin_self on admin_users for select to authenticated using(user_id=auth.uid());
