# Full Court Stickman

macOS 13 이상에서 실행하는 2D 농구 슛 연습 앱입니다. Apple Silicon과 Intel을 지원합니다.
사진 얼굴 + 졸라맨 캐릭터, 나무 코트, 키보드 이동과 드리블·슛·점프·덩크·수비 애니메이션을 포함합니다.
현재는 싱글 플레이 연습 모드이며 상대 AI/온라인 대전은 없습니다.

## 설치

GitHub 릴리스와 Homebrew cask가 공개되어 있습니다.

```sh
brew tap sonsy12/bk
brew install --cask full-court-stickman
```

응용 프로그램 폴더의 **Full Court Stickman**을 실행하세요.

## 조작

| 키 | 동작 |
|---|---|
| 방향키 | 이동; 공 가까이 가면 자동 획득 |
| Space | 독립 점프 |
| X | 일반 슛; 점프 중 누르면 점프슛 |
| Z | 골대 가까이에서 공을 들고 덩크 |
| C | 누르는 동안 수비; 점프 중 누르면 블로킹 |
| R | 점수와 공 초기화 |
| Command-Q | 종료 |

공을 소유하면 자동으로 드리블합니다. 득점한 경우에만 공이 가운데로 돌아오며,
실패한 슛은 코트에 남아 다시 잡을 수 있습니다. 슛 성공률은 골대와의 거리에 따라 달라집니다.

## 자동 업데이트

실행 시 GitHub 최신 릴리스를 확인합니다. Homebrew로 설치된 앱이면 새 버전을
Homebrew의 체크섬 검증 경로로 자동 설치합니다. 현재 플레이를 종료시키지는 않으며,
앱을 다시 열면 새 버전이 적용됩니다. 네트워크/업데이트 실패 시 기존 앱은 그대로 사용 가능합니다.
직접 압축 파일을 내려받은 앱은 자동 설치 대상이 아닙니다.

```sh
brew update
brew upgrade --cask sonsy12/bk/full-court-stickman
```

## 개발 및 배포

```sh
bash scripts/build.sh
open "build/Full Court Stickman.app"
```

`dist/Full-Court-Stickman.zip`에 universal 앱이 생성됩니다.
실행 파일은 임시(ad-hoc) 서명이며 Apple 공증은 아직 지원하지 않습니다.
다운로드 앱이 차단되면 시스템 설정 → 개인정보 보호 및 보안의 ‘확인 없이 열기’를 사용하세요.
Gatekeeper를 전체 비활성화할 필요는 없습니다.

다음 릴리스는 Info.plist의 버전을 올리고 빌드한 뒤 GitHub 릴리스에 ZIP을 업로드하고,
Homebrew cask의 버전과 SHA256을 같은 릴리스에 맞춰 갱신해야 합니다.
캐릭터에 사용된 사진의 권리는 원 권리자에게 있으며, 별도의 재배포 허락을 부여하지 않습니다.
