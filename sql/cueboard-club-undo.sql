-- ⛔ 되돌리기 — 만든 것을 ★전부 지웁니다 (동우회 자료도 함께 사라집니다)
--    score_games 는 ★그대로입니다.
drop table if exists public.cue_club_games   cascade;
drop table if exists public.cue_club_members cascade;
drop table if exists public.cue_clubs        cascade;
drop function if exists public.cue_join(text, text);
drop function if exists public.cue_is_member(uuid);
drop function if exists public.cue_is_admin(uuid);
drop function if exists public.cue_club_born();
