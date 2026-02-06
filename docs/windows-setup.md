# Windows 환경 설정

tz-k8s-vagrant를 Windows에서 사용하기 위한 가이드. **Git Bash** 또는 **MSYS2** 환경에서 실행합니다.

---

## Cursor IDE에서 사용하기

Cursor에서 이 프로젝트를 열었을 때, **기본 터미널을 Git Bash**로 두고 **붙여넣기**가 되도록 설정하면 `bootstrap.sh` 등 셸 스크립트를 편하게 실행할 수 있습니다.

### 1. 설정 샘플 (settings.json)

**파일** → **기본 설정** → **설정 (JSON) 열기** 로 사용자 설정을 연 뒤, 아래 **전체 블록**을 복사해 기존 내용과 합치거나 필요한 항목만 추가합니다. (이미 있는 키는 덮어쓰지 말고 값만 맞게 수정하세요.)

```json
{
  "window.commandCenter": true,
  "terminal.integrated.profiles.windows": {
    "Git Bash": {
      "path": "C:\\Program Files\\Git\\bin\\bash.exe",
      "args": ["--login", "-i"]
    }
  },
  "terminal.integrated.defaultProfile.windows": "Git Bash",
  "terminal.integrated.rightClickBehavior": "paste",
  "terminal.integrated.commandsToSkipShell": [
    "workbench.action.terminal.paste",
    "workbench.action.terminal.copySelection"
  ]
}
```

| 설정 | 설명 |
|------|------|
| `terminal.integrated.profiles.windows` | Git Bash 프로필 정의. `path`는 본인 PC의 `bash.exe` 경로로 맞추세요. |
| `terminal.integrated.defaultProfile.windows` | 새 터미널을 Git Bash로 열기. |
| `terminal.integrated.rightClickBehavior` | `"paste"`: 터미널에서 **우클릭 = 붙여넣기**. (메뉴 대신 바로 붙여넣기) |
| `terminal.integrated.commandsToSkipShell` | **Ctrl+V**(붙여넣기), **Ctrl+C**(선택 복사)를 셸이 아닌 Cursor가 처리하도록 함. Git Bash에서 붙여넣기/복사가 확실히 동작하도록 합니다. |

- **설정 파일 위치 (Windows)**  
  `%APPDATA%\Cursor\User\settings.json` (예: `C:\Users\본인사용자명\AppData\Roaming\Cursor\User\settings.json`)
- Git이 **다른 경로**에 있으면 `path`만 수정. 예: `"C:\\Program Files (x86)\\Git\\bin\\bash.exe"`

### 2. 터미널 열기 및 스크립트 실행

| 동작 | 방법 |
|------|------|
| 터미널 열기 | **Ctrl + `** (백틱) 또는 **터미널** → **새 터미널** |
| Git Bash 확인 | 프롬프트가 `user@PC MINGW64 ~` 형태이면 Git Bash임 |
| 붙여넣기 | **우클릭** 또는 **Ctrl+V** (위 설정 적용 후) |
| 프로젝트 폴더로 이동 | `cd /c/Users/본인사용자명/workspace/tz/tz-k8s-vagrant` (경로는 환경에 맞게) |
| bootstrap 실행 | `./bootstrap.sh` 또는 `./bootstrap.sh M` (마스터 설치) |

PowerShell에서는 현재 폴더의 스크립트를 실행할 때 `.\`가 필요하고, `.sh`는 bash 전용이므로 **PowerShell에서 직접 `.\bootstrap.sh`만 입력하면 동작하지 않습니다.** 반드시 **Git Bash 터미널**에서 `./bootstrap.sh`를 실행하거나, PowerShell에서 `bash .\bootstrap.sh`로 실행하세요.

### 3. 터미널 프로필 전환

- 터미널 패널 **오른쪽 ∨ (드롭다운)** → **Git Bash** / **PowerShell** / **Command Prompt** 선택
- 기본만 바꾸려면: 설정에서 **Default Profile: Windows** 를 **PowerShell** 등으로 변경

---

## 사전 요구사항

1. **VirtualBox** - [다운로드](https://www.virtualbox.org/wiki/Downloads)
2. **Vagrant** - [다운로드](https://www.vagrantup.com/downloads)
3. **Git for Windows** (Git Bash 포함) - [다운로드](https://git-scm.com/download/win)
   - 또는 **MSYS2** - [다운로드](https://www.msys2.org/)
4. **kubectl** (선택) - [설치 가이드](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/)

---

## 실행 환경

### 권장: Git Bash

1. 프로젝트 디렉터리로 이동
2. Git Bash 터미널 실행
3. `bash bootstrap.sh` 실행

```bash
cd /c/path/to/tz-k8s-vagrant
bash bootstrap.sh
```

### 호스트 스크립트 (백업)

`scripts/backup-vms.sh`는 호스트에서 실행하는 백업 스크립트이며, **Windows(Git Bash)** 에서도 동작합니다.  
- VirtualBox/Vagrant 경로 자동 감지, 최신 백업은 symlink 대신 `~/vagrant-backups/latest.txt`에 경로 저장.

### 대안: WSL2

WSL2(Windows Subsystem for Linux)를 사용하면 Linux와 동일하게 동작합니다.

1. [WSL2 설치](https://docs.microsoft.com/en-us/windows/wsl/install)
2. Ubuntu 등 Linux 배포판 설치
3. WSL 터미널에서 `bash bootstrap.sh` 실행

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

- **VBoxManage 경로**: `C:\Program Files\Oracle\VirtualBox\VBoxManage.exe` 자동 탐지
- **프로세스 종료**: `vagrant remove` 시 `taskkill` 사용 (ps/pkill 대신)
- **브릿지 네트워크**: VirtualBox의 첫 번째 사용 가능한 인터페이스 자동 선택
- **kubeconfig**: `~/.kube/config` (Git Bash에서 `$USERPROFILE\.kube\config`로 매핑)

---

## 네트워크 (192.168.0.x)

VM들은 192.168.0.100(kube-master), 192.168.0.101~102(kube-node) IP를 사용합니다. Windows 호스트와 동일 네트워크 대역인지 확인하세요.

---

## kubectl 사용

bootstrap.sh 완료 후 kubeconfig가 `~/.kube/config`에 복사됩니다.

```bash
# Git Bash에서
kubectl get nodes

# Windows PowerShell/CMD에서 (별도 kubectl 설치 필요)
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config"
kubectl get nodes
```

---

## 문제 해결

### Vagrant/VBoxManage를 찾을 수 없음

- VirtualBox와 Vagrant를 설치한 후 **Git Bash를 재시작**하세요.
- PATH에 `C:\Program Files\Oracle\VirtualBox`가 포함되는지 확인하세요.

### 브릿지 네트워크 오류

- VirtualBox에서 **호스트 전용 네트워크 어댑터**가 생성되어 있는지 확인하세요.
- `Vagrantfile`의 `scripts/local/`에서 브릿지 인터페이스를 수동으로 지정할 수 있습니다.

### bash 버전 (vm-network.sh)

- vm-network.sh는 bash 4+ (associative arrays)가 필요합니다.
- Git Bash 기본 bash는 4.x 이상이므로 일반적으로 문제없습니다.

### "The system cannot find the path specified" (vagrant ssh 시)

- **원인**: Git Bash에서 `vagrant ssh`를 호출할 때, Vagrant가 Windows 쪽 경로를 제대로 찾지 못해 발생할 수 있습니다.
- **대응**: `bootstrap.sh`와 `common-vagrant.sh`에서 Windows일 때 **cmd.exe**로 작업 디렉터리를 Windows 경로로 바꾼 뒤 `vagrant ssh`를 실행하도록 되어 있습니다. 최신 코드를 pull한 상태라면 해당 경고는 줄어들거나 사라질 수 있습니다.
- 이전 버전 사용 중이라면 위 메시지가 나와도, 그 다음에 VM 안에서 스크립트가 실행되면(**Checking internet connectivity...**, **Cloning into 'kubespray'...** 등) 정상 동작으로 보면 됩니다.

### "No running VMs found" (vm-network.sh)

- vm-network.sh가 `vagrant status`로 VM 목록을 다시 조회합니다. Windows에서는 먼저 machine-readable, 실패 시 human-readable 출력으로 fallback합니다.
- 계속 실패하면 프로젝트 루트에서 `vagrant status`로 VM이 보이는지 확인하고, Git Bash에서 bootstrap을 실행했는지 확인하세요.
