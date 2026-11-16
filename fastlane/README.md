fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios verify_auth

```sh
[bundle exec] fastlane ios verify_auth
```

ASC API Key 인증만 검증 (실제 빌드 안 함, ASC 호출 1번)

### ios create_app

```sh
[bundle exec] fastlane ios create_app
```

ASC에 앱 레코드 생성 (처음 한 번). APP_NAME 환경변수로 이름 지정

### ios rename_app

```sh
[bundle exec] fastlane ios rename_app
```

ASC 앱 이름(언어별 앱 정보의 name) 바꾸기. APP_NAME 없이 돌리면 현재 상태만 출력

### ios beta_status

```sh
[bundle exec] fastlane ios beta_status
```

외부 테스트 준비 상태 출력(읽기만): 베타 그룹, 테스트 정보, 심사 연락처, 최근 빌드 심사 상태

### ios submit_external

```sh
[bundle exec] fastlane ios submit_external
```

외부 테스트 제출: 테스트 정보·심사 연락처·빌드 안내를 채우고, 외부 그룹에 넣고, 베타 심사에 낸다

REVIEW_INFO_DIR = first_name/last_name/email_address/phone_number.txt 가 있는 폴더(저장소 밖). BUILD_NUMBER 없으면 최신

### ios list_apps

```sh
[bundle exec] fastlane ios list_apps
```

ASC 계정의 앱 목록(이름 · 번들 ID) 출력

### ios beta

```sh
[bundle exec] fastlane ios beta
```

TestFlight 업로드. build_number를 ASC 최신+1로 자동 bump

### ios snapshot_all

```sh
[bundle exec] fastlane ios snapshot_all
```

스크린샷 자동 캡처 (fastlane snapshot OS truncate 버그 우회 — UDID 직접)

CcutuSnapshots UI 테스트 타깃이 있어야 한다 (App Store 제출 준비 때 추가).

### ios release_metadata

```sh
[bundle exec] fastlane ios release_metadata
```

ASC 메타데이터 + 빌드 promote (submit X — 사용자 ASC web에서 manual submit)

### ios upload_screenshots_direct

```sh
[bundle exec] fastlane ios upload_screenshots_direct
```

스크린샷 ASC 직접 업로드 (Spaceship::ConnectAPI — fastlane deliver silent skip 우회)

### ios release

```sh
[bundle exec] fastlane ios release
```

심사 자동 제출 + 자동 release (v1.1+ 권장). 첫 release는 release_metadata + ASC web manual.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
