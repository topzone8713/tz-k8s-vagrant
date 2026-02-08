# Windows 환경 설정

tz-k8s-vagrant를 Windows에서 사용하기 위한 가이드입니다.

---

## 사전 요구사항

1. **VirtualBox** - [다운로드](https://www.virtualbox.org/wiki/Downloads)
2. **Vagrant** - [다운로드](https://www.vagrantup.com/downloads)
3. **Git for Windows** (Git Bash 포함) - [다운로드](https://git-scm.com/download/win)

---

## 실행 방법

**Git Bash** 터미널에서:

```bash
cd /c/path/to/tz-k8s-vagrant
bash bootstrap.sh
```

또는 **MSYS2**에서 동일하게 `bash bootstrap.sh`를 실행합니다.

---

## 플랫폼 감지

bootstrap.sh는 `OSTYPE`으로 플랫폼을 자동 감지합니다.

| 환경   | OSTYPE | PLATFORM |
|--------|--------|----------|
| Git Bash | msys   | windows  |
| MSYS2  | msys2  | windows  |
| Cygwin | cygwin | windows  |
| WSL2   | linux-gnu | linux  |

---

## Windows 특화 동작

- **VBoxManage**: `C:\Program Files\Oracle\VirtualBox\VBoxManage.exe` 자동 탐지
- **프로세스 종료**: `vagrant remove` 시 `taskkill` 사용
- **브릿지 네트워크**: VirtualBox의 첫 번째 사용 가능한 인터페이스 자동 선택

---

## 대안: WSL2

WSL2를 사용하면 Linux와 동일하게 동작합니다.

1. [WSL2 설치](https://docs.microsoft.com/en-us/windows/wsl/install)
2. Ubuntu 등 Linux 배포판 설치
3. WSL 터미널에서 `bash bootstrap.sh` 실행
