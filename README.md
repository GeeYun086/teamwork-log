# 팀워크 로그

출근 인증, 4주 업무계획, 오늘 업무 기록, 수정 요청, 퇴근 보고를 한곳에서 공유하는 반응형 웹앱 MVP입니다. React + TypeScript + Vite로 화면을 만들고, 팀원 간 실제 데이터 공유에는 Supabase Auth, Postgres, 비공개 Storage를 사용합니다.

## 빠르게 둘러보기

```bash
npm install
npm run dev
```

`.env`에 Supabase 키가 없으면 샘플 팀 데이터로 미리보기 모드가 열립니다. 이 모드의 변경 내용은 현재 브라우저의 `localStorage`에만 저장되므로 다른 팀원과 공유되지 않습니다.

## 실제 팀에서 함께 사용하기

1. [Supabase](https://supabase.com/)에서 프로젝트를 생성합니다.
2. 프로젝트의 **SQL Editor**에서 `supabase/schema.sql` 전체를 실행합니다. 기본 테이블, 팀 합류 함수, 접근 정책, 비공개 사진 버킷이 준비됩니다.
3. 같은 SQL Editor에서 기존 마이그레이션을 순서대로 실행한 뒤 `supabase/migrations/20261027_notifications_comments_roles.sql`과 `supabase/migrations/20261027_allow_own_report_delete.sql`도 실행합니다. 알림 기록, 수정 요청 댓글, 관리자 권한 변경 함수와 본인 보고서 삭제 정책이 추가됩니다.
4. 프로젝트의 **Project Settings → API**에서 Project URL과 publishable/anon key를 복사합니다.
5. `.env.example`을 `.env`로 복사해 다음 값을 채웁니다.

   ```dotenv
   VITE_SUPABASE_URL=https://your-project.supabase.co
   VITE_SUPABASE_ANON_KEY=your-publishable-key
   ```

6. `npm run dev`를 다시 실행하고 계정을 만든 뒤 새 팀을 생성합니다. 팀원은 각자 계정을 만든 다음 사이드바의 초대 코드를 받아 같은 팀 공간에 합류합니다.
7. GitHub에 프로젝트를 push하고 Vercel에서 **Add New → Project**로 저장소를 import합니다. Framework Preset은 Vite, Build Command는 `npm run build`, Output Directory는 `dist`로 둡니다 (`vercel.json`에 반영되어 있습니다).
8. Vercel 프로젝트의 **Settings → Environment Variables**에 `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`를 Production/Preview 환경에 추가하고 Deploy합니다. Supabase Auth URL Configuration의 Site URL과 Redirect URLs에 배포 도메인도 추가합니다.
9. 브라우저 푸시용 VAPID 키 쌍을 생성합니다. 공개 키는 Vercel의 `VITE_VAPID_PUBLIC_KEY`에, 공개 키·비밀 키·`VAPID_SUBJECT`(예: `mailto:관리자 이메일`)는 Supabase Edge Function Secrets에 등록합니다. 비밀 키는 절대 `VITE_` 환경 변수나 브라우저 코드에 넣지 않습니다.
10. Supabase CLI로 연결한 뒤 `supabase functions deploy attendance-push`와 `supabase functions deploy team-push`를 실행합니다. 새 함수 코드는 `supabase/functions/team-push/index.ts`에 있으며 출퇴근, 퇴근 보고, 수정 요청, 댓글 푸시를 보냅니다. Vercel을 다시 배포해 공개 VAPID 키를 프런트엔드에 반영합니다.
11. 로그인한 팀원은 각 기기에서 앱 우측 상단의 종 모양 버튼을 한 번 눌러 권한을 허용합니다. 퇴근 보고와 받은 수정 요청/댓글은 알림 기록에도 남고, 푸시를 누르면 앱이 열립니다. iPhone은 홈 화면에 추가한 웹앱에서 푸시를 허용해야 하며, Android는 지원 브라우저에서 권한을 허용하면 됩니다.

이제 팀원은 같은 Vercel HTTPS 주소로 접속해 사진·출퇴근 시각·근무 일정·업무·보고서를 공유합니다. 로그인 세션은 기기의 브라우저 저장소에 유지되고 자동 갱신됩니다. 일정은 사람마다 주 3일과 기준 출퇴근 시각을 지정하고 특정 주의 변경도 팀 전체에 표시됩니다. 공지사항은 관리자가 공통 업무와 기한을 등록하고, 팀원별 확인·완료 상태를 공유합니다. 변경은 최대 30초 안에 반영됩니다. 본인은 날짜를 선택해 과거 퇴근 보고서를 수정할 수 있습니다.

비밀 `service_role` 키는 브라우저 환경 변수로 넣지 마세요. 앱은 사용자 세션과 데이터베이스 RLS 정책으로 접근을 제한합니다. 출근 사진은 근무일별 1회만 등록할 수 있고, 등록 뒤에는 재업로드와 덮어쓰기가 차단됩니다. 비공개 버킷에 저장하며 본인과 관리자만 만료되는 서명 URL로 사진을 볼 수 있습니다. 브라우저에서 긴 변 1440px JPEG로 최적화한 뒤 최대 5MB로 업로드합니다. 데이터 보관 기간 설정 UI는 아직 없으므로 운영 시 Supabase에서 보관 정책을 정해야 합니다.

## 기능

- 출근·퇴근 사진과 서버 기준 사진 등록 시각, 지각 분·지각비 기록. 사진은 기기에서 긴 변 1440px JPEG로 축소한 뒤 저장
- 2026-10-26·27 사후 출퇴근 기록(사후 표시 및 등록 시각 별도 보관). 사후 등록은 10월 27일까지만 허용하고 이후에는 실시간 인증만 가능
- 팀 전체/개인별 주차 계획과 예정·진행 중·완료·대기 상태
- 오늘 메모, 완료 내용, 대기 사유, 다음 할 일
- 담당자·업무·우선순위·희망일이 있는 수정 요청, 댓글, 확인 버튼과 상태 추적
- 읽음 표시가 있는 알림 기록, 퇴근 보고·받은 수정 요청·댓글·출퇴근 등록 알림
- 관리자의 팀원별 관리자/팀원 권한 부여와 팀원 내보내기
- 업무 기록으로 초안을 만든 AS-IS/TO-BE 보고서, 수정·저장·복사
- 팀 공지사항에 공통 업무·기한을 게시하고 팀원별 확인·완료 현황 공유
- 팀 대시보드의 출근, 계획 진행, 확인 대기 요청, 대기 업무, 보고서 작성 현황
- 작은 화면에서 사용할 수 있는 모바일 탐색과 사진 촬영 입력
- 팀원별 주 3일 반복 근무일·개인 출근 시각, 특정 주 변경 설정 및 2026-10-27부터의 지각 통계
- 본인의 과거 날짜 퇴근 보고서 수정·저장

퇴근 초안은 업무 메모와 상태를 정해진 양식에 배치합니다. AI 호출은 포함하지 않았습니다. AI 요약을 붙일 경우 별도 서버 함수에서 사용자가 명시적으로 실행할 때만 호출하고, 결과를 검토·저장하도록 확장할 수 있습니다.

## 비용과 운영 유의사항

- 이 코드 자체는 오픈소스 의존성만 사용하며 라이선스 구독료가 없습니다.
- 개인/비상업 프로젝트라면 Vercel Hobby는 $0이고, Supabase Free도 $0으로 시작할 수 있습니다. 다만 Supabase Free는 데이터베이스 500MB, 파일 저장 1GB, egress 5GB 한도이며 프로젝트가 1주 비활성 상태면 pause될 수 있습니다. 사진은 Storage에 저장되고 업무·일정·시각은 DB에 저장됩니다. [Supabase 요금](https://supabase.com/pricing)
- 팀의 상업적/업무용 서비스라면 Vercel Hobby는 개인용·비상업 용도 제한이 있으므로, 현재 안내 기준 Pro는 $20/월입니다. Supabase Pro는 $25/월부터이며 저장공간과 백업 등이 늘어납니다. 세금, 사용량 초과, 요금 변경 가능성이 있으니 배포 전에 [Vercel 요금](https://vercel.com/pricing)과 Supabase 요금을 다시 확인하세요.
- Supabase Free는 현재 파일 저장 1GB, 데이터베이스 500MB, egress 5GB 한도를 제공합니다. 사진은 Storage에, 시각·일정·보고서는 DB에 저장됩니다. 출근·퇴근 사진을 각각 저장하므로 사진 한 장당 최대 5MB 기준 주 3회 근무하는 5명 팀은 월 최대 약 650MB(월 13회 근무 가정)까지 늘 수 있습니다. 실제 사진은 업로드 전에 축소·압축해 보통 이보다 작지만, 여러 달 누적과 사진 열람량에 따라 1GB Storage/5GB 전송 한도에 가까워질 수 있습니다. Supabase 대시보드의 Storage 사용량을 확인하고 사진 보관 기간을 정하세요.
- AI 요약은 현재 연결되어 있지 않아 AI API 비용이 발생하지 않습니다. 추후 선택 실행으로 추가하면 모델 호출량에 따라 별도 비용이 생깁니다.
- 로그인 이메일 인증을 켜면 이메일 발송량이나 별도 SMTP 설정에 따라 비용/설정이 추가될 수 있습니다.

## 기술 구성

- UI: React 19, TypeScript, Vite, Lucide icons
- 계정/공유 데이터: Supabase Auth + Postgres + Row Level Security
- 출근 사진: Supabase private Storage bucket + signed URL
- 배포: Vite 정적 산출물 (`dist/`)을 정적 웹 호스팅에 게시

카카오톡 자동 전송, 얼굴 인식, AI 판정은 포함되지 않습니다. 출퇴근 사진·시각 등록 시 팀원에게 보내는 브라우저 푸시는 Supabase Edge Function과 VAPID 키 설정 후 활성화됩니다. 팀원은 기기별로 알림을 한 번 허용해야 하며, 푸시 발송량과 Edge Function 실행량은 Supabase 플랜 한도에 포함됩니다.
