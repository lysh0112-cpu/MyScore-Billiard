-- ══════════════════════════════════════════════════════════════════
--  큐보드 동우회 — 표 셋 만들기            2026-11-13
--
--  ⛔ score_games · score_results 는 ★한 줄도 건드리지 않습니다.
--     명카페 · My Score · 골프온은 ★영향이 없습니다.
--  ★ 여러 번 돌려도 안전합니다 (있으면 그냥 넘어갑니다).
--  ★ 지금 돌려도 앱은 ★아직 이 표를 쓰지 않습니다 — 다음 판부터 씁니다.
--
--  붙여 넣는 곳
--    https://supabase.com/dashboard/project/auvuwytatfcoawdrgunl/sql/new
--    → 전부 붙여넣고 [Run]
-- ══════════════════════════════════════════════════════════════════

-- ───────── ① 동우회 ─────────
create table if not exists public.cue_clubs (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  code       text not null default lpad((floor(random()*900000)+100000)::int::text, 6, '0'),
  owner      uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);
create unique index if not exists cue_clubs_code_key on public.cue_clubs (code);
create index        if not exists cue_clubs_owner_idx on public.cue_clubs (owner);

-- ───────── ② 명단 ─────────
--  user_id 가 비어 있으면 = 총무가 «이름만» 올려 둔 분 (아직 수락 안 함)
create table if not exists public.cue_club_members (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.cue_clubs(id) on delete cascade,
  user_id    uuid,
  name       text not null,
  h3         int     default 0,      -- 3쿠션 수지
  e3         numeric default 0,      -- 3쿠션 신고 에버
  h4         int     default 0,      -- 4구 수지
  e4         numeric default 0,      -- 4구 신고 에버
  phone      text,                   -- ★총무만 봅니다
  role       text not null default 'member',    -- admin | member
  status     text not null default 'invited',   -- invited | active
  local_mid  text,                   -- 총무 기계에 있던 회원 번호 (옮겨 붙일 때)
  created_at timestamptz not null default now()
);
create unique index if not exists cue_members_user_key
  on public.cue_club_members (club_id, user_id) where user_id is not null;
create index if not exists cue_members_club_idx on public.cue_club_members (club_id);

-- ───────── ③ 동우회에 올린 경기 «사본» ─────────
--  client_id = 그 기계에서 쓰던 경기 번호. 같은 판이 두 번 올라오는 것을 막습니다.
create table if not exists public.cue_club_games (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.cue_clubs(id) on delete cascade,
  owner      uuid not null default auth.uid(),
  client_id  text not null,
  played_on  date,
  mode       text,
  data       jsonb not null,
  created_at timestamptz not null default now()
);
create unique index if not exists cue_games_key on public.cue_club_games (club_id, client_id);
create index if not exists cue_games_club_date_idx on public.cue_club_games (club_id, played_on desc);

-- ══════════════════════════════════════════════════════════════════
--  누가 무엇을 볼 수 있는가
-- ══════════════════════════════════════════════════════════════════

-- 「나는 이 동우회 사람인가」
--  ⚠ security definer 라야 합니다. 안 그러면 규칙이 ★자기를 다시 불러 맴돕니다.
create or replace function public.cue_is_member(p_club uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.cue_club_members m
     where m.club_id = p_club and m.user_id = auth.uid() and m.status = 'active');
$$;

-- 「나는 이 동우회 총무인가」
create or replace function public.cue_is_admin(p_club uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.cue_clubs c
                  where c.id = p_club and c.owner = auth.uid())
      or exists (select 1 from public.cue_club_members m
                  where m.club_id = p_club and m.user_id = auth.uid()
                    and m.status = 'active' and m.role = 'admin');
$$;

-- 동우회를 만들면 ★만든 사람이 총무로 명단에 들어갑니다
create or replace function public.cue_club_born()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.cue_club_members (club_id, user_id, name, role, status)
  values (new.id, new.owner, '총무', 'admin', 'active');
  return new;
end; $$;
drop trigger if exists cue_club_born on public.cue_clubs;
create trigger cue_club_born after insert on public.cue_clubs
  for each row execute function public.cue_club_born();

-- 초대 코드로 들어가기
--  ① 이미 든 사람이면 그대로
--  ② 총무가 «이름만» 올려 둔 줄이 있으면 ★그 줄을 잇습니다 (지난 기록이 따라옵니다)
--  ③ 없으면 새로 한 줄 넣습니다
create or replace function public.cue_join(p_code text, p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_club uuid; v_id uuid;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;

  select id into v_club from public.cue_clubs where code = p_code;
  if v_club is null then raise exception '초대 코드가 맞지 않습니다'; end if;

  select id into v_id from public.cue_club_members
   where club_id = v_club and user_id = auth.uid();
  if v_id is not null then
    update public.cue_club_members set status = 'active' where id = v_id;
    return v_club;
  end if;

  select id into v_id from public.cue_club_members
   where club_id = v_club and user_id is null and name = p_name
   order by created_at limit 1;
  if v_id is not null then
    update public.cue_club_members
       set user_id = auth.uid(), status = 'active'
     where id = v_id;
    return v_club;
  end if;

  insert into public.cue_club_members (club_id, user_id, name, status)
  values (v_club, auth.uid(), coalesce(nullif(p_name, ''), '회원'), 'active');
  return v_club;
end; $$;

alter table public.cue_clubs        enable row level security;
alter table public.cue_club_members enable row level security;
alter table public.cue_club_games   enable row level security;

-- ① 동우회
drop policy if exists cue_clubs_sel on public.cue_clubs;
create policy cue_clubs_sel on public.cue_clubs for select to authenticated
  using (owner = auth.uid() or public.cue_is_member(id));
drop policy if exists cue_clubs_ins on public.cue_clubs;
create policy cue_clubs_ins on public.cue_clubs for insert to authenticated
  with check (owner = auth.uid());
drop policy if exists cue_clubs_upd on public.cue_clubs;
create policy cue_clubs_upd on public.cue_clubs for update to authenticated
  using (public.cue_is_admin(id)) with check (public.cue_is_admin(id));
drop policy if exists cue_clubs_del on public.cue_clubs;
create policy cue_clubs_del on public.cue_clubs for delete to authenticated
  using (owner = auth.uid());

-- ② 명단 — ★총무만 고칩니다. 본인은 ★자기 줄만 고칩니다.
drop policy if exists cue_mem_sel on public.cue_club_members;
create policy cue_mem_sel on public.cue_club_members for select to authenticated
  using (user_id = auth.uid() or public.cue_is_member(club_id) or public.cue_is_admin(club_id));
drop policy if exists cue_mem_ins on public.cue_club_members;
create policy cue_mem_ins on public.cue_club_members for insert to authenticated
  with check (public.cue_is_admin(club_id));
drop policy if exists cue_mem_upd on public.cue_club_members;
create policy cue_mem_upd on public.cue_club_members for update to authenticated
  using  (public.cue_is_admin(club_id) or user_id = auth.uid())
  with check (public.cue_is_admin(club_id) or user_id = auth.uid());
drop policy if exists cue_mem_del on public.cue_club_members;
create policy cue_mem_del on public.cue_club_members for delete to authenticated
  using (public.cue_is_admin(club_id));

-- ③ 경기 — 동우회 사람이면 ★누가 적었든 봅니다.
--           지우는 것은 ★적은 사람과 총무만.
drop policy if exists cue_game_sel on public.cue_club_games;
create policy cue_game_sel on public.cue_club_games for select to authenticated
  using (public.cue_is_member(club_id) or public.cue_is_admin(club_id));
drop policy if exists cue_game_ins on public.cue_club_games;
create policy cue_game_ins on public.cue_club_games for insert to authenticated
  with check (owner = auth.uid()
              and (public.cue_is_member(club_id) or public.cue_is_admin(club_id)));
drop policy if exists cue_game_upd on public.cue_club_games;
create policy cue_game_upd on public.cue_club_games for update to authenticated
  using  (owner = auth.uid() or public.cue_is_admin(club_id))
  with check (owner = auth.uid() or public.cue_is_admin(club_id));
drop policy if exists cue_game_del on public.cue_club_games;
create policy cue_game_del on public.cue_club_games for delete to authenticated
  using (owner = auth.uid() or public.cue_is_admin(club_id));

grant select, insert, update, delete
  on public.cue_clubs, public.cue_club_members, public.cue_club_games
  to authenticated;
grant execute on function public.cue_join(text, text)   to authenticated;
grant execute on function public.cue_is_member(uuid)    to authenticated;
grant execute on function public.cue_is_admin(uuid)     to authenticated;

-- ══════════════════════════════════════════════════════════════════
--  ★ 제대로 됐는지 — 아래가 함께 나오면 끝난 것입니다
-- ══════════════════════════════════════════════════════════════════
select '표'::text as 무엇, table_name::text as 이름 from information_schema.tables
 where table_schema = 'public' and table_name::text like 'cue_%'
union all
select '함수'::text, routine_name::text from information_schema.routines
 where routine_schema = 'public' and routine_name::text like 'cue_%'
union all
select ('규칙 ' || tablename)::text, policyname::text from pg_policies
 where schemaname = 'public' and tablename like 'cue_%'
order by 1, 2;
