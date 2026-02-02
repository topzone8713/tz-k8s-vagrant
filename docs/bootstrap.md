# 부트스트랩·프로비저닝

## 사용법 (명령 참조)

- **인자 없음**: VM 없으면 `vagrant up`, 있으면 `vagrant reload` (이전 선택 재사용)
- **halt**: VM 중지 (`vagrant halt`)
- **reload**: VM 재시작 (`vagrant reload`)
- **provision**: VM이 이미 있을 때 kubespray 등 프로비저닝 실행
- **status**: VM 상태 (`vagrant status`)
- **save**: 스냅샷 저장 (`vagrant snapshot save <이름>`)
- **restore \<이름>**: 스냅샷 복원
- **delete \<이름>**: 스냅샷 삭제
- **ssh**: 마스터 노드 SSH (`vagrant ssh kube-master`)
- **remove**: 환경 완전 제거 (`vagrant destroy -f`)

첫 설정 시 `A_ENV`(M/S) 등 질문에 답하면 기록되어 이후 자동 적용됩니다.

---

## bootstrap.sh 동작

`bootstrap.sh`는 Vagrant VM 생명주기와 Kubernetes 클러스터 자동 설치를 관리합니다.

### A_ENV (환경 타입)

- 환경변수 `A_ENV` 있으면 그 값 사용. 없으면 **기본값 "M" (Master)**.
- `M`: Master (kube-master, kube-node-1, kube-node-2). `S`: Slave (kube-slave-*).

### EVENT (작업 타입)

- `vagrant status`에서 `kube-master` 또는 `kube-slave-1`이 `not created` → `EVENT='up'` (VM 생성)
- 아니면 → `EVENT='reload'` (VM 재시작)
- **VM이 이미 있으면 kubespray 스킵**. kubespray 실행하려면 VM 삭제 후 `up` 필요.

### EVENT='up'일 때

1. `info` 생성 2. `vagrant up` 3. Static IP 설정 4. A_ENV='M'이면 kubespray.sh, master_01.sh 실행

### EVENT='reload'일 때

- `PROVISION='y'`이면 kubespray 실행. 없으면 `vagrant reload`만.

### kubespray 실행 조건

- 실행: `EVENT='up'` AND `A_ENV='M'` 또는 `EVENT='reload'` AND `PROVISION='y'` AND `A_ENV='M'`
- 스킵: `reload`이고 provision 없음, 또는 `A_ENV='S'`

### 처음부터 설치

```bash
bash bootstrap.sh remove
bash bootstrap.sh
```

### 기존 VM에 kubespray

```bash
bash bootstrap.sh provision
```

---

## Provision (base.sh) 실행 추적

**증상**: `base.sh`가 실행되지 않아 kubectl, helm 미설치.

**흐름**: Vagrantfile provision → master.sh / node.sh → base.sh → kubectl, helm 설치.

**실행 조건**: VM **처음 생성 시** (`vagrant up`)에만 provision. `vagrant reload` 시에는 실행 안 됨. 강제: `vagrant provision` 또는 `vagrant up --provision`.

**가능 원인**: VM 이미 있는 상태에서 reload만 실행 / base.sh 호출 전 에러 / base.sh 내부·네트워크 실패.

**디버깅**:
- VM 내부: `sudo bash /vagrant/scripts/local/check-provision.sh`, `sudo bash /vagrant/scripts/local/base.sh`
- 호스트: `vagrant up --debug 2>&1 | tee vagrant-debug.log`

**해결**:
- VM 재생성: `bash bootstrap.sh remove` 후 `bash bootstrap.sh up`
- Provision 강제: `vagrant provision` 또는 `vagrant provision kube-master` 등
- 수동 base.sh: `vagrant ssh kube-master -c "sudo bash /vagrant/scripts/local/base.sh"` (각 노드 동일)

**문제 해결**: kubespray 미실행 → `bootstrap.sh remove` 후 `bash bootstrap.sh` 또는 `bash bootstrap.sh provision`. A_ENV → `A_ENV=M bash bootstrap.sh`.
