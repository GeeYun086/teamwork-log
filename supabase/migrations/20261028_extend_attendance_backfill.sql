create or replace function public.stamp_attendance()
returns trigger language plpgsql set search_path=public
as $$
declare
  days smallint[];
  daily_starts jsonb;
  daily_ends jsonb;
  fallback_start time;
  fallback_end time;
  starts_at time;
  ends_at time;
  monday date;
  weekday_key text;
begin
  if tg_op='INSERT' then
    new.uploaded_at=now();
    new.work_date=coalesce(new.work_date,(now() at time zone 'Asia/Seoul')::date);
    new.is_backfilled=coalesce(new.is_backfilled,false);
    if new.is_backfilled then
      if (now() at time zone 'Asia/Seoul')::date > date '2026-10-28'
         or new.work_date < date '2026-10-26'
         or new.work_date > (now() at time zone 'Asia/Seoul')::date then
        raise exception '이번 사후 등록은 2026-10-26~2026-10-28 기록만 오늘까지 가능합니다';
      end if;
      if new.photo_path is null or new.checkout_photo_path is null
         or new.check_in_at is null or new.checked_out_at is null then
        raise exception '사후 등록에는 출퇴근 사진과 시각이 모두 필요합니다';
      end if;
      if (new.check_in_at at time zone 'Asia/Seoul')::date <> new.work_date
         or (new.checked_out_at at time zone 'Asia/Seoul')::date <> new.work_date
         or new.checked_out_at <= new.check_in_at then
        raise exception '출퇴근 시각은 선택한 날짜 안에서 순서대로 입력해 주세요';
      end if;
      new.backfilled_at=now();
      new.backfilled_by=auth.uid();
    else
      new.check_in_at=now();
      new.checked_out_at=null;
      new.backfilled_at=null;
      new.backfilled_by=null;
    end if;

    if new.work_date >= date '2026-10-26' then
      monday=new.work_date-(extract(isodow from new.work_date)::integer-1);
      select workdays,start_times,end_times,start_time,end_time
        into days,daily_starts,daily_ends,fallback_start,fallback_end
        from public.weekly_schedule_overrides
        where team_id=new.team_id and user_id=new.user_id and week_start=monday;
      if not found then
        select workdays,start_times,end_times,start_time,end_time
          into days,daily_starts,daily_ends,fallback_start,fallback_end
          from public.work_schedules where team_id=new.team_id and user_id=new.user_id;
      end if;
      weekday_key=extract(isodow from new.work_date)::integer::text;
      starts_at=coalesce(nullif(daily_starts->>weekday_key,'')::time,fallback_start);
      ends_at=coalesce(nullif(daily_ends->>weekday_key,'')::time,fallback_end);
      if days is not null and extract(isodow from new.work_date)::smallint=any(days) then
        new.scheduled_start_at=((new.work_date+starts_at) at time zone 'Asia/Seoul');
        new.scheduled_end_at=((new.work_date+ends_at) at time zone 'Asia/Seoul');
        if not new.is_backfilled or new.work_date=(now() at time zone 'Asia/Seoul')::date then
          new.late_minutes=greatest(0,floor(extract(epoch from (new.uploaded_at-new.scheduled_start_at))/60)::integer);
          if extract(isodow from new.work_date)=3 then
            new.late_fee_krw=new.late_minutes*1000;
          elsif new.late_minutes>=30 then
            new.late_fee_krw=5000;
          elsif new.late_minutes>=20 then
            new.late_fee_krw=3000;
          elsif new.late_minutes>=10 then
            new.late_fee_krw=1000;
          else
            new.late_fee_krw=0;
          end if;
        else
          new.late_minutes=null;
          new.late_fee_krw=0;
        end if;
        if new.is_backfilled then
          new.early_minutes=greatest(0,floor(extract(epoch from (new.scheduled_end_at-new.checked_out_at))/60)::integer);
        else
          new.early_minutes=null;
        end if;
      else
        new.scheduled_start_at=null;
        new.scheduled_end_at=null;
        new.late_minutes=null;
        new.early_minutes=null;
        new.late_fee_krw=0;
      end if;
    end if;
  else
    new.uploaded_at=old.uploaded_at;
    new.work_date=old.work_date;
    new.is_backfilled=old.is_backfilled;
    new.backfilled_at=old.backfilled_at;
    new.backfilled_by=old.backfilled_by;
    if new.changed_at is distinct from old.changed_at or new.photo_path is distinct from old.photo_path then
      new.changed_at=now();
    else
      new.changed_at=old.changed_at;
    end if;
    new.check_in_at=old.check_in_at;
    new.scheduled_start_at=old.scheduled_start_at;
    new.scheduled_end_at=old.scheduled_end_at;
    new.late_minutes=old.late_minutes;
    new.late_fee_krw=old.late_fee_krw;
    if old.checked_out_at is null and new.checked_out_at is not null then
      new.checked_out_at=now();
      if old.scheduled_end_at is not null then
        new.early_minutes=greatest(0,floor(extract(epoch from (old.scheduled_end_at-new.checked_out_at))/60)::integer);
      else
        new.early_minutes=null;
      end if;
    elsif old.checked_out_at is not null then
      new.checked_out_at=old.checked_out_at;
      new.early_minutes=old.early_minutes;
    else
      new.early_minutes=old.early_minutes;
    end if;
  end if;
  return new;
end $$;
