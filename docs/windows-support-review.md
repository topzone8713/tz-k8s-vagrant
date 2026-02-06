# Windows 스크립트 지원 검토

윈도우즈 지원 관련 커밋을 기준으로 구현 상태와 보완점을 정리했습니다.

---

## 1. 커밋 요약 (windows 브랜치)

| 커밋 | 내용 |
|------|------|
| `6b537766` | feat: add Windows support (Git Bash/MSYS2) – 기본 지원 |
| `aebbfcd4` | Cursor 터미널 설정, vm-network 경로/fallback, base.sh exit 0 |
| `1b236668` | backup-vms.sh Windows 지원, 문서 보강 |
| `820b7a8f` | nul 파일 방지(Mac), E_ACCESSDENIED 시 VBoxManage 복구 |

---

## 2. 구현 현황

### 2.1 bootstrap.sh

| 항목 | 구현 | 비고 |
|------|------|------|
| PLATFORM 감지 (mac/linux/windows) | ✅ | `OSTYPE` → msys, cygwin, msys2 → windows |
| vagrant remove 시 프로세스 종료 | ✅ | Windows: taskkill, 그 외: pkill |
| VBoxManage 경로 | ✅ | PATH + Mac 경로 + **Windows** (`/c/Program Files/...`, `/mingw64/bin`) |
| Vagrantfile 복사 시점 | ✅ | vagrant status **이전**에 복사 (nul 방지) |
| sed -i (kubeconfig) | ✅ | PLATFORM=mac → `sed -i ''`, 그 외 → `sed -i` |
| Bash 4+ (vm-network.sh) | ✅ | bash, homebrew, /usr/local, /usr/bin, **/mingw64/bin/bash.exe** |
| E_ACCESSDENIED 복구 | ✅ | VBoxManage unregistervm --delete 후 .vagrant 삭제 |

**E_ACCESSDENIED 블록**: VBoxManage 경로가 **Mac + Linux**만 있고 **Windows 경로 없음**.  
Windows에서 같은 lock 오류가 나면 해당 복구 경로가 동작하지 않을 수 있음.

### 2.2 Vagrantfile (scripts/local + Vagrantfile_slave, slave2)

| 항목 | 구현 | 비고 |
|------|------|------|
| VBoxManage in PATH | ✅ | `which`(Unix) / `where`(Windows, **Gem.win_platform?** 일 때만) |
| nul 사용 | ✅ | Windows일 때만 `2>nul`, `where ... > nul` (Mac에서 nul 파일 생성 방지) |
| VBoxManage 절대 경로 | ✅ | Mac, Linux, **Windows** (C:/Program Files, Program Files (x86), ENV ProgramFiles) |
| 브릿지 인터페이스 | ✅ | en0 없으면 **첫 번째 인터페이스** 사용 (Windows 대응) |

### 2.3 scripts/local/common-vagrant.sh

| 항목 | 구현 | 비고 |
|------|------|------|
| detect_host | ✅ | darwin, linux-gnu, **msys/cygwin/msys2 → my-windows** |
| find_vagrant_cmd | ✅ | Windows일 때 PATH에 VirtualBox 디렉터리 추가 |

### 2.4 scripts/local/vm-network.sh

| 항목 | 구현 | 비고 |
|------|------|------|
| VM_CONFIGS | ✅ | **my-windows:kube-master, kube-node-1, kube-node-2** (my-ubuntu와 동일 IP) |

Slave(my-windows:kube-slave-*) 설정은 없음. A_ENV=S/S2 + Windows 조합이면 apply-static-ip에서 해당 VM은 스킵됨.

### 2.5 scripts/backup-vms.sh

| 항목 | 구현 | 비고 |
|------|------|------|
| PLATFORM 감지 | ✅ | mac, linux, windows (msys/cygwin/msys2) |
| VirtualBox PATH | ✅ | Windows: `/c/Program Files/Oracle/VirtualBox` 등 |
| 기타 Windows 대응 | ✅ | doc에 따르면 machine-readable fallback, symlink 대신 latest.txt 등 |

### 2.6 문서

| 파일 | 내용 |
|------|------|
| docs/windows-setup.md | 사전 요구사항, Git Bash/WSL2, Cursor 터미널 설정, 플랫폼 감지 표, 문제 해결 |
| README.md | Windows 사용자 안내 및 docs/windows-setup.md 링크 |

---

## 3. 누락·불일치

1. **.gitignore**  
   - `nul` / `/nul` 항목이 없음.  
   - Mac/Linux에서 실수로 `nul` 파일이 생기면 커밋될 수 있음.  
   - **권장**: `.gitignore`에 `nul`, `/nul` 추가.

2. **bootstrap.sh – E_ACCESSDENIED 블록의 VBoxManage**  
   - 현재: `command -v`, Mac 경로, Linux 경로만 사용.  
   - Windows(Git Bash)에서는 `/c/Program Files/Oracle/VirtualBox/VBoxManage.exe` 등이 필요.  
   - **권장**: 이 블록에도 Windows용 VBoxManage 경로 추가 (다른 곳과 동일한 경로 목록 사용).

3. **vm-network.sh – my-windows Slave**  
   - A_ENV=S / S2 인 Windows 호스트에서 slave VM(kube-slave-1~6)에 대한 apply-static-ip가 필요하면,  
     `VM_CONFIGS["my-windows:kube-slave-1"]` 등이 없어서 스킵됨.  
   - **선택**: Slave를 Windows에서도 쓸 계획이면 my-windows:kube-slave-* 설정 추가.

4. **common-vagrant.sh – find_vagrant_cmd (Windows)**  
   - `find /usr/local -name vagrant`는 Windows에 없음.  
   - `which vagrant` 실패 시 `echo "vagrant"`로 넘어가고, `command -v vagrant`로 한 번 더 확인하므로 실제로는 큰 문제 없음.  
   - 필요하면 Windows에서는 `"/c/Program Files/Vagrant/bin/vagrant"` 같은 fallback을 추가할 수 있음.

---

## 4. 권장 보완 (우선순위)

1. **.gitignore**  
   - `nul`, `/nul` 추가 (nul 파일 커밋 방지).

2. **bootstrap.sh – E_ACCESSDENIED 시 VBoxManage**  
   - Windows 경로 추가하여, Windows에서도 lock 복구 시 VBoxManage로 unregistervm 가능하게 함.

3. **(선택) vm-network.sh**  
   - Windows에서 Slave 사용 시: `my-windows:kube-slave-1` 등 VM_CONFIGS 추가.

4. **(선택) docs/windows-setup.md**  
   - “제한 사항”에  
     - “Slave( A_ENV=S/S2 ) + Windows 조합은 apply-static-ip에서 slave VM이 자동 설정 대상에 포함되지 않을 수 있음”  
     정도를 한 줄 추가하면 좋음.

---

## 5. 정리

- **호스트 스크립트**: bootstrap, Vagrantfile 3종, common-vagrant, vm-network, backup-vms 모두 Windows(Git Bash/MSYS2)를 의식한 분기가 들어가 있음.
- **VM 내부 스크립트**: Ubuntu 기준이라 Windows 전용 수정은 없음 (설계대로임).
- **실제로 손보면 좋은 것**:  
  - `.gitignore`에 nul 추가  
  - E_ACCESSDENIED 블록에 Windows용 VBoxManage 경로 추가  
  - (필요 시) my-windows Slave 설정 및 문서 한 줄 보완  

이대로도 Git Bash/MSYS2에서의 기본 사용은 가능하고, 위 보완만 적용하면 Windows 지원이 더 일관되고 예외 상황에서도 복구가 쉬워집니다.
