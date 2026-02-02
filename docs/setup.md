# 호스트·자동 시작 설정

재부팅 시 Vagrant VM 자동 시작 및 SSH 터널 설정. **my-ubuntu**: Linux (systemd). **my-mac**: macOS (launchd).

---

## my-ubuntu (systemd)

1. 서비스 파일 복사: `mkdir -p ~/.config/systemd/user` 후 `cp ~/workspaces/tz-drillquiz/provisioning/vagrant-reload.service ~/.config/systemd/user/`
2. `systemctl --user daemon-reload`
3. `systemctl --user enable vagrant-reload.service`
4. **linger**: `loginctl enable-linger $USER` (로그인 없이도 서비스 실행)
5. 테스트: `systemctl --user start vagrant-reload.service`, `systemctl --user status vagrant-reload.service`

**로그**: `journalctl --user -u vagrant-reload.service -f`

---

## my-mac (launchd)

1. plist 복사: `cp ~/workspaces/tz-drillquiz/provisioning/com.vagrant.autostart.plist ~/Library/LaunchAgents/`
2. plist 수정: `ProgramArguments`(스크립트 경로), `EnvironmentVariables`(WORKSPACE_BASE), `StandardOutPath`/`StandardErrorPath`(로그 경로)를 실제 사용자 경로로 변경
3. `mkdir -p ~/workspaces/tz-drillquiz/provisioning/logs`
4. `launchctl load ~/Library/LaunchAgents/com.vagrant.autostart.plist`
5. 테스트: `launchctl start com.vagrant.autostart`, `launchctl list | grep com.vagrant.autostart`

**로그**: `tail -f ~/workspaces/tz-drillquiz/provisioning/logs/vagrant-autostart.log`

macOS는 로그인 후 LaunchAgents 실행. 로그인 없이 실행하려면 LaunchDaemons(root) 필요.

---

## 서비스 동작

- **vagrant-reload.service**: `ExecStart` → `auto-reload-and-tunnel.sh`. Type=oneshot, TimeoutStartSec=900, KillMode=none, RemainAfterExit=yes.
- **auto-reload-and-tunnel.sh**: VM 상태 확인 → poweroff/aborted면 `vagrant up` → VM running 대기 → SSH 터널 `provisioning/access-k8s-from-host.sh start`

**관련 파일**: 서비스 원본 `~/workspaces/tz-drillquiz/provisioning/vagrant-reload.service` (ubuntu), `com.vagrant.autostart.plist` (mac). 스크립트 `provisioning/auto-reload-and-tunnel.sh`, `provisioning/access-k8s-from-host.sh`.

---

## Access Kubernetes from host (my-ubuntu)

스크립트 위치: **`~/workspaces/tz-drillquiz/provisioning/access-k8s-from-host.sh`** (tz-k8s-vagrant가 아님).

**사전 조건**: Vagrant VM(kube-master, kube-node-1, kube-node-2) 실행 중, my-ubuntu에 kubectl 설치, my-ubuntu에서 실행.

```bash
cd ~/workspaces/tz-drillquiz/provisioning

# SSH 터널 시작 및 kubeconfig 복사
./access-k8s-from-host.sh start

# 터널 상태 확인
./access-k8s-from-host.sh status

# 연결 테스트
./access-k8s-from-host.sh test

# 터널 중지
./access-k8s-from-host.sh stop

# 터널 재시작
./access-k8s-from-host.sh restart
```

---

## 설정 확인

- **상태**: `systemctl --user is-enabled vagrant-reload.service` (ubuntu), `launchctl list | grep vagrant` (mac)
- **VM**: `cd ~/workspaces/tz-k8s-vagrant && vagrant status`
- **터널**: `cd ~/workspaces/tz-drillquiz/provisioning && bash access-k8s-from-host.sh status`
- **K8s**: `kubectl get nodes`, `kubectl get pods -n kube-system`

---

## 문제 해결

- **서비스 미실행 (ubuntu)**: linger 확인 `loginctl enable-linger $USER`, 서비스 파일·권한, `systemctl --user daemon-reload`
- **VM 미시작**: 로그 확인, vagrant/VBoxManage 경로, 수동 `bash provisioning/auto-reload-and-tunnel.sh`
- **터널 미생성**: `vagrant ssh kube-master -- echo OK`, `cd ~/workspaces/tz-drillquiz/provisioning && bash access-k8s-from-host.sh start`
- **타임아웃**: 서비스 파일에서 `TimeoutStartSec=1800` 등 증가
- **재시작 후 미실행**: linger/enable 상태, `journalctl --user -u vagrant-reload.service --since "boot"`

---

## 빠른 설정 요약

**my-ubuntu**:
```bash
mkdir -p ~/.config/systemd/user
cp ~/workspaces/tz-drillquiz/provisioning/vagrant-reload.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable vagrant-reload.service
loginctl enable-linger $USER
systemctl --user start vagrant-reload.service
```

**my-mac**:
```bash
cp ~/workspaces/tz-drillquiz/provisioning/com.vagrant.autostart.plist ~/Library/LaunchAgents/
# plist 경로 수정 후
mkdir -p ~/workspaces/tz-drillquiz/provisioning/logs
launchctl load ~/Library/LaunchAgents/com.vagrant.autostart.plist
launchctl start com.vagrant.autostart
```

---

## my-mac2

my-mac과 동일: `auto-reload-and-tunnel.sh`, `backup-vms.sh`, `com.vagrant.autostart.plist`. VM: `kube-master3`, `kube-node3-1`.

**launchd 로드**: GUI 세션에서만 가능. SSH로는 로드 불가. 터미널에서:
```bash
launchctl unload ~/Library/LaunchAgents/com.vagrant.autostart.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.vagrant.autostart.plist
launchctl list | grep vagrant
```
또는 재부팅.

**상태 확인**: `vagrant status`, `launchctl list | grep vagrant`, `tail -f provisioning/logs/vagrant-autostart.log`, `bash scripts/backup-vms.sh list`

**문제**: launchd 미로드 → GUI에서 load 또는 재부팅. VM 카운팅 (0/0) → `auto-reload-and-tunnel.sh` 최신·TOTAL_COUNT 확인. 백업 미실행 → `AUTO_BACKUP_ENABLED=true`, 재부팅 후 1시간 이내, 또는 수동 `bash scripts/backup-vms.sh backup`

**파일 위치**: 자동 시작 `provisioning/auto-reload-and-tunnel.sh`, 백업 `scripts/backup-vms.sh`, plist `~/Library/LaunchAgents/com.vagrant.autostart.plist`, 로그 `provisioning/logs/vagrant-autostart.log`, 백업 디렉토리 `~/vagrant-backups/`
