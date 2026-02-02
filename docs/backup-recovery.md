# 백업·복구

## 개요

- **백업**: Vagrant VM 전체 상태(VirtualBox VM 파일, Vagrantfile, Kubernetes 클러스터 상태) 보존. VirtualBox 스냅샷은 불안정하므로 VM 전체 복사 방식 사용.
- **⚠️ VM 재생성 금지**: `vagrant destroy` 시 클러스터·설정·데이터가 모두 삭제됩니다. 복구는 백업 또는 아래 방법만 사용하세요.

---

## 자동 백업

VM 기동 후 자동 백업: `auto-reload-and-tunnel.sh`가 VM 기동 확인 후 실행. 재부팅 시에도 launchd/systemd로 VM 기동 후 실행.

**조건**: `AUTO_BACKUP_ENABLED=true`, 마지막 백업 후 24시간 이상, 스크립트 존재. 백그라운드 실행, 로그: `/tmp/vagrant-auto-backup.log`.

**설정**: 환경변수 `AUTO_BACKUP_ENABLED=true|false`. plist에 `AUTO_BACKUP_ENABLED` 추가. 간격: `auto-reload-and-tunnel.sh` 내 `BACKUP_INTERVAL=86400` (24시간).

**확인**: `tail -f /tmp/vagrant-auto-backup.log`, `bash scripts/backup-vms.sh list`

**수동 백업**: `cd ~/workspaces/tz-k8s-vagrant && bash scripts/backup-vms.sh`

---

## 백업 방법·스크립트

| 방법 | 장점 | 단점 | 안정성 |
|------|------|------|--------|
| VirtualBox 스냅샷 | 빠름 | 불안정 | ⭐⭐ |
| Vagrant package | 간단 | VM 중지 필요 | ⭐⭐⭐ |
| **VM 전체 복사** | **가장 안정** | 용량·시간 | ⭐⭐⭐⭐⭐ |

**스크립트 사용**:
- 백업: `bash scripts/backup-vms.sh` 또는 `bash scripts/backup-vms.sh backup` → `~/vagrant-backups/vagrant-vms-YYYYMMDD-HHMMSS/`
- 목록: `bash scripts/backup-vms.sh list`
- 복원: `bash scripts/backup-vms.sh restore latest` 또는 `restore vagrant-vms-YYYYMMDD-HHMMSS`
- 개수 제한: `bash scripts/backup-vms.sh limit` (기본 10개), `MAX_BACKUP_COUNT=5 bash scripts/backup-vms.sh limit`
- 오래된 삭제: `bash scripts/backup-vms.sh clean 7` (7일 이상)

**백업 크기**: 작은 백업(설정만) / 큰 백업(VM 파일 포함). 완전 복구는 VM 파일 포함 백업 필요.

---

## 사용 시나리오·복원

1. **VM 삭제됨**: `bash scripts/backup-vms.sh restore latest` (또는 특정 백업명)
2. **VM aborted**: `vagrant halt` → `bash scripts/backup-vms.sh restore latest` → VirtualBox에서 VM 수동 등록(.vbox) → `vagrant up`
3. **클러스터 손상**: 백업에 클러스터 상태 포함 → `restore latest`로 복구
4. **설정 변경 전**: `bash scripts/backup-vms.sh` 실행 후 변경, 문제 시 `restore latest`

**자동 복원**: 설정 파일(Vagrantfile, .vagrant 등)만 복원. **VM 파일**: 수동으로 VirtualBox에서 .vbox 등록 후 `vagrant up`.

**백업 디렉토리 구조**: `backup-info.txt`, `Vagrantfile`, `.vagrant/`, `scripts/`, `resource/`, `vms/<vm-name>/` 등.

---

## VM 복구 (aborted 시)

**절대 사용 금지**: `vagrant destroy -f`

**올바른 순서**:
1. 백업에서 복구: `bash scripts/backup-vms.sh list` → `bash scripts/backup-vms.sh restore latest`
2. 없으면: `vagrant up` 또는 `vagrant up --no-provision` 시도
3. 그래도 안 되면: VirtualBox에서 `VBoxManage startvm <VM-UUID> --type headless`
4. Vagrant 스냅샷 있으면: `vagrant halt` → `vagrant snapshot restore <vm> <스냅샷이름>` → `vagrant up`

**복구 후 확인**: `vagrant status`, `vagrant ssh kube-master2 -- -t 'sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes'`

---

## 문제 해결·주의사항

- **자동 백업 미실행**: `echo $AUTO_BACKUP_ENABLED`, 스크립트 경로·권한. 너무 자주 → `BACKUP_INTERVAL` 증가 또는 `AUTO_BACKUP_ENABLED=false`. 디스크 부족 → `bash scripts/backup-vms.sh limit`, `clean 7`
- **백업 실패(VM 실행 중)**: `vagrant halt` 후 백업, `vagrant up`
- **복원 후 미기동**: VirtualBox UUID 충돌 → `VBoxManage unregistervm` / `registervm` 또는 UUID 변경
- **VM 계속 aborted**: VirtualBox 로그(Log folder), 리소스 확인 후 `VBoxManage startvm <VM-UUID> --type headless`

복원은 현재 VM을 덮어씀. 복원 전 백업 권장. VM 파일은 수동 등록 필요. 백업 시점 이후 변경사항은 사라짐. VM 백업 용량 크므로 디스크·최대 10개 유지 확인.
