-- =====================================================================
-- 하랑 업무 허브 (harangwork.co.kr) 데이터베이스 설정
-- Supabase > SQL Editor > New query 에 전체를 붙여 넣고 Run 한 번.
-- 여러 번 실행해도 안전하도록 작성됨.
-- =====================================================================

-- ---------- 1. 지점 ----------
create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort int not null default 0,
  created_at timestamptz not null default now()
);

-- ---------- 2. 직원 프로필 (로그인 계정 1개 = 프로필 1개) ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  login_id text unique,
  name text not null default '',
  role text not null default 'staff' check (role in ('admin','staff')),
  branch_id uuid references public.branches(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- 권한 확인 함수
create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active);
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and active and role = 'admin');
$$;

-- 계정이 만들어지면 프로필 자동 생성 (아이디 = 이메일 @ 앞부분)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, login_id, name)
  values (new.id, split_part(new.email, '@', 1),
          coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- 3. 광고 일일보고 (지점 × 날짜 1건) ----------
create table if not exists public.ad_days (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  branch_id uuid not null references public.branches(id) on delete cascade,
  items jsonb not null default '[]'::jsonb,
  total numeric not null default 0,
  excel_sum numeric,
  sheet text,
  file_name text,
  uploader uuid references public.profiles(id) on delete set null default auth.uid(),
  uploaded_at timestamptz not null default now(),
  unique (date, branch_id)
);

-- ---------- 4. 업무 보고 ----------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  author uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  type text not null check (type in ('daily','weekly')),
  date date not null,
  client_id uuid,
  done text not null default '',
  plan text not null default '',
  issue text not null default '',
  checked boolean not null default false,
  checked_at timestamptz,
  comment text not null default '',
  created_at timestamptz not null default now()
);

-- ---------- 5. 현장·거래처 ----------
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  site text not null default '',
  kind text not null default '파견',
  headcount int not null default 0,
  start_date date,
  end_date date,
  status text not null default 'active' check (status in ('active','talk','ending','closed')),
  manager text not null default '',
  memo text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.reports drop constraint if exists reports_client_fk;
alter table public.reports add constraint reports_client_fk foreign key (client_id) references public.clients(id) on delete set null;

-- ---------- 6. 업무 지시 ----------
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  detail text not null default '',
  assignee_id uuid references public.profiles(id) on delete set null,
  assignee_text text not null default '',
  due date,
  urgent boolean not null default false,
  status text not null default 'todo' check (status in ('todo','doing','done')),
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- 7. 공지·자료 ----------
create table if not exists public.notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null default '',
  link text not null default '',
  pinned boolean not null default false,
  author uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

-- ---------- 8. 주간 요약 (대표 전용) ----------
create table if not exists public.digests (
  week date primary key,
  body text not null,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

-- =====================================================================
-- 접근 권한: 로그인한 직원만, 비로그인(anon)은 아무것도 못 봄
-- =====================================================================
revoke all on public.branches, public.profiles, public.ad_days, public.reports,
  public.clients, public.tasks, public.notices, public.digests from anon;
grant select, insert, update, delete on public.branches, public.profiles, public.ad_days,
  public.reports, public.clients, public.tasks, public.notices, public.digests to authenticated;
grant execute on function public.is_member(), public.is_admin() to authenticated;

alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.ad_days  enable row level security;
alter table public.reports  enable row level security;
alter table public.clients  enable row level security;
alter table public.tasks    enable row level security;
alter table public.notices  enable row level security;
alter table public.digests  enable row level security;

-- 기존 정책 정리 후 다시 생성
do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname='public'
    and tablename in ('branches','profiles','ad_days','reports','clients','tasks','notices','digests')
  loop execute format('drop policy %I on public.%I', r.policyname, r.tablename); end loop;
end $$;

-- 지점: 직원 읽기 / 대표만 수정
create policy br_read  on public.branches for select to authenticated using (public.is_member());
create policy br_admin on public.branches for all    to authenticated using (public.is_admin()) with check (public.is_admin());

-- 프로필: 직원 읽기(이름 표시용) / 대표만 수정(역할·지점·비활성)
create policy pf_read  on public.profiles for select to authenticated using (public.is_member() or id = auth.uid());
create policy pf_admin on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- 광고 보고: 직원 읽기·올리기 / 삭제는 올린 사람 또는 대표
create policy ad_read  on public.ad_days for select to authenticated using (public.is_member());
create policy ad_ins   on public.ad_days for insert to authenticated with check (public.is_member() and uploader = auth.uid());
create policy ad_upd   on public.ad_days for update to authenticated using (public.is_member()) with check (public.is_member() and uploader = auth.uid());
create policy ad_del   on public.ad_days for delete to authenticated using (public.is_admin() or uploader = auth.uid());

-- 업무 보고: 직원은 자기 보고만, 대표는 전체
create policy rp_read  on public.reports for select to authenticated using (public.is_admin() or (public.is_member() and author = auth.uid()));
create policy rp_ins   on public.reports for insert to authenticated with check (public.is_member() and author = auth.uid());
create policy rp_upd   on public.reports for update to authenticated using (public.is_admin() or (author = auth.uid() and not checked)) with check (public.is_admin() or author = auth.uid());
create policy rp_del   on public.reports for delete to authenticated using (public.is_admin() or author = auth.uid());

-- 현장·거래처: 직원 읽기·등록·수정 / 삭제는 대표
create policy cl_read  on public.clients for select to authenticated using (public.is_member());
create policy cl_ins   on public.clients for insert to authenticated with check (public.is_member());
create policy cl_upd   on public.clients for update to authenticated using (public.is_member()) with check (public.is_member());
create policy cl_del   on public.clients for delete to authenticated using (public.is_admin());

-- 업무 지시: 직원 읽기·등록·상태변경 / 삭제는 대표 또는 등록자
create policy tk_read  on public.tasks for select to authenticated using (public.is_member());
create policy tk_ins   on public.tasks for insert to authenticated with check (public.is_member() and created_by = auth.uid());
create policy tk_upd   on public.tasks for update to authenticated using (public.is_member()) with check (public.is_member());
create policy tk_del   on public.tasks for delete to authenticated using (public.is_admin() or created_by = auth.uid());

-- 공지: 직원 읽기·작성 / 수정·삭제는 작성자 또는 대표
create policy nt_read  on public.notices for select to authenticated using (public.is_member());
create policy nt_ins   on public.notices for insert to authenticated with check (public.is_member() and author = auth.uid());
create policy nt_upd   on public.notices for update to authenticated using (public.is_admin() or author = auth.uid()) with check (public.is_admin() or author = auth.uid());
create policy nt_del   on public.notices for delete to authenticated using (public.is_admin() or author = auth.uid());

-- 주간 요약: 대표만
create policy dg_admin on public.digests for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- 기본 지점 ----------
insert into public.branches (name, sort) values ('본사', 1), ('천안', 2), ('아산', 3)
on conflict (name) do nothing;

select '설정 완료' as result;
