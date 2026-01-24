# bootstrap.sh 동작 방식 문서

## 개요
`bootstrap.sh`는 Vagrant VM의 생명주기를 관리하고 Kubernetes 클러스터를 자동으로 설치하는 스크립트입니다.

## 주요 동작 로직

### 1. A_ENV (환경 타입) 결정 로직

```bash
# 환경변수에서 A_ENV 확인, 없으면 기본값 "M" 사용
if [ -z "${A_ENV}" ]; then
  A_ENV="M"
  echo "Using default A_ENV=M (Master)"
else
  echo "Using A_ENV from environment: ${A_ENV}"
fi

# info 파일이 있고, 환경변수가 없으면 Vagrantfile에서 확인
if [ -f info ] && [ -z "${A_ENV}" ]; then
  A_ENV_CHECK=`cat Vagrantfile | grep 'kube-master'`
  if [[ "${A_ENV_CHECK}" != "" ]]; then
    A_ENV="M"
  else
    A_ENV="S"
  fi
fi
```

**동작:**
- 환경변수 `A_ENV`가 설정되어 있으면 그 값을 사용
- 환경변수가 없으면 **항상 기본값 "M" (Master)으로 설정**
- `info` 파일이 존재하고 환경변수가 없을 때만 Vagrantfile에서 확인

**A_ENV 값:**
- `M`: Master 모드 (kube-master, kube-node-1, kube-node-2)
- `S`: Slave 모드 (kube-slave-1, kube-slave-2, kube-slave-3)

### 2. EVENT (작업 타입) 결정 로직

```bash
EVENT=`vagrant status | grep -E 'kube-master|kube-slave-1' | grep 'not created'`
if [[ "${EVENT}" != "" ]]; then
  EVENT='up'
else
  EVENT='reload'
fi
```

**동작:**
- `vagrant status`로 `kube-master` 또는 `kube-slave-1`이 `not created` 상태인지 확인
- `not created`가 발견되면 → `EVENT='up'` (VM 생성)
- `not created`가 없으면 → `EVENT='reload'` (VM 재시작)

**중요:**
- **VM이 이미 존재하면 `EVENT='reload'`가 되어 kubespray가 스킵됩니다**
- kubespray를 실행하려면 **반드시 VM을 삭제하고 `EVENT='up'` 상태로 만들어야 합니다**

### 3. EVENT='up'일 때의 동작

```bash
if [[ "${EVENT}" == "up" ]]; then
  # 1. info 파일 생성
  echo "- PC Type: ${A_ENV}" > info
  
  # 2. VM 생성
  vagrant ${EVENT} --provider=virtualbox
  
  # 3. Static IP 설정
  if [ -f scripts/local/apply-static-ip-ubuntu.sh ]; then
    bash scripts/local/apply-static-ip-ubuntu.sh
  elif [ -f scripts/local/apply-static-ip.sh ]; then
    bash scripts/local/apply-static-ip.sh
  fi
  
  # 4. A_ENV가 "M"이면 kubespray 실행
  if [[ "${A_ENV}" == "M" ]]; then
    vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/kubespray.sh"
    vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/master_01.sh"
  fi
fi
```

**실행 순서:**
1. `info` 파일 생성
2. `vagrant up` 실행 (VM 생성)
3. Static IP 설정 적용
4. **A_ENV가 "M"이면 kubespray.sh 실행** (Kubernetes 설치)
5. master_01.sh 실행

### 4. EVENT='reload'일 때의 동작

```bash
else
  if [[ "${PROVISION}" == "y" ]]; then
    # provision 플래그가 있으면 kubespray 실행
    if [[ "${A_ENV}" == "M" ]]; then
      vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/kubespray.sh"
      vagrant ssh kube-master -- -t "sudo bash /vagrant/scripts/local/master_01.sh"
    fi
  else
    # provision 플래그가 없으면 단순히 vagrant reload만 실행
    vagrant ${EVENT}
  fi
fi
```

**동작:**
- `PROVISION='y'` 플래그가 있으면 kubespray 실행
- 플래그가 없으면 **kubespray가 스킵되고 `vagrant reload`만 실행**

### 5. 명령어 옵션

```bash
bash bootstrap.sh [옵션]
```

**옵션:**
- (없음): VM 상태에 따라 `up` 또는 `reload` 실행
- `halt`: `vagrant halt` (VM 중지)
- `reload`: `vagrant reload` (VM 재시작)
- `provision`: kubespray 실행 (VM이 이미 존재할 때)
- `status`: `vagrant status` (VM 상태 확인)
- `remove`: `vagrant destroy -f` (VM 삭제)
- `ssh`: `vagrant ssh kube-master` (마스터 노드 접속)

## 중요한 동작 원리

### kubespray가 실행되는 조건

**kubespray가 실행되는 경우:**
1. `EVENT='up'` **AND** `A_ENV='M'` → 자동 실행
2. `EVENT='reload'` **AND** `PROVISION='y'` **AND** `A_ENV='M'` → 수동 실행

**kubespray가 스킵되는 경우:**
1. `EVENT='reload'` **AND** `PROVISION` 플래그 없음 → 스킵
2. `A_ENV='S'` → 스킵 (Slave 모드는 kubespray 없음)

### 처음부터 설치하는 방법

**올바른 방법:**
```bash
# 1. 기존 VM 삭제
bash bootstrap.sh remove

# 2. info 파일 삭제 (선택사항)
rm -f info

# 3. 처음부터 설치
bash bootstrap.sh
```

**결과:**
- `EVENT='up'` (모든 VM이 `not created` 상태)
- `A_ENV='M'` (기본값)
- kubespray.sh 자동 실행
- Kubernetes 설치 완료

### VM이 이미 존재할 때 kubespray 실행하는 방법

**방법 1: VM 삭제 후 재생성**
```bash
bash bootstrap.sh remove
bash bootstrap.sh
```

**방법 2: provision 플래그 사용**
```bash
bash bootstrap.sh provision
```

## 문제 해결

### 문제: kubespray가 실행되지 않음

**원인:**
- VM이 이미 존재해서 `EVENT='reload'`로 설정됨
- `PROVISION` 플래그가 없어서 kubespray가 스킵됨

**해결:**
```bash
# VM 삭제 후 재생성
bash bootstrap.sh remove
bash bootstrap.sh

# 또는 provision 플래그 사용
bash bootstrap.sh provision
```

### 문제: A_ENV가 잘못 설정됨

**원인:**
- 이전 버전에서는 `info` 파일이 있으면 Vagrantfile에서 확인하여 "S"로 설정될 수 있었음

**해결:**
- 현재 버전에서는 환경변수가 없으면 항상 기본값 "M"으로 설정됨
- 환경변수로 명시적으로 설정 가능: `A_ENV=M bash bootstrap.sh`

## 요약

1. **A_ENV 기본값**: 환경변수가 없으면 항상 "M" (Master)
2. **EVENT 결정**: VM이 `not created`이면 `up`, 아니면 `reload`
3. **kubespray 실행**: `EVENT='up'`이거나 `PROVISION='y'`일 때만 실행
4. **처음부터 설치**: `bash bootstrap.sh remove` 후 `bash bootstrap.sh` 실행
5. **기존 VM에 kubespray 실행**: `bash bootstrap.sh provision` 실행
