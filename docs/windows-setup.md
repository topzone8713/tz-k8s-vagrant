# Windows 환경 설정

tz-k8s-vagrant를 Windows에서 사용하기 위한 가이드. **Git Bash** 또는 **MSYS2** 환경에서 실행합니다.

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
