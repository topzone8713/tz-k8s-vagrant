#!/bin/bash

################################################################################
# Vagrant VM 백업 스크립트
#
# 호스트(mac / Linux / Windows Git Bash)에서 실행합니다.
# 스냅샷 대신 VM 전체를 복사하는 방식을 사용하여 더 안정적입니다.
#
# 사용법:
#   ./scripts/backup-vms.sh              # 기본 백업 (타임스탬프 포함)
#   ./scripts/backup-vms.sh restore      # 백업 목록 보기
#   ./scripts/backup-vms.sh restore <name> # 특정 백업 복원
#   ./scripts/backup-vms.sh list         # 백업 목록 보기
#   ./scripts/backup-vms.sh clean <days> # 오래된 백업 삭제 (기본 30일)
################################################################################

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAGRANT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_BASE_DIR="${HOME}/vagrant-backups"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_NAME="vagrant-vms-${TIMESTAMP}"
BACKUP_DIR="${BACKUP_BASE_DIR}/${BACKUP_NAME}"
MAX_BACKUP_COUNT="${MAX_BACKUP_COUNT:-10}"  # 최대 백업 개수

# 플랫폼 감지 (mac, linux, windows)
detect_platform() {
    case "${OSTYPE:-}" in
        darwin*)  echo "mac" ;;
        linux-gnu*) echo "linux" ;;
        msys|cygwin|msys2) echo "windows" ;;
        *) echo "linux" ;;
    esac
}
PLATFORM=$(detect_platform)

# VirtualBox PATH: macOS / Windows / Linux
if [ "${PLATFORM}" = "mac" ]; then
    export PATH="/Applications/VirtualBox.app/Contents/MacOS:${PATH}"
elif [ "${PLATFORM}" = "windows" ]; then
    for vbox in "/c/Program Files/Oracle/VirtualBox" "/c/Program Files (x86)/Oracle/VirtualBox"; do
        [ -d "${vbox}" ] && export PATH="${vbox}:${PATH}" && break
    done
fi

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# VirtualBox 확인
check_virtualbox() {
    if ! command -v VBoxManage &> /dev/null; then
        log_error "VBoxManage를 찾을 수 없습니다. VirtualBox가 설치되어 있는지 확인하세요."
        exit 1
    fi
}

# Vagrant 확인
check_vagrant() {
    VAGRANT_CMD=""
    if [ "${PLATFORM}" = "windows" ]; then
        # Windows: which만 사용 (경로에 공백 가능), -x 검사 생략
        VAGRANT_CMD=$(which vagrant 2>/dev/null) || true
        [ -z "${VAGRANT_CMD}" ] && VAGRANT_CMD="/c/Program Files (x86)/Vagrant/bin/vagrant"
        [ ! -f "${VAGRANT_CMD}" ] && VAGRANT_CMD="/c/Program Files/Vagrant/bin/vagrant"
    else
        for path in "/usr/local/bin/vagrant" "/opt/homebrew/bin/vagrant" "$(which vagrant 2>/dev/null)"; do
            [ -z "${path}" ] && continue
            if [ -x "${path}" ] 2>/dev/null || [ -f "${path}" ]; then
                VAGRANT_CMD="${path}"
                break
            fi
        done
    fi
    
    if [ -z "${VAGRANT_CMD}" ] || [ ! -f "${VAGRANT_CMD}" ]; then
        log_error "vagrant 명령어를 찾을 수 없습니다."
        log_info "다음 경로에서 vagrant를 찾아보세요:"
        log_info "  - /usr/local/bin/vagrant (mac/linux)"
        log_info "  - /opt/homebrew/bin/vagrant (mac)"
        log_info "  - C:\\Program Files (x86)\\Vagrant\\bin\\vagrant (windows)"
        exit 1
    fi
    
    export VAGRANT_CMD
    log_info "Vagrant 경로: ${VAGRANT_CMD}"
}

# 백업 디렉토리 생성
create_backup_dir() {
    mkdir -p "${BACKUP_DIR}"
    log_info "백업 디렉토리 생성: ${BACKUP_DIR}"
}

# Vagrantfile 및 설정 파일 백업
backup_config_files() {
    log_info "설정 파일 백업 중..."
    
    cd "${VAGRANT_DIR}"
    
    # 백업할 파일/디렉토리 목록
    BACKUP_ITEMS=(
        "Vagrantfile"
        ".vagrant"
        "scripts"
        "resource"
        ".ssh"
    )
    
    for item in "${BACKUP_ITEMS[@]}"; do
        if [ -e "${item}" ]; then
            log_info "  - ${item} 백업 중..."
            cp -R "${item}" "${BACKUP_DIR}/" 2>/dev/null || log_warning "  ${item} 백업 실패 (무시)"
        fi
    done
    
    log_success "설정 파일 백업 완료"
}

# VirtualBox VM 백업 (VMDK 파일 포함)
backup_virtualbox_vms() {
    log_info "VirtualBox VM 백업 중..."
    
    cd "${VAGRANT_DIR}"
    
    # Vagrant로 관리되는 VM 목록 가져오기 (Windows: CRLF 제거, 경로 공백 대비 따옴표)
    VM_NAMES=$("${VAGRANT_CMD}" status --machine-readable 2>&1 | tr -d '\r' | grep ",state," | cut -d',' -f2 | sort -u || true)
    
    if [ -z "${VM_NAMES}" ]; then
        log_warning "Vagrant VM을 찾을 수 없습니다."
        return
    fi
    
    VM_COUNT=0
    for vm_name in ${VM_NAMES}; do
        # VirtualBox UUID 찾기
        VM_UUID=$(VBoxManage list vms | grep "${vm_name}" | awk -F'[{}]' '{print $2}' || true)
        
        if [ -z "${VM_UUID}" ]; then
            log_warning "  ${vm_name}: VirtualBox VM을 찾을 수 없습니다 (건너뜀)"
            continue
        fi
        
        log_info "  ${vm_name} (${VM_UUID}) 백업 중..."
        
        # VM 정보 저장
        VBoxManage showvminfo "${VM_UUID}" > "${BACKUP_DIR}/${vm_name}-vminfo.txt" 2>/dev/null || true
        
        # VM 설정 파일 (.vbox) 찾기
        VM_CONFIG_FILE=$(VBoxManage showvminfo "${VM_UUID}" --machinereadable 2>/dev/null | grep "^CfgFile=" | cut -d'"' -f2 || true)
        
        if [ -z "${VM_CONFIG_FILE}" ]; then
            # 대체 방법: VM 이름으로 디렉토리 찾기
            VM_BASE_DIR="${HOME}/VirtualBox VMs"
            VM_CONFIG_FILE=$(find "${VM_BASE_DIR}" -name "*.vbox" -exec grep -l "${VM_UUID}" {} \; 2>/dev/null | head -1 || true)
        fi
        
        if [ -n "${VM_CONFIG_FILE}" ] && [ -f "${VM_CONFIG_FILE}" ]; then
            VM_DIR=$(dirname "${VM_CONFIG_FILE}")
            VM_BASE_NAME=$(basename "${VM_CONFIG_FILE}" .vbox)
            
            # VM 디렉토리 전체 복사
            log_info "    VM 디렉토리 복사: ${VM_DIR}"
            mkdir -p "${BACKUP_DIR}/vms/${vm_name}"
            cp -R "${VM_DIR}"/* "${BACKUP_DIR}/vms/${vm_name}/" 2>/dev/null || log_warning "    일부 파일 복사 실패"
            
            # VM 경로 정보 저장
            echo "${VM_DIR}" > "${BACKUP_DIR}/vms/${vm_name}/original-path.txt"
            echo "${VM_UUID}" > "${BACKUP_DIR}/vms/${vm_name}/uuid.txt"
            
            VM_COUNT=$((VM_COUNT + 1))
            log_success "    ${vm_name} 백업 완료"
        else
            log_warning "    ${vm_name}: VM 설정 파일을 찾을 수 없습니다 (UUID: ${VM_UUID})"
            # UUID만 저장
            mkdir -p "${BACKUP_DIR}/vms/${vm_name}"
            echo "${VM_UUID}" > "${BACKUP_DIR}/vms/${vm_name}/uuid.txt"
            log_info "    UUID만 저장됨 (수동 복원 필요)"
        fi
    done
    
    if [ ${VM_COUNT} -eq 0 ]; then
        log_warning "백업된 VM이 없습니다."
    else
        log_success "${VM_COUNT}개 VM 백업 완료"
    fi
}

# 백업 메타데이터 생성
create_backup_metadata() {
    log_info "백업 메타데이터 생성 중..."
    
    cat > "${BACKUP_DIR}/backup-info.txt" <<EOF
백업 정보
==========
백업 시간: $(date)
백업 이름: ${BACKUP_NAME}
백업 디렉토리: ${BACKUP_DIR}
호스트: $(hostname)
사용자: $(whoami)
Vagrant 버전: $("${VAGRANT_CMD}" --version 2>/dev/null || echo "N/A")
VirtualBox 버전: $(VBoxManage --version 2>/dev/null || echo "N/A")

VM 목록:
$("${VAGRANT_CMD}" status 2>/dev/null | grep -E "(kube-master2|kube-node2)" || echo "N/A")

백업 방법:
- Vagrantfile 및 설정 파일: 직접 복사
- VirtualBox VM: VMDK 파일 및 설정 파일 전체 복사
- 스냅샷 사용 안 함 (더 안정적)

복원 방법:
1. 백업 디렉토리에서 Vagrantfile 및 설정 파일 복원
2. VirtualBox에서 VM 등록 (VBoxManage registervm)
3. vagrant reload
EOF
    
    log_success "백업 메타데이터 생성 완료"
}

# 백업 실행
do_backup() {
    log_info "=========================================="
    log_info "Vagrant VM 백업 시작"
    log_info "=========================================="
    
    check_virtualbox
    check_vagrant
    create_backup_dir
    backup_config_files
    backup_virtualbox_vms
    create_backup_metadata
    
    # 백업 크기 계산
    BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
    
    log_info "=========================================="
    log_success "백업 완료!"
    log_info "백업 위치: ${BACKUP_DIR}"
    log_info "백업 크기: ${BACKUP_SIZE}"
    log_info "=========================================="
    
    # 최신 백업 참조 (Windows: symlink 대신 파일에 경로 저장)
    LATEST_LINK="${BACKUP_BASE_DIR}/latest"
    if [ "${PLATFORM}" = "windows" ]; then
        echo "${BACKUP_DIR}" > "${BACKUP_BASE_DIR}/latest.txt"
        log_info "최신 백업 경로 저장: ${BACKUP_BASE_DIR}/latest.txt"
    else
        rm -f "${LATEST_LINK}"
        ln -s "${BACKUP_DIR}" "${LATEST_LINK}"
        log_info "최신 백업 링크: ${LATEST_LINK}"
    fi
    
    # 백업 개수 제한 (최대 개수 유지)
    limit_backup_count "${MAX_BACKUP_COUNT}"
}

# 백업 목록 보기
list_backups() {
    log_info "백업 목록:"
    echo ""
    
    if [ ! -d "${BACKUP_BASE_DIR}" ]; then
        log_warning "백업 디렉토리가 없습니다: ${BACKUP_BASE_DIR}"
        return
    fi
    
    BACKUP_COUNT=0
    for backup_dir in "${BACKUP_BASE_DIR}"/vagrant-vms-*; do
        if [ -d "${backup_dir}" ]; then
            BACKUP_COUNT=$((BACKUP_COUNT + 1))
            BACKUP_NAME=$(basename "${backup_dir}")
            BACKUP_DATE=$(echo "${BACKUP_NAME}" | sed 's/vagrant-vms-//')
            BACKUP_SIZE=$(du -sh "${backup_dir}" 2>/dev/null | cut -f1)
            
            # 최신 백업 표시
            IS_LATEST=0
            if [ "${PLATFORM}" = "windows" ] && [ -f "${BACKUP_BASE_DIR}/latest.txt" ]; then
                LATEST_PATH=$(cat "${BACKUP_BASE_DIR}/latest.txt" 2>/dev/null | tr -d '\r\n')
                [ "${LATEST_PATH}" = "${backup_dir}" ] && IS_LATEST=1
            elif [ -L "${BACKUP_BASE_DIR}/latest" ] && [ "$(readlink "${BACKUP_BASE_DIR}/latest")" = "${backup_dir}" ]; then
                IS_LATEST=1
            fi
            if [ ${IS_LATEST} -eq 1 ]; then
                echo -e "  ${GREEN}*${NC} ${BACKUP_NAME} (${BACKUP_SIZE}) [최신]"
            else
                echo "    ${BACKUP_NAME} (${BACKUP_SIZE})"
            fi
        fi
    done
    
    if [ ${BACKUP_COUNT} -eq 0 ]; then
        log_warning "백업이 없습니다."
    else
        echo ""
        log_info "총 ${BACKUP_COUNT}개 백업"
    fi
}

# 백업 복원
restore_backup() {
    local restore_name="$1"
    
    if [ -z "${restore_name}" ]; then
        log_error "복원할 백업 이름을 지정하세요."
        list_backups
        exit 1
    fi
    
    # 백업 경로 찾기
    if [ "${restore_name}" = "latest" ]; then
        if [ "${PLATFORM}" = "windows" ] && [ -f "${BACKUP_BASE_DIR}/latest.txt" ]; then
            RESTORE_DIR=$(cat "${BACKUP_BASE_DIR}/latest.txt" 2>/dev/null | tr -d '\r\n')
        else
            RESTORE_DIR="${BACKUP_BASE_DIR}/latest"
            if [ ! -L "${RESTORE_DIR}" ]; then
                log_error "최신 백업 링크를 찾을 수 없습니다."
                exit 1
            fi
            RESTORE_DIR=$(readlink "${RESTORE_DIR}")
        fi
        [ -z "${RESTORE_DIR}" ] && { log_error "최신 백업 경로를 읽을 수 없습니다."; exit 1; }
    else
        RESTORE_DIR="${BACKUP_BASE_DIR}/${restore_name}"
    fi
    
    if [ ! -d "${RESTORE_DIR}" ]; then
        log_error "백업을 찾을 수 없습니다: ${RESTORE_DIR}"
        list_backups
        exit 1
    fi
    
    log_warning "=========================================="
    log_warning "백업 복원 시작"
    log_warning "백업: ${RESTORE_DIR}"
    log_warning "=========================================="
    log_warning "주의: 이 작업은 현재 VM을 덮어씁니다!"
    echo ""
    read -p "계속하시겠습니까? (yes/no): " confirm
    
    if [ "${confirm}" != "yes" ]; then
        log_info "복원 취소됨"
        exit 0
    fi
    
    log_info "VM 종료 중..."
    cd "${VAGRANT_DIR}"
    "${VAGRANT_CMD}" halt 2>/dev/null || true
    
    log_info "설정 파일 복원 중..."
    # Vagrantfile 복원
    if [ -f "${RESTORE_DIR}/Vagrantfile" ]; then
        cp "${RESTORE_DIR}/Vagrantfile" "${VAGRANT_DIR}/"
        log_success "Vagrantfile 복원 완료"
    fi
    
    # .vagrant 디렉토리 복원
    if [ -d "${RESTORE_DIR}/.vagrant" ]; then
        rm -rf "${VAGRANT_DIR}/.vagrant"
        cp -R "${RESTORE_DIR}/.vagrant" "${VAGRANT_DIR}/"
        log_success ".vagrant 디렉토리 복원 완료"
    fi
    
    # VirtualBox VM 복원 (자동)
    if [ -d "${RESTORE_DIR}/vms" ]; then
        log_info "VirtualBox VM 복원 중..."
        
        # 기존 VM 제거 (있는 경우)
        for vm_dir in "${RESTORE_DIR}/vms"/*; do
            if [ -d "${vm_dir}" ]; then
                VM_NAME=$(basename "${vm_dir}")
                log_info "  ${VM_NAME} 복원 중..."
                
                # .vbox 파일 찾기
                VBOX_FILE=$(find "${vm_dir}" -name "*.vbox" -type f | head -1)
                if [ -n "${VBOX_FILE}" ] && [ -f "${VBOX_FILE}" ]; then
                    # UUID 확인 (macOS 호환)
                    VM_UUID=$(grep -o 'uuid="[^"]*"' "${VBOX_FILE}" | head -1 | sed 's/uuid="\([^"]*\)"/\1/' || echo "")
                    
                    if [ -n "${VM_UUID}" ]; then
                        # 기존 VM 제거 (있는 경우)
                        VBoxManage unregistervm "${VM_UUID}" --delete 2>/dev/null || true
                        
                        # 원본 경로 확인
                        ORIGINAL_PATH=""
                        if [ -f "${vm_dir}/original-path.txt" ]; then
                            ORIGINAL_PATH=$(cat "${vm_dir}/original-path.txt" | tr -d '\n\r')
                        fi
                        
                        # 원본 경로가 있으면 그곳으로 복원, 없으면 백업 위치에서 등록
                        if [ -n "${ORIGINAL_PATH}" ] && [ -d "${ORIGINAL_PATH}" ]; then
                            log_info "    원본 경로로 복원: ${ORIGINAL_PATH}"
                            # VM 파일 복사
                            cp -R "${vm_dir}"/* "${ORIGINAL_PATH}/" 2>/dev/null || true
                            # VM 등록
                            VBoxManage registervm "${ORIGINAL_PATH}/$(basename "${VBOX_FILE}")" 2>/dev/null && \
                                log_success "    ${VM_NAME} 복원 완료" || \
                                log_warning "    ${VM_NAME} 등록 실패 (수동 등록 필요)"
                        else
                            log_info "    백업 위치에서 등록: ${vm_dir}"
                            # VM 등록
                            VBoxManage registervm "${VBOX_FILE}" 2>/dev/null && \
                                log_success "    ${VM_NAME} 복원 완료" || \
                                log_warning "    ${VM_NAME} 등록 실패 (수동 등록 필요)"
                        fi
                    else
                        log_warning "    ${VM_NAME}: UUID를 찾을 수 없음"
                    fi
                else
                    log_warning "    ${VM_NAME}: .vbox 파일을 찾을 수 없음"
                fi
            fi
        done
    else
        log_warning "VM 백업 디렉토리가 없습니다: ${RESTORE_DIR}/vms"
        log_info "VirtualBox VM 복원은 수동으로 수행해야 합니다:"
        log_info "1. VirtualBox GUI에서 VM 가져오기"
        log_info "2. 또는 VBoxManage registervm 명령 사용"
    fi
    
    log_success "복원 완료"
}

# 백업 개수 제한 (최대 개수 유지)
limit_backup_count() {
    local max_count="${1:-${MAX_BACKUP_COUNT}}"
    
    log_info "백업 개수 제한 확인 중 (최대 ${max_count}개)..."
    
    if [ ! -d "${BACKUP_BASE_DIR}" ]; then
        log_warning "백업 디렉토리가 없습니다."
        return
    fi
    
    # 백업 디렉토리 목록 가져오기 (최신 순으로 정렬)
    BACKUP_LIST=()
    if [ "$(uname)" = "Darwin" ] || [ "${PLATFORM}" = "windows" ]; then
        # macOS / Windows: ls -td (시간순 정렬)
        while IFS= read -r backup_dir; do
            if [ -d "${backup_dir}" ] && [ ! -L "${backup_dir}" ]; then
                BACKUP_LIST+=("${backup_dir}")
            fi
        done < <(ls -td "${BACKUP_BASE_DIR}"/vagrant-vms-* 2>/dev/null || true)
    else
        # Linux: find -printf
        while IFS= read -r backup_dir; do
            if [ -d "${backup_dir}" ] && [ ! -L "${backup_dir}" ]; then
                BACKUP_LIST+=("${backup_dir}")
            fi
        done < <(find "${BACKUP_BASE_DIR}" -maxdepth 1 -type d -name "vagrant-vms-*" -printf "%T@ %p\n" 2>/dev/null | sort -rn | cut -d' ' -f2- || true)
    fi
    
    BACKUP_TOTAL=${#BACKUP_LIST[@]}
    
    if [ ${BACKUP_TOTAL} -le ${max_count} ]; then
        log_info "백업 개수: ${BACKUP_TOTAL}/${max_count} (제한 내)"
        return
    fi
    
    log_info "백업 개수: ${BACKUP_TOTAL}/${max_count} (제한 초과, 오래된 백업 삭제 중...)"
    
    # 최신 백업 경로 확인 (Windows: latest.txt / 그 외: symlink)
    LATEST_LINK=""
    if [ "${PLATFORM}" = "windows" ] && [ -f "${BACKUP_BASE_DIR}/latest.txt" ]; then
        LATEST_LINK=$(cat "${BACKUP_BASE_DIR}/latest.txt" 2>/dev/null | tr -d '\r\n')
    elif [ -L "${BACKUP_BASE_DIR}/latest" ]; then
        LATEST_LINK=$(readlink "${BACKUP_BASE_DIR}/latest")
    fi
    
    DELETED_COUNT=0
    KEPT_COUNT=0
    
    # 최신 순으로 정렬된 목록에서 오래된 것부터 삭제
    for backup_dir in "${BACKUP_LIST[@]}"; do
        # 최신 링크는 보호
        if [ -n "${LATEST_LINK}" ] && [ "${backup_dir}" = "${LATEST_LINK}" ]; then
            KEPT_COUNT=$((KEPT_COUNT + 1))
            continue
        fi
        
        # 최대 개수 이하로 유지
        if [ ${KEPT_COUNT} -lt ${max_count} ]; then
            KEPT_COUNT=$((KEPT_COUNT + 1))
        else
            # 초과된 백업 삭제
            BACKUP_NAME=$(basename "${backup_dir}")
            BACKUP_SIZE=$(du -sh "${backup_dir}" 2>/dev/null | cut -f1 || echo "unknown")
            log_info "  삭제: ${BACKUP_NAME} (${BACKUP_SIZE})"
            rm -rf "${backup_dir}"
            DELETED_COUNT=$((DELETED_COUNT + 1))
        fi
    done
    
    if [ ${DELETED_COUNT} -eq 0 ]; then
        log_info "삭제할 백업이 없습니다."
    else
        log_success "${DELETED_COUNT}개 백업 삭제 완료 (현재: ${KEPT_COUNT}개)"
    fi
}

# 오래된 백업 삭제
clean_old_backups() {
    local days="${1:-30}"
    
    log_info "${days}일 이상 된 백업 삭제 중..."
    
    if [ ! -d "${BACKUP_BASE_DIR}" ]; then
        log_warning "백업 디렉토리가 없습니다."
        return
    fi
    
    # 최신 백업 경로 (삭제 제외용)
    LATEST_PATH=""
    if [ "${PLATFORM}" = "windows" ] && [ -f "${BACKUP_BASE_DIR}/latest.txt" ]; then
        LATEST_PATH=$(cat "${BACKUP_BASE_DIR}/latest.txt" 2>/dev/null | tr -d '\r\n')
    elif [ -L "${BACKUP_BASE_DIR}/latest" ]; then
        LATEST_PATH=$(readlink "${BACKUP_BASE_DIR}/latest")
    fi

    DELETED_COUNT=0
    for backup_dir in "${BACKUP_BASE_DIR}"/vagrant-vms-*; do
        if [ -d "${backup_dir}" ] && [ ! -L "${backup_dir}" ]; then
            if [ -n "${LATEST_PATH}" ] && [ "${backup_dir}" = "${LATEST_PATH}" ]; then
                continue
            fi
            # 디렉터리 mtime으로 오래된 것만 삭제 (stat: GNU -c %Y / BSD -f %m)
            DIR_MTIME=$(stat -c %Y "${backup_dir}" 2>/dev/null || stat -f %m "${backup_dir}" 2>/dev/null || echo 0)
            NOW=$(date +%s)
            if [ "${DIR_MTIME}" != "0" ] && [ "$(( NOW - DIR_MTIME ))" -gt $((days * 86400)) ]; then
                log_info "  삭제: $(basename "${backup_dir}")"
                rm -rf "${backup_dir}"
                DELETED_COUNT=$((DELETED_COUNT + 1))
            fi
        fi
    done
    
    if [ ${DELETED_COUNT} -eq 0 ]; then
        log_info "삭제할 백업이 없습니다."
    else
        log_success "${DELETED_COUNT}개 백업 삭제 완료"
    fi
}

# 메인
main() {
    case "${1:-backup}" in
        backup)
            do_backup
            ;;
        list)
            list_backups
            ;;
        restore)
            restore_backup "${2:-}"
            ;;
        clean)
            clean_old_backups "${2:-30}"
            ;;
        limit)
            limit_backup_count "${2:-${MAX_BACKUP_COUNT}}"
            ;;
        *)
            echo "사용법: $0 [backup|list|restore <name>|clean <days>|limit <count>]"
            echo ""
            echo "명령어:"
            echo "  backup          - VM 백업 (기본, 최대 ${MAX_BACKUP_COUNT}개 유지)"
            echo "  list            - 백업 목록 보기"
            echo "  restore <name>  - 백업 복원 (latest 또는 백업 이름)"
            echo "  clean <days>    - 오래된 백업 삭제 (기본 30일)"
            echo "  limit <count>   - 백업 개수 제한 (기본 ${MAX_BACKUP_COUNT}개)"
            echo ""
            echo "환경 변수:"
            echo "  MAX_BACKUP_COUNT - 최대 백업 개수 (기본: ${MAX_BACKUP_COUNT})"
            exit 1
            ;;
    esac
}

main "$@"
