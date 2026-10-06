# 하랑 업무 허브 (harangwork.co.kr)

직원 전용 사내 업무 허브. 회사가 발급한 아이디·비밀번호로 로그인.

## 구성
- `index.html` — 화면 전체 (빌드 없음). Cloudflare가 main 브랜치를 자동 배포.
- `supabase-setup.sql` — 데이터베이스 표·권한 설정 (Supabase SQL Editor에서 실행, 여러 번 실행해도 안전)
- 데이터: Supabase 프로젝트 `harangwork-hub` (https://jxwvkloodovpyzmdbkja.supabase.co)
  - 화면에는 공개용 publishable 키만 들어 있음. secret/service_role 키는 절대 코드에 넣지 않음.

## 로그인 방식
- 아이디 `kimtk` → 내부적으로 `kimtk@harangwork.co.kr` 계정으로 로그인
- 계정 발급: Supabase → Authentication → Users → Add user (Email `아이디@harangwork.co.kr`, Auto Confirm 체크)
- 공개 회원가입은 꺼져 있어야 함 (Authentication → Sign In / Providers → Allow new users to sign up: OFF)
- 대표 계정: `wldnddk12` (profiles.role = 'admin')
- 직원 비밀번호 재설정 (SQL Editor):
  `update auth.users set encrypted_password = crypt('새비밀번호', gen_salt('bf')) where email = '아이디@harangwork.co.kr';`

## 권한 (RLS)
- 직원: 자기 업무 보고만 조회, 광고 보고·현장·지시·공지는 전체 조회
- 대표(admin): 전체 조회, 직원 계정 관리, 지점 설정, 주간 요약
- 로그인 안 한 사람: 아무것도 볼 수 없음

## 화면 (탭)
홈 · 광고 보고(엑셀 업로드·대시보드) · 업무 보고 · 현장·거래처 · 업무 지시 · 공지·자료

## 광고 보고 엑셀
- 시트 이름 `광고YY-MM-DD`, '광고금액' 칸이 있는 표를 읽음. 기존 양식은 오른쪽 표(R~AD열)만 사용
- 같은 지점·날짜는 내용이 바뀐 경우에만 덮어씀
- 화면은 최근 약 14개월 자료만 불러옴

## 주간 요약
- 대표 전용. '요약 요청문 복사' → claude.ai에 붙여 넣기 → 결과를 붙여 넣고 저장
