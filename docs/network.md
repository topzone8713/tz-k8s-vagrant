# Kubernetes 클러스터 네트워크 구성 가이드

## 목차
1. [개요](#개요)
2. [네트워크 아키텍처](#네트워크-아키텍처)
3. [Vagrantfile 네트워크 구성](#vagrantfile-네트워크-구성)
4. [Static IP 설정](#static-ip-설정)
5. [MetalLB IP 풀 구성](#metallb-ip-풀-구성)
6. [Ingress 접근 설정](#ingress-접근-설정)
7. [문제 해결](#문제-해결)
8. [검증 방법](#검증-방법)

---

## 개요

이 문서는 여러 호스트(my-ubuntu, my-mac, my-mac2)에 분산된 Kubernetes 클러스터의 네트워크 구성을 설명합니다.

### 네트워크 구성 요약

- **Kubernetes 내부 네트워크**: `192.168.0.0/24` (VM 간 통신)
- **호스트 접근 네트워크**: `192.168.0.0/24` (호스트에서 VM 접근)
- **MetalLB IP 풀**: `192.168.0.210-250` (LoadBalancer 서비스용)
- **Ingress IP**: `192.168.0.210` (외부 접근용)
- **검증 상태**: 호스트(my-ubuntu, my-mac, my-mac2) 간 네트워크, 노드·Pod 간 통신, DNS 통신 정상 확인됨.

### 왜 Static IP가 필요한가?

Vagrant의 `public_network`에서 `ip:` 옵션을 지정해도, 실제로는 DHCP로 동작할 수 있습니다. 특히 macOS에서 VirtualBox의 bridged network는 DHCP를 사용할 수 있습니다.

**IP가 변경되면 발생할 수 있는 문제:**

1. **kubespray inventory의 IP 불일치**: 노드 추가/관리 불가
2. **Kubernetes 노드 간 통신 실패**: 노드들이 서로 찾을 수 없음
3. **kubelet API 서버 접근 불가**: 노드가 클러스터에서 분리됨
4. **Calico CNI 네트워크 구성 오류**: 노드 IP 기반 네트워크 구성 실패

---

## 네트워크 아키텍처

### VM 네트워크 인터페이스 구성

각 VM은 세 개의 네트워크 인터페이스를 가집니다:

1. **eth0**: VirtualBox NAT (인터넷 접근용)
   - IP: `10.0.2.15/24` (자동 할당)
   - 용도: 기본 인터넷 접근

2. **eth1**: Kubernetes 클러스터 내부 통신용
   - IP 범위: `192.168.0.100-107`
   - 용도: Kubernetes 노드 간 통신, Pod 네트워킹

3. **eth2**: 호스트 접근용
   - IP 범위: `192.168.0.100-107`
   - 용도: 호스트에서 VM 직접 접근, Kubernetes API 접근, 기본 게이트웨이

### 호스트별 VM 구성

#### my-ubuntu
- `kube-master`: 192.168.0.100 (eth1), 192.168.0.100 (eth2)
- `kube-node-1`: 192.168.0.101 (eth1), 192.168.0.101 (eth2)
- `kube-node-2`: 192.168.0.102 (eth1), 192.168.0.102 (eth2)

#### my-mac
- `kube-master2`: 192.168.0.103 (eth1), 192.168.0.103 (eth2)
- `kube-node2-1`: 192.168.0.104 (eth1), 192.168.0.104 (eth2)
- `kube-node2-2`: 192.168.0.105 (eth1), 192.168.0.105 (eth2)

#### my-mac2
- `kube-master3`: 192.168.0.106 (eth1), 192.168.0.106 (eth2)
- `kube-node3-1`: 192.168.0.107 (eth1), 192.168.0.107 (eth2)

### 네트워크 다이어그램

```
┌─────────────────────────────────────────────────────────────┐
│                    MacBook (192.168.0.133)                    │
│                    (개발자 워크스테이션)                        │
└───────────────────────┬───────────────────────────────────────┘
                        │
                        │ 192.168.0.0/24 네트워크
                        │
        ┌───────────────┴───────────────┐
        │                               │
┌───────▼────────┐              ┌──────▼────────┐
│  my-ubuntu     │              │  my-mac        │
│  (192.168.0.139)│              │  (192.168.0.x) │
│                │              │                │
│  ┌──────────┐  │              │  ┌──────────┐  │
│  │kube-master│  │              │  │kube-master2│ │
│  │eth2: .100 │  │              │  │eth2: .103 │ │
│  └──────────┘  │              │  └──────────┘  │
└────────────────┘              └────────────────┘
        │                               │
        │ 192.168.0.0/24 네트워크      │
        │ (Kubernetes 클러스터 내부)     │
        │                               │
┌───────┴───────────────────────────────┴────────┐
│         Kubernetes 클러스터                     │
│                                                 │
│  ┌──────────────────────────────────────────┐ │
│  │  MetalLB (192.168.0.210-250)             │ │
│  │  └─> ingress-nginx-controller            │ │
│  │      IP: 192.168.0.210                   │ │
│  └──────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

---

## Vagrantfile 네트워크 구성

### 핵심 원칙

**중요**: 모든 호스트의 VM들은 `public_network`를 사용하여 실제 물리 네트워크에 브리지해야 합니다. 이렇게 해야 서로 다른 물리 호스트의 VM들이 같은 네트워크 세그먼트에서 통신할 수 있습니다.

### private_network vs public_network

**private_network:**
- VirtualBox Host-Only 네트워크 사용
- 같은 호스트 내 VM들 간 통신만 가능
- 다른 물리 호스트의 VM들과 통신 불가
- ❌ my-ubuntu의 VM들과 통신 불가

**public_network:**
- 실제 물리 네트워크에 브리지
- 같은 물리 네트워크 세그먼트의 모든 장치와 통신 가능
- ✅ my-ubuntu의 VM들과 통신 가능

### my-ubuntu의 Vagrantfile

```ruby
config.vm.define "kube-master" do |master|
  master.vm.box = IMAGE_NAME
  master.vm.provider "virtualbox" do |vb|
    vb.memory = 5096
    vb.cpus = 3
  end
  # Kubernetes 네트워크 (192.168.0.x)
  master.vm.network "public_network", bridge: "en0: Wi-Fi (AirPort)", ip: "192.168.0.100"
  # 호스트 접근용 네트워크 (192.168.0.x)
  master.vm.network "public_network", bridge: "eno1", ip: "192.168.0.100"
  master.vm.hostname = "kube-master"
end
```

### my-mac의 Vagrantfile

**현재 상태**: `private_network`를 사용하지만, 이전에 `public_network`로 설정했던 eth2 인터페이스가 남아있어 정상 작동 중입니다.

**권장 설정** (일관성을 위해):
```ruby
config.vm.define "kube-master2" do |master|
  master.vm.box = IMAGE_NAME
  master.vm.provider "virtualbox" do |vb|
    vb.memory = 5096
    vb.cpus = 3
  end
  # Kubernetes 네트워크 (my-ubuntu와 동일한 물리 네트워크)
  master.vm.network "public_network", bridge: "en0: Wi-Fi (AirPort)", ip: "192.168.0.103"
  # 호스트 접근용 네트워크 추가
  master.vm.network "public_network", bridge: "en0: Wi-Fi (AirPort)", ip: "192.168.0.103"
  master.vm.hostname = "kube-master2"
end
```

### my-mac2의 Vagrantfile (최종)

```ruby
config.vm.define "kube-master3" do |master|
  master.vm.box = IMAGE_NAME
  master.vm.provider "virtualbox" do |vb|
    vb.memory = 2048
    vb.cpus = 2
  end
  # Kubernetes 네트워크 (my-ubuntu와 동일한 물리 네트워크)
  master.vm.network "public_network", bridge: "en0: Wi-Fi (AirPort)", ip: "192.168.0.106"
  # 호스트 접근용 네트워크 추가
  master.vm.network "public_network", bridge: "en0: Wi-Fi (AirPort)", ip: "192.168.0.106"
  master.vm.hostname = "kube-master3"
end

config.vm.define "kube-node3-1" do |node|
  node.vm.box = IMAGE_NAME
  node.vm.provider "virtualbox" do |vb|
    vb.memory = 1536
    vb.cpus = 1
  end
  # Kubernetes 네트워크
  node.vm.network "public_network", bridge: "en0: Wi-Fi (AirPort)", ip: "192.168.0.107"
  # 호스트 접근용 네트워크 추가
  node.vm.network "public_network", bridge: "en0: Wi-Fi (AirPort)", ip: "192.168.0.107"
  node.vm.hostname = "kube-node3-1"
end
```

### 네트워크 브리지 선택

**macOS에서 `bridge: "en0: Wi-Fi (AirPort)"`를 사용하는 이유:**
- Wi-Fi 인터페이스가 실제 물리 네트워크에 연결되어 있음
- 192.168.0.x 네트워크가 Wi-Fi 네트워크에 존재
- 다른 호스트(my-ubuntu)의 VM들과 같은 네트워크 세그먼트에 접근 가능

**my-ubuntu에서 `bridge: "eno1"`을 사용하는 이유:**
- 이더넷 인터페이스가 실제 물리 네트워크에 연결되어 있음
- 192.168.0.x 네트워크는 이더넷 인터페이스를 통해 접근

---

## Static IP 설정

### 자동 설정 스크립트 사용 (권장)

통합 스크립트를 사용하여 모든 VM에 Static IP를 자동으로 설정할 수 있습니다:

```bash
# 프로젝트 루트에서 실행
cd ~/workspaces/tz-k8s-vagrant  # 또는 해당 호스트의 프로젝트 경로
bash scripts/local/vm-network.sh apply-static-ip
```

이 스크립트는:
- 호스트를 자동 감지 (my-ubuntu, my-mac, my-mac2)
- 실행 중인 VM 목록 확인
- 각 VM에 적절한 Static IP 자동 설정
- 설정 결과 검증

### 수동 설정

개별 VM에 수동으로 Static IP를 설정하려면:

```bash
# VM에 접속
vagrant ssh <vm-name>

# Kubernetes 네트워크 인터페이스에 static IP 설정
sudo bash /vagrant/scripts/local/vm-network.sh configure-interface eth1 <k8s-ip> 255.255.255.0 <k8s-gateway> "8.8.8.8 8.8.4.4"

# 호스트 접근용 인터페이스에 static IP 설정
sudo bash /vagrant/scripts/local/vm-network.sh configure-interface eth2 <host-ip> 255.255.255.0 <host-gateway> "8.8.8.8 8.8.4.4"
```

**예시:**
```bash
# kube-master3에 접속
vagrant ssh kube-master3

# Kubernetes 네트워크 인터페이스에 static IP 설정
sudo bash /vagrant/scripts/local/vm-network.sh configure-interface eth1 192.168.0.106 255.255.255.0 192.168.0.1 "8.8.8.8 8.8.4.4"

# 호스트 접근용 인터페이스에 static IP 설정
sudo bash /vagrant/scripts/local/vm-network.sh configure-interface eth2 192.168.0.106 255.255.255.0 192.168.0.1 "8.8.8.8 8.8.4.4"
```

### Static IP 설정 확인

**VM 내부에서 확인:**
```bash
vagrant ssh kube-master
ip addr show eth1
ip addr show eth2
```

**재시작 후 IP 유지 확인:**
```bash
vagrant reload kube-master
# 재시작 후
vagrant ssh kube-master
ip addr show eth1  # IP가 유지되는지 확인
```

### Static IP 설정된 VM 목록

| 호스트 | VM 이름 | eth1 (K8s) | eth2 (Host) |
|--------|---------|------------|-------------|
| my-ubuntu | kube-master | 192.168.0.100 | 192.168.0.100 |
| my-ubuntu | kube-node-1 | 192.168.0.101 | 192.168.0.101 |
| my-ubuntu | kube-node-2 | 192.168.0.102 | 192.168.0.102 |
| my-mac | kube-master2 | 192.168.0.103 | 192.168.0.103 |
| my-mac | kube-node2-1 | 192.168.0.104 | 192.168.0.104 |
| my-mac | kube-node2-2 | 192.168.0.105 | 192.168.0.105 |
| my-mac2 | kube-master3 | 192.168.0.106 | 192.168.0.106 |
| my-mac2 | kube-node3-1 | 192.168.0.107 | 192.168.0.107 |

### Static IP 설정 원리

`vm-network.sh configure-interface` 명령은 VM 내부에서 netplan을 사용하여 Static IP를 설정합니다:

1. **netplan 설정 파일 생성**: `/etc/netplan/50-static-<interface>.yaml`
2. **DHCP 비활성화**: `dhcp4: false`
3. **Static IP 설정**: 지정된 IP 주소와 게이트웨이 설정
4. **DNS 서버 설정**: Google DNS (8.8.8.8, 8.8.4.4) 또는 지정된 DNS
5. **설정 적용**: `netplan apply`

이 방법은 VM 재시작 후에도 IP 주소가 유지되도록 보장합니다.

### 라우팅 구성

**기본 라우팅:**
```bash
# Default route: eth2를 통해 인터넷 접근
default via 192.168.0.1 dev eth2

# Kubernetes 네트워크: eth1을 통해 직접 통신
192.168.0.0/24 dev eth1 scope link
```

---

## MetalLB IP 풀 구성

### MetalLB 개요

MetalLB는 Bare Metal Kubernetes 환경에서 LoadBalancer 타입의 Service에 IP를 할당해주는 도구입니다.

### IP 풀 설정

**현재 설정 (192.168.0.x):**
- IP 풀: `192.168.0.210-192.168.0.250`
- 장점: MacBook과 같은 서브넷에서 직접 접근 가능

### MetalLB 설정 변경

**설정 파일 위치:**
- 로컬: `/Users/dhong/workspaces/tz-drillquiz/provisioning/metallb/layer2-config.yaml`
- 클러스터: `metallb-system` 네임스페이스의 `config` ConfigMap

**설정 내용:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.0.210-192.168.0.250
```

**적용 방법:**
```bash
# my-ubuntu의 kube-master VM에서
kubectl apply -f /vagrant/provisioning/metallb/layer2-config.yaml

# 또는 직접 적용
kubectl patch configmap config -n metallb-system --patch '{
  "data": {
    "config": "address-pools:\n- name: default\n  protocol: layer2\n  addresses:\n  - 192.168.0.210-192.168.0.250\n"
  }
}'
```

**설정 확인:**
```bash
kubectl get configmap config -n metallb-system -o yaml
```

### LoadBalancer 서비스 IP 할당

MetalLB가 IP 풀에서 자동으로 IP를 할당합니다:

```bash
# Ingress Controller 서비스 확인
kubectl get svc ingress-nginx-controller -n default

# 출력 예시:
# NAME                       TYPE           EXTERNAL-IP
# ingress-nginx-controller   LoadBalancer   192.168.0.210
```

---

## Ingress 접근 설정

### Ingress Controller IP

**현재 설정:**
- **서비스명**: `ingress-nginx-controller`
- **타입**: `LoadBalancer`
- **EXTERNAL-IP**: `192.168.0.210`
- **포트**: HTTP (80), HTTPS (443)

### Ingress 리소스 설정

**Jenkins Ingress 예시:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins-ingress
  namespace: jenkins
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: selfsigned-issuer
spec:
  rules:
  - host: jenkins.drillquiz.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jenkins
            port:
              number: 8080  # Jenkins 서비스 포트
  tls:
  - hosts:
    - jenkins.drillquiz.com
    secretName: jenkins-ingress-tls
```

**중요**: Ingress의 백엔드 포트는 실제 서비스 포트와 일치해야 합니다.
- Jenkins 서비스: `8080`
- Ingress 백엔드: `8080` (80이 아님)

### MacBook에서 접근 설정

#### 1. /etc/hosts 파일 설정

```bash
sudo vi /etc/hosts

# 다음 줄 추가/수정:
192.168.0.210   jenkins.drillquiz.com
192.168.0.210   minio.drillquiz.com
192.168.0.210   grafana.drillquiz.com
# 기타 필요한 도메인들...
```

**자동 업데이트:**
```bash
sudo sed -i.bak 's/192.168.0.200/192.168.0.210/g' /etc/hosts
```

#### 2. 접근 테스트

```bash
# HTTP 접근
curl http://jenkins.drillquiz.com

# HTTPS 접근
curl https://jenkins.drillquiz.com -k

# 브라우저에서 접근
# http://jenkins.drillquiz.com
```

### 접근 방법 비교

| 방법 | IP 주소 | 접근 가능 여부 | 설명 |
|------|---------|----------------|------|
| 직접 IP 접근 | 192.168.0.210 | ✅ 가능 | Host 헤더 필요 |
| 도메인 접근 | jenkins.drillquiz.com | ✅ 가능 | /etc/hosts 설정 필요 |
| kubectl port-forward | localhost:8080 | ✅ 가능 | SSH 터널 필요 |

---

## 문제 해결

### 문제 1: MacBook에서 Ingress 접근 불가

**증상:**
```bash
ping jenkins.drillquiz.com
# Request timeout

curl http://jenkins.drillquiz.com
# Timeout 또는 Connection refused
```

**원인:**
- MacBook (192.168.0.133)과 Ingress IP (192.168.0.200)가 다른 서브넷
- 네트워크 라우팅 불가

**해결:**
1. MetalLB IP 풀을 192.168.0.x로 변경
2. Ingress Controller가 192.168.0.210 IP 할당
3. /etc/hosts 파일 업데이트

### 문제 2: 503 Service Temporarily Unavailable

**증상:**
```bash
curl http://192.168.0.210 -H "Host: jenkins.drillquiz.com"
# < HTTP/1.1 503 Service Temporarily Unavailable
```

**원인:**
- Ingress의 백엔드 포트가 서비스 포트와 불일치
- 예: Ingress는 80, 서비스는 8080

**해결:**
```bash
# Ingress의 백엔드 포트를 서비스 포트와 일치시킴
kubectl patch ingress jenkins-ingress -n jenkins -p '{
  "spec": {
    "rules": [{
      "host": "jenkins.drillquiz.com",
      "http": {
        "paths": [{
          "path": "/",
          "pathType": "Prefix",
          "backend": {
            "service": {
              "name": "jenkins",
              "port": {"number": 8080}
            }
          }
        }]
      }
    }]
  }
}'
```

### 문제 3: VM 재시작 후 IP 변경

**증상:**
- VM 재시작 후 IP 주소가 변경됨
- Kubernetes 클러스터에서 노드 연결 실패

**원인:**
- DHCP로 IP 할당
- Static IP 설정이 적용되지 않음

**해결:**
1. Static IP 설정 스크립트 실행
2. netplan 설정 확인
3. 재시작 후 IP 유지 확인

**확인 방법:**
```bash
# VM 내부에서
cat /etc/netplan/50-static-eth1.yaml

# 재시작 후 확인
vagrant reload kube-master
vagrant ssh kube-master
ip addr show eth1  # IP가 유지되는지 확인
```

### 문제 4: my-mac2의 VM들이 클러스터에 조인되지 않음

**증상:**
- `kubectl get nodes`에서 `NotReady` 상태
- my-ubuntu의 kube-master(192.168.0.100)와 통신 불가
- containerd 설치 실패

**원인:**
- `private_network` 사용으로 인한 네트워크 세그먼트 불일치
- eth2 인터페이스 없음

**해결:**
1. Vagrantfile에서 `private_network` → `public_network`로 변경
2. `bridge: "en0: Wi-Fi (AirPort)"` 추가
3. 두 번째 네트워크 인터페이스 추가 (eth2)
4. VM 재시작: `vagrant reload kube-master3 kube-node3-1`
5. Static IP 설정 적용
6. kubespray로 Kubernetes 설치

### 문제 5: Calico 설정 불일치

**증상:**
kubespray 설치 중 오류:
```
"Your inventory doesn't match the current cluster configuration"
```

**원인:**
- 기존 클러스터: `ipipMode: CrossSubnet`, `vxlanMode: Never`
- kubespray 기본값과 불일치

**해결:**
`/vagrant/resource/kubespray/group_vars/k8s_cluster/k8s-net-calico.yml` 파일 생성:

```yaml
---
# Calico network plugin configuration
# Match existing cluster configuration
calico_ipip_mode: "CrossSubnet"
calico_vxlan_mode: "Never"
```

### 문제 6: Default Route 충돌

**증상:**
```
Error: Conflicting default route declarations for IPv4
```

**원인:**
- eth1과 eth2 모두 default route 설정 시도

**해결:**
- eth2만 default route 사용 (인터넷 접근)
- eth1은 Kubernetes 네트워크용으로만 사용 (default route 없음)

**권장 설정:**
- eth1: Kubernetes 네트워크용 (default route 없음)
- eth2: default route 포함 (인터넷 접근)

### 문제 7: Kubernetes API 접근 불가

**증상:**
```bash
kubectl get nodes
# Error: connection refused
```

**원인:**
- kubeconfig의 server IP가 접근 불가능한 주소

**해결:**
```bash
# kubeconfig 수정
vi ~/.kube/config

# server 주소를 호스트 접근용 IP로 변경
server: https://192.168.0.100:6443  # eth2 IP 사용
insecure-skip-tls-verify: true  # TLS 인증서 문제 해결
```

---

## 검증 방법

### 1. 네트워크 연결 확인

```bash
# my-mac2의 VM에서 실행
vagrant ssh kube-master3
ping -c 2 192.168.0.100  # my-ubuntu의 kube-master
ping -c 2 8.8.8.8         # 인터넷 연결
```

### 2. 노드 상태 확인

```bash
# my-ubuntu에서 실행
kubectl get nodes -o wide | grep -E 'kube-master3|kube-node3-1'
# 결과: Ready 상태여야 함
```

### 3. 시스템 Pod 확인

```bash
kubectl get pods -n kube-system -o wide | grep -E 'kube-master3|kube-node3-1'
# Calico, kube-proxy, nodelocaldns 등이 Running 상태여야 함
```

### 4. 네트워크 인터페이스 확인

```bash
vagrant ssh <vm-name>
ip addr show eth1
ip addr show eth2
ip route show
```

### 5. MetalLB 및 Ingress 확인

```bash
# Ingress Controller 서비스 확인
kubectl get svc ingress-nginx-controller -n default

# MetalLB 설정 확인
kubectl get configmap config -n metallb-system -o yaml

# Ingress 리소스 확인
kubectl get ingress -A
```

---

## 네트워크 설정 체크리스트

### 초기 설정

- [ ] Vagrantfile에서 `public_network` 사용 확인
- [ ] `bridge: "en0: Wi-Fi (AirPort)"` 설정 확인 (macOS)
- [ ] `bridge: "eno1"` 설정 확인 (my-ubuntu)
- [ ] eth1 (192.168.0.x)와 eth2 (192.168.0.x) 인터페이스 존재 확인
- [ ] Static IP 설정 스크립트 실행
- [ ] 재시작 후 IP 유지 확인
- [ ] MetalLB IP 풀 설정 (192.168.0.210-250)
- [ ] Ingress Controller IP 확인 (192.168.0.210)
- [ ] Ingress 리소스 ADDRESS 업데이트 확인
- [ ] /etc/hosts 파일 업데이트
- [ ] Calico 설정 파일(`k8s-net-calico.yml`) 생성 확인 (새 노드 추가 시)

### 정기 점검

- [ ] VM IP 주소 확인
- [ ] Kubernetes 노드 상태 확인
- [ ] Ingress Controller 서비스 확인
- [ ] MetalLB 설정 확인
- [ ] 네트워크 연결 테스트

### 명령어 참고

```bash
# VM IP 확인
vagrant ssh <vm-name> -- ip addr show

# Kubernetes 노드 확인
kubectl get nodes -o wide

# Ingress Controller 확인
kubectl get svc ingress-nginx-controller -n default

# MetalLB 설정 확인
kubectl get configmap config -n metallb-system -o yaml

# Ingress 리소스 확인
kubectl get ingress -A

# 네트워크 연결 테스트
ping <ip-address>
curl http://<ip-address> -H "Host: <domain>"
```

---

## 참고 자료

### 스크립트 위치
- 통합 네트워크 관리 스크립트: `scripts/local/vm-network.sh`
  - `configure-interface`: VM 내부에서 인터페이스 설정
  - `apply-static-ip`: 호스트에서 모든 VM에 Static IP 설정
  - `fix-mac2-network`: my-mac2 네트워크 수정
  - `restore-mac2-node`: my-mac2 노드 복구

### MetalLB 설정
- 설정 파일: `provisioning/metallb/layer2-config.yaml`
- 네임스페이스: `metallb-system`
- ConfigMap: `config`

### kubespray 설정
- 인벤토리 파일: `/vagrant/resource/kubespray/inventory_add.ini`
- Calico 설정: `/vagrant/resource/kubespray/group_vars/k8s_cluster/k8s-net-calico.yml`

### 관련 파일
- Vagrantfile: 각 호스트의 `~/workspaces/tz-k8s-vagrant/Vagrantfile`

---

## 요약

- **Vagrantfile**: `public_network`로 물리 네트워크 브리지
- **Static IP**: VM 재시작 후에도 IP 유지
- **MetalLB**: LoadBalancer에 192.168.0.210-250
- **Ingress**: 192.168.0.210
- **Calico**: `k8s-net-calico.yml`로 기존 클러스터와 일치
