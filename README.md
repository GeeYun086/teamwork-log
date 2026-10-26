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
2. 프로젝트의 **SQL Editor**에서 이 저장소의 `supabase/schema.sql` 전체를 한 번 실행합니다. 테이블, 팀 합류 함수, 행 단위 접근 정책, 비공개 사진 버킷이 준비됩니다.
3. 프로젝트의 **Project Settings → API**에서 Project URL과 publishable/anon key를 복사합니다.
4. `.env.example`을 `.env`로 복사해 다음 값을 채웁니다.

   ```dotenv
   VITE_SUPABASE_URL=https://your-project.supabase.co
   VITE_SUPABASE_ANON_KEY=your-publishable-key
   ```

5. `npm run dev`를 다시 실행하고 계정을 만든 뒤 새 팀을 생성합니다. 팀원은 각자 계정을 만든 다음 사이드바의 초대 코드를 받아 같은 팀 공간에 합류합니다.
6. GitHub에 프로젝트를 push하고 Vercel에서 **Add New → Project**로 저장소를 import합니다. Framework Preset은 Vite, Build Command는 `npm run build`, Output Directory는 `dist`로 둡니다 (`vercel.json`에 반영되어 있습니다).
7. Vercel 프로젝트의 **Settings → Environment Variables**에 `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`를 Production/Preview 환경에 추가하고 Deploy합니다. Supabase Auth URL Configuration의 Site URL과 Redirect URLs에 배포 도메인도 추가합니다.

이제 팀원은 같은 Vercel HTTPS 주소로 언제든 접속하고, 사진·출근 시각·업무·보고서를 같은 Supabase 팀 공간에 저장합니다. 사진은 Vercel의 임시 파일시스템이 아니라 Supabase Storage에 저장되므로 새 배포 후에도 남습니다. 팀원이 올린 변경은 다른 사용자의 화면에 최대 30초 안에 반영됩니다.

비밀 `service_role` 키는 브라우저 환경 변수로 넣지 마세요. 앱은 사용자 세션과 데이터베이스 RLS 정책으로 접근을 제한합니다. 출근 사진은 비공개 버킷에 저장하고, 팀원만 만료되는 서명 URL을 받아 열 수 있습니다. 사진은 JPEG/PNG/WebP, 최대 5MB입니다. 데이터 보관 기간 설정 UI는 아직 없으므로 운영 시 Supabase에서 보관 정책을 정해야 합니다.

## 기능

- 출근 사진과 데이터베이스 서버 시각 저장, 사진 재열람 및 변경 시각 기록
- 팀 전체/개인별 주차 계획과 예정·진행 중·완료·막힘 상태
- 오늘 메모, 완료 내용, 막힌 점, 다음 할 일
- 담당자·업무·우선순위·희망일이 있는 수정 요청과 상태 추적
- 업무 기록으로 초안을 만든 AS-IS/TO-BE 보고서, 수정·저장·복사
- 팀 대시보드의 출근, 계획 진행, 확인 대기 요청, 막힘 업무, 보고서 작성 현황
- 작은 화면에서 사용할 수 있는 모바일 탐색과 사진 촬영 입력

퇴근 초안은 업무 메모와 상태를 정해진 양식에 배치합니다. AI 호출은 포함하지 않았습니다. AI 요약을 붙일 경우 별도 서버 함수에서 사용자가 명시적으로 실행할 때만 호출하고, 결과를 검토·저장하도록 확장할 수 있습니다.

## 비용과 운영 유의사항

- 이 코드 자체는 오픈소스 의존성만 사용하며 라이선스 구독료가 없습니다.
- 개인/비상업 프로젝트라면 Vercel Hobby는 $0이고, Supabase Free도 $0으로 시작할 수 있습니다. 다만 Supabase Free 프로젝트는 1주 비활성 후 pause될 수 있으며 데이터베이스 500MB, 파일 1GB, egress 5GB 한도가 있습니다. 출근 사진을 자주 올리면 파일 저장/전송량이 먼저 한도에 닿을 수 있습니다. [Supabase 요금](https://supabase.com/pricing)
- 팀의 상업적/업무용 서비스라면 Vercel Hobby는 개인용·비상업 용도 제한이 있으므로, 현재 안내 기준 Pro는 $20/월입니다. Supabase Pro는 $25/월부터이며 저장공간과 백업 등이 늘어납니다. 세금, 사용량 초과, 요금 변경 가능성이 있으니 배포 전에 [Vercel 요금](https://vercel.com/pricing)과 Supabase 요금을 다시 확인하세요.
- 사진 저장과 열람은 특히 Storage 용량 및 다운로드 대역폭을 사용합니다. 오래된 인증 사진 삭제 주기를 팀 정책으로 정하세요.
- AI 요약은 현재 연결되어 있지 않아 AI API 비용이 발생하지 않습니다. 추후 선택 실행으로 추가하면 모델 호출량에 따라 별도 비용이 생깁니다.
- 로그인 이메일 인증을 켜면 이메일 발송량이나 별도 SMTP 설정에 따라 비용/설정이 추가될 수 있습니다.

## 기술 구성

- UI: React 19, TypeScript, Vite, Lucide icons
- 계정/공유 데이터: Supabase Auth + Postgres + Row Level Security
- 출근 사진: Supabase private Storage bucket + signed URL
- 배포: Vite 정적 산출물 (`dist/`)을 정적 웹 호스팅에 게시

이 MVP에는 카카오톡 자동 전송, 근태 계산, 얼굴 인식, AI 판정, 실시간 푸시 알림이 포함되지 않습니다. 변경 요청과 업무는 공유 데이터베이스에 저장되며, 다른 사용자의 변경은 화면에서 최대 30초 간격으로 반영됩니다.
