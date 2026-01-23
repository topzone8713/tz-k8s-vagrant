# 서버 재시작 시 Vagrant VM 자동 시작 설정 가이드

## 개요

이 문서는 서버가 재시작될 때 Vagrant VM을 자동으로 시작하고 SSH 터널을 설정하는 방법을 설명합니다.

**지원 플랫폼:**
- **my-ubuntu**: Linux (systemd 사용)
- **my-mac**: macOS (launchd 사용)

## 목차

1. [개요](#개요)
2. [플랫폼별 설정](#플랫폼별-설정)
   - [my-ubuntu (Linux/systemd)](#my-ubuntu-linuxsystemd)
   - [my-mac (macOS/launchd)](#my-mac-macoslaunchd)
3. [서비스 동작 원리](#서비스-동작-원리)
4. [설정 확인 및 테스트](#설정-확인-및-테스트)
5. [문제 해결](#문제-해결)

---

## 플랫폼별 설정

### my-ubuntu (Linux/systemd)

#### 1단계: systemd 서비스 파일 복사

**my-ubuntu 서버에서 실행:**

```bash
# 서비스 파일을 systemd user 디렉토리로 복사
mkdir -p ~/.config/systemd/user
cp ~/workspaces/tz-drillquiz/provisioning/vagrant-reload.service ~/.config/systemd/user/
```

**서비스 파일 위치:**
- 원본: `~/workspaces/tz-drillquiz/provisioning/vagrant-reload.service`
- 복사 위치: `~/.config/systemd/user/vagrant-reload.service`

#### 2단계: systemd daemon reload

```bash
# systemd user 서비스 데몬 리로드
systemctl --user daemon-reload
```

#### 3단계: 서비스 활성화

```bash
# 서비스 활성화 (재시작 시 자동 실행)
systemctl --user enable vagrant-reload.service
```

**활성화 확인:**
```bash
systemctl --user is-enabled vagrant-reload.service
# 출력: enabled
```

#### 4단계: linger 활성화

**중요**: 사용자가 로그인하지 않아도 서비스가 실행되도록 linger를 활성화해야 합니다.

```bash
# linger 활성화 (로그인 없이도 사용자 서비스 실행)
loginctl enable-linger $USER
```

**확인:**
```bash
loginctl show-user $USER | grep Linger
# 출력: Linger=yes
```

#### 5단계: 서비스 테스트

**서비스 수동 시작 (테스트):**
```bash
systemctl --user start vagrant-reload.service
```

**서비스 상태 확인:**
```bash
systemctl --user status vagrant-reload.service
```

**서비스 로그 확인:**
```bash
# 실시간 로그 확인
journalctl --user -u vagrant-reload.service -f

# 최근 로그 확인
journalctl --user -u vagrant-reload.service -n 50
```

---

### my-mac (macOS/launchd)

#### 1단계: plist 파일 준비

**my-mac에서 실행:**

먼저 plist 파일의 사용자 경로를 수정해야 합니다:

```bash
# plist 파일 복사
cp ~/workspaces/tz-drillquiz/provisioning/com.vagrant.autostart.plist ~/Library/LaunchAgents/

# 사용자 경로로 수정 (필요시)
vi ~/Library/LaunchAgents/com.vagrant.autostart.plist
```

**수정할 내용:**
- `ProgramArguments` 배열의 스크립트 경로를 실제 경로로 변경
- `EnvironmentVariables`의 `WORKSPACE_BASE` 경로를 실제 경로로 변경
- `StandardOutPath`와 `StandardErrorPath`의 로그 파일 경로를 실제 경로로 변경

**예시 (사용자: dooheehong):**
```xml
<key>ProgramArguments</key>
<array>
    <string>/bin/bash</string>
    <string>/Users/dooheehong/workspaces/tz-drillquiz/provisioning/auto-reload-and-tunnel.sh</string>
</array>

<key>EnvironmentVariables</key>
<dict>
    <key>WORKSPACE_BASE</key>
    <string>/Users/dooheehong/workspaces</string>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
</dict>

<key>StandardOutPath</key>
<string>/Users/dooheehong/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.log</string>

<key>StandardErrorPath</key>
<string>/Users/dooheehong/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.error.log</string>
```

#### 2단계: 로그 디렉토리 생성

```bash
# 로그 디렉토리 생성
mkdir -p ~/workspaces/tz-drillquiz/provisioning/logs
```

#### 3단계: launchd에 서비스 로드

```bash
# 서비스 로드 (재시작 시 자동 실행)
launchctl load ~/Library/LaunchAgents/com.vagrant.autostart.plist
```

**로드 확인:**
```bash
launchctl list | grep com.vagrant.autostart
```

#### 4단계: 서비스 시작 (테스트)

```bash
# 서비스 시작 (즉시 실행)
launchctl start com.vagrant.autostart
```

**상태 확인:**
```bash
# 서비스 상태 확인
launchctl list | grep com.vagrant.autostart

# 로그 확인
tail -f ~/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.log
tail -f ~/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.error.log
```

#### 5단계: 자동 시작 확인

**macOS 재시작 후 자동 실행 확인:**
```bash
# 재시작 후 서비스가 자동으로 실행되었는지 확인
launchctl list | grep com.vagrant.autostart

# 로그 확인
tail -n 100 ~/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.log
```

**참고**: macOS는 사용자가 로그인한 후에 LaunchAgents가 실행됩니다. 로그인 없이 실행하려면 LaunchDaemons를 사용해야 하지만, 이는 root 권한이 필요합니다.

---

## 서비스 동작 원리

### vagrant-reload.service

**서비스 파일 내용:**
```ini
[Unit]
Description=Vagrant Reload and SSH Tunnel Service
After=network.target default.target

[Service]
Type=oneshot
Environment="WORKSPACE_BASE=%h/workspaces"
ExecStart=%h/workspaces/tz-drillquiz/provisioning/auto-reload-and-tunnel.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=900
KillMode=none
RemainAfterExit=yes

[Install]
WantedBy=default.target
```

**주요 설정:**
- **Type=oneshot**: 서비스가 한 번 실행되고 종료됨
- **TimeoutStartSec=900**: 최대 15분 대기 (VM 시작 시간 고려)
- **KillMode=none**: 서비스 종료 시에도 VM이 계속 실행됨
- **RemainAfterExit=yes**: 실행 후에도 서비스 상태 유지

### auto-reload-and-tunnel.sh 스크립트

**스크립트 동작 순서:**

1. **VM 상태 확인**
   - `vagrant status`로 현재 VM 상태 확인
   - running, poweroff, aborted 상태 카운트

2. **VM 시작 (필요시)**
   - poweroff 또는 aborted 상태의 VM이 있으면 `vagrant up` 실행
   - 모든 VM이 이미 running이면 스킵

3. **VM 준비 대기**
   - 모든 VM이 running 상태가 될 때까지 대기 (최대 5분)
   - 10초 간격으로 상태 확인

4. **SSH 연결 확인**
   - VirtualBox에서 VM이 실제로 실행 중인지 확인
   - 최대 2분 대기

5. **SSH 터널 시작**
   - 기존 SSH 터널 정리
   - `access-k8s-from-host.sh start` 실행
   - Kubernetes API 서버 접근을 위한 SSH 터널 생성

**스크립트 위치:**
- `~/workspaces/tz-drillquiz/provisioning/auto-reload-and-tunnel.sh`

---

## 설정 확인 및 테스트

### 서비스 상태 확인

```bash
# 서비스 활성화 여부 확인
systemctl --user is-enabled vagrant-reload.service

# 서비스 실행 상태 확인
systemctl --user status vagrant-reload.service

# linger 상태 확인
loginctl show-user $USER | grep Linger
```

### 서비스 로그 확인

```bash
# 실시간 로그 모니터링
journalctl --user -u vagrant-reload.service -f

# 최근 100줄 로그 확인
journalctl --user -u vagrant-reload.service -n 100

# 특정 시간 이후 로그 확인
journalctl --user -u vagrant-reload.service --since "1 hour ago"
```

### VM 상태 확인

```bash
# Vagrant VM 상태 확인
cd ~/workspaces/tz-k8s-vagrant
vagrant status

# VirtualBox에서 실행 중인 VM 확인
VBoxManage list runningvms
```

### SSH 터널 확인

```bash
# SSH 터널 상태 확인
cd ~/workspaces/tz-k8s-vagrant
bash access-k8s-from-host.sh status

# 또는 provisioning 디렉토리에서
cd ~/workspaces/tz-drillquiz/provisioning
bash access-k8s-from-host.sh status
```

### Kubernetes 연결 테스트

```bash
# kubectl로 클러스터 접근 테스트
kubectl get nodes

# Pod 상태 확인
kubectl get pods -n kube-system
```

---

## 문제 해결

### 문제 1: 서비스가 실행되지 않음

**증상:**
```bash
systemctl --user status vagrant-reload.service
# Active: inactive (dead)
```

**해결:**
1. **linger 활성화 확인:**
   ```bash
   loginctl enable-linger $USER
   loginctl show-user $USER | grep Linger
   ```

2. **서비스 파일 경로 확인:**
   ```bash
   ls -la ~/.config/systemd/user/vagrant-reload.service
   ```

3. **서비스 파일 권한 확인:**
   ```bash
   chmod 644 ~/.config/systemd/user/vagrant-reload.service
   ```

4. **daemon reload:**
   ```bash
   systemctl --user daemon-reload
   ```

### 문제 2: VM이 시작되지 않음

**증상:**
- 서비스는 실행되지만 VM이 시작되지 않음

**확인 사항:**
1. **로그 확인:**
   ```bash
   journalctl --user -u vagrant-reload.service -n 100
   ```

2. **Vagrant 경로 확인:**
   ```bash
   which vagrant
   cd ~/workspaces/tz-k8s-vagrant
   vagrant status
   ```

3. **VirtualBox 설치 확인:**
   ```bash
   VBoxManage --version
   ```

4. **수동 실행 테스트:**
   ```bash
   cd ~/workspaces/tz-k8s-vagrant
   bash ~/workspaces/tz-drillquiz/provisioning/auto-reload-and-tunnel.sh
   ```

### 문제 3: SSH 터널이 시작되지 않음

**증상:**
- VM은 시작되지만 SSH 터널이 생성되지 않음

**확인 사항:**
1. **VM SSH 연결 확인:**
   ```bash
   cd ~/workspaces/tz-k8s-vagrant
   vagrant ssh kube-master -- echo "SSH connection test"
   ```

2. **터널 스크립트 확인:**
   ```bash
   ls -la ~/workspaces/tz-drillquiz/provisioning/access-k8s-from-host.sh
   ```

3. **수동 터널 시작 테스트:**
   ```bash
   cd ~/workspaces/tz-k8s-vagrant
   bash access-k8s-from-host.sh start
   ```

### 문제 4: 서비스 타임아웃

**증상:**
- 서비스가 15분 내에 완료되지 않아 타임아웃 발생

**해결:**
1. **타임아웃 시간 증가 (필요시):**
   ```bash
   # 서비스 파일 수정
   vi ~/.config/systemd/user/vagrant-reload.service
   
   # TimeoutStartSec 값을 증가 (예: 1800 = 30분)
   TimeoutStartSec=1800
   
   # daemon reload
   systemctl --user daemon-reload
   ```

2. **VM 시작 시간 단축:**
   - VM 리소스 할당 확인
   - 불필요한 프로비저닝 스크립트 제거

### 문제 5: 재시작 후 서비스가 실행되지 않음

**증상:**
- 서버 재시작 후에도 VM이 자동으로 시작되지 않음

**확인 사항:**
1. **linger 상태 확인:**
   ```bash
   loginctl show-user $USER | grep Linger
   # Linger=yes 여야 함
   ```

2. **서비스 활성화 확인:**
   ```bash
   systemctl --user is-enabled vagrant-reload.service
   # enabled 여야 함
   ```

3. **서비스 파일 존재 확인:**
   ```bash
   ls -la ~/.config/systemd/user/vagrant-reload.service
   ```

4. **재시작 후 로그 확인:**
   ```bash
   journalctl --user -u vagrant-reload.service --since "boot"
   ```

---

## 서비스 관리 명령어

### my-ubuntu (Linux/systemd)

#### 서비스 시작/중지

```bash
# 서비스 시작 (수동)
systemctl --user start vagrant-reload.service

# 서비스 중지 (실행 중인 경우)
systemctl --user stop vagrant-reload.service

# 서비스 재시작
systemctl --user restart vagrant-reload.service
```

#### 서비스 활성화/비활성화

```bash
# 서비스 활성화 (재시작 시 자동 실행)
systemctl --user enable vagrant-reload.service

# 서비스 비활성화 (재시작 시 자동 실행 안 함)
systemctl --user disable vagrant-reload.service
```

#### 서비스 상태 확인

```bash
# 서비스 상태 확인
systemctl --user status vagrant-reload.service

# 서비스 활성화 여부 확인
systemctl --user is-enabled vagrant-reload.service

# 서비스 활성 상태 확인
systemctl --user is-active vagrant-reload.service
```

#### 로그 확인

```bash
# 실시간 로그
journalctl --user -u vagrant-reload.service -f

# 최근 로그
journalctl --user -u vagrant-reload.service -n 100

# 부팅 이후 로그
journalctl --user -u vagrant-reload.service --since "boot"

# 특정 시간 이후 로그
journalctl --user -u vagrant-reload.service --since "2026-01-23 00:00:00"
```

---

### my-mac (macOS/launchd)

#### 서비스 시작/중지

```bash
# 서비스 시작 (즉시 실행)
launchctl start com.vagrant.autostart

# 서비스 중지 (실행 중인 경우)
launchctl stop com.vagrant.autostart
```

#### 서비스 로드/언로드

```bash
# 서비스 로드 (재시작 시 자동 실행)
launchctl load ~/Library/LaunchAgents/com.vagrant.autostart.plist

# 서비스 언로드 (재시작 시 자동 실행 안 함)
launchctl unload ~/Library/LaunchAgents/com.vagrant.autostart.plist
```

#### 서비스 상태 확인

```bash
# 서비스 목록 확인
launchctl list | grep com.vagrant.autostart

# 서비스 상세 정보 확인
launchctl list com.vagrant.autostart
```

#### 로그 확인

```bash
# 표준 출력 로그 (실시간)
tail -f ~/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.log

# 에러 로그 (실시간)
tail -f ~/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.error.log

# 최근 로그 확인
tail -n 100 ~/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.log
```

---

## 환경 변수 설정

### WORKSPACE_BASE 커스터마이징

기본값은 `$HOME/workspaces`입니다. 다른 경로를 사용하는 경우:

**방법 1: 서비스 파일 수정**
```bash
vi ~/.config/systemd/user/vagrant-reload.service

# Environment 라인 수정
Environment="WORKSPACE_BASE=/custom/path/to/workspaces"

# daemon reload
systemctl --user daemon-reload
systemctl --user restart vagrant-reload.service
```

**방법 2: 환경 변수 파일 사용**
```bash
# ~/.config/systemd/user/vagrant-reload.service.d/override.conf 생성
mkdir -p ~/.config/systemd/user/vagrant-reload.service.d
cat > ~/.config/systemd/user/vagrant-reload.service.d/override.conf <<EOF
[Service]
Environment="WORKSPACE_BASE=/custom/path/to/workspaces"
EOF

# daemon reload
systemctl --user daemon-reload
```

---

## 주의사항

### 1. VM이 계속 실행됨

- `KillMode=none` 설정으로 서비스가 종료되어도 VM은 계속 실행됩니다.
- VM을 중지하려면 수동으로 `vagrant halt`를 실행해야 합니다.

### 2. 리소스 사용

- 모든 VM이 자동으로 시작되므로 서버 리소스를 충분히 확보해야 합니다.
- 필요시 특정 VM만 시작하도록 스크립트를 수정할 수 있습니다.

### 3. 네트워크 의존성

- 서비스는 `network.target` 이후에 실행됩니다.
- 네트워크가 완전히 준비되기 전에 실행될 수 있으므로, 스크립트 내에서 재시도 로직이 포함되어 있습니다.

### 4. SSH 키 인증

- Vagrant SSH 키가 올바르게 설정되어 있어야 합니다.
- `~/.vagrant.d/insecure_private_key` 또는 설정된 SSH 키가 필요합니다.

---

## 관련 파일

### my-ubuntu (Linux/systemd)
- **서비스 파일**: `~/workspaces/tz-drillquiz/provisioning/vagrant-reload.service`
- **서비스 설치 위치**: `~/.config/systemd/user/vagrant-reload.service`

### my-mac (macOS/launchd)
- **서비스 파일**: `~/workspaces/tz-drillquiz/provisioning/com.vagrant.autostart.plist`
- **서비스 설치 위치**: `~/Library/LaunchAgents/com.vagrant.autostart.plist`

### 공통 파일
- **실행 스크립트**: `~/workspaces/tz-drillquiz/provisioning/auto-reload-and-tunnel.sh`
- **SSH 터널 스크립트**: `~/workspaces/tz-k8s-vagrant/access-k8s-from-host.sh`
- **로그 파일 (macOS)**: 
  - `~/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.log`
  - `~/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.error.log`

---

## 빠른 설정 요약

### my-ubuntu (Linux/systemd)

```bash
# 1. 서비스 파일 복사
mkdir -p ~/.config/systemd/user
cp ~/workspaces/tz-drillquiz/provisioning/vagrant-reload.service ~/.config/systemd/user/

# 2. daemon reload
systemctl --user daemon-reload

# 3. 서비스 활성화
systemctl --user enable vagrant-reload.service

# 4. linger 활성화
loginctl enable-linger $USER

# 5. 서비스 테스트
systemctl --user start vagrant-reload.service

# 6. 상태 확인
systemctl --user status vagrant-reload.service
journalctl --user -u vagrant-reload.service -f
```

### my-mac (macOS/launchd)

```bash
# 1. plist 파일 복사 및 경로 수정
cp ~/workspaces/tz-drillquiz/provisioning/com.vagrant.autostart.plist ~/Library/LaunchAgents/
vi ~/Library/LaunchAgents/com.vagrant.autostart.plist  # 경로 수정 필요

# 2. 로그 디렉토리 생성
mkdir -p ~/workspaces/tz-drillquiz/provisioning/logs

# 3. 서비스 로드
launchctl load ~/Library/LaunchAgents/com.vagrant.autostart.plist

# 4. 서비스 시작 (테스트)
launchctl start com.vagrant.autostart

# 5. 상태 확인
launchctl list | grep com.vagrant.autostart
tail -f ~/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.log
```

---

## 작성일

2026-01-23

## 참고 자료

### Linux/systemd
- [systemd user services](https://wiki.archlinux.org/title/Systemd/User)
- [REINSTALL_PLAN.md](../provisioning/REINSTALL_PLAN.md) - 4.1.1 섹션 참조

### macOS/launchd
- [Apple Developer - Launch Agents and Daemons](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
- [launchd.plist man page](https://www.manpagez.com/man/5/launchd.plist/)

### 공통
- [Vagrant documentation](https://www.vagrantup.com/docs)
