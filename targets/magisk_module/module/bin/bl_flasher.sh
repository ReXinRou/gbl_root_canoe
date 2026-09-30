#!/system/bin/sh
if [ -z "$MODDIR" ]; then
  MODDIR=$(CDPATH= cd -- "$(dirname "$0")/.." 2>/dev/null && pwd)
fi
if [ -z "$MODDIR" ]; then
  echo 'ERROR=MODDIR detection failed' >&2
  exit 1
fi

LANG=zh
if [ -f "$MODDIR/lang.txt" ]; then
  USER_LANG=$(cat "$MODDIR/lang.txt" | tr -d '[:space:]')
  if [ "$USER_LANG" = "en" ]; then
    LANG=en
  fi
fi

if [ "$LANG" = "zh" ]; then
  TEXT_IDLE="等待操作"
  TEXT_NO_SLOT="无法识别当前槽位"
  TEXT_NO_TARGET_SLOT="无法计算目标槽位"
  TEXT_FLASHING="正在将镜像刷写到槽位"
  TEXT_DEBUG_MODE="调试模式：仅处理不刷写，efisp 目录使用模块 tmp/efisp"
  TEXT_DEBUG_DONE="调试完成，文件保存在"
  TEXT_DEBUG_FAILED="调试过程中出错"
  TEXT_EXTRACT_FAILED="ABL 提取失败"
  TEXT_PATCH_FAILED="补丁应用失败"
  TEXT_PERSIST_NOT_MOUNTED="persist 分区未挂载到 /mnt/vendor/persist"
  TEXT_EFISP_MKDIR_FAILED="创建 efisp 启动目录失败"
  TEXT_EFISP_WRITE_FAILED="写入 efisp 启动文件失败"
  TEXT_BACKUP_BOOT="已备份旧的 boot.efi"
  TEXT_EFISP_FILES_OK="efisp 启动项已更新"
  TEXT_GBL_DETECT_FAILED="漏洞检测失败，继续流程"
  TEXT_NO_GBL_VULN="未检测到GBL漏洞"
  TEXT_EFISP_WARN="efisp 刷写失败，继续刷入BL"
  TEXT_SET_RW_FAILED="分区设置可写失败"
  TEXT_FLASH_PART="刷写"
  TEXT_FLASH_OK="完成"
  TEXT_ALL_OK="全部完成（含efisp）"
  TEXT_ALL_OK_NO_EFISP="全部完成（不含efisp）"
  TEXT_BUSY="任务正在运行"
  TEXT_LOG_CLEARED="日志已清空"
else
  TEXT_IDLE="Waiting"
  TEXT_NO_SLOT="Cannot detect current slot"
  TEXT_NO_TARGET_SLOT="Cannot detect target slot"
  TEXT_FLASHING="Flashing to slot"
  TEXT_DEBUG_MODE="Debug Mode: process only, no flash; efisp dir uses module tmp/efisp"
  TEXT_DEBUG_DONE="Debug done"
  TEXT_DEBUG_FAILED="Debug error"
  TEXT_EXTRACT_FAILED="ABL extract failed"
  TEXT_PATCH_FAILED="Patch failed"
  TEXT_PERSIST_NOT_MOUNTED="persist is not mounted at /mnt/vendor/persist"
  TEXT_EFISP_MKDIR_FAILED="efisp boot dir create failed"
  TEXT_EFISP_WRITE_FAILED="efisp boot file write failed"
  TEXT_BACKUP_BOOT="Backed up old boot.efi"
  TEXT_EFISP_FILES_OK="efisp boot entries updated"
  TEXT_GBL_DETECT_FAILED="Vuln check failed"
  TEXT_NO_GBL_VULN="No GBL vuln found"
  TEXT_EFISP_WARN="efisp failed, continue BL"
  TEXT_SET_RW_FAILED="setrw failed"
  TEXT_FLASH_PART="Flashing"
  TEXT_FLASH_OK="done"
  TEXT_ALL_OK="All done (with efisp)"
  TEXT_ALL_OK_NO_EFISP="All done (no efisp)"
  TEXT_BUSY="Task running"
  TEXT_LOG_CLEARED="Log cleared"
fi

RUNTIME_DIR="$MODDIR/tmp"
BY_NAME_DIR="/dev/block/by-name"
PERSIST_MNT="/mnt/vendor/persist"
EFISP_DIR="$PERSIST_MNT/efisp"
IMAGE_NAMES="abl"
LOG_FILE="$RUNTIME_DIR/flash.log"
STATE_FILE="$RUNTIME_DIR/state"
MESSAGE_FILE="$RUNTIME_DIR/message"
UPDATED_FILE="$RUNTIME_DIR/updated"
PID_FILE="$RUNTIME_DIR/flash.pid"
LOCK_DIR="$RUNTIME_DIR/flash.lock"
export PATH=/data/adb/ksu/bin:/system/bin:/system/xbin:$PATH

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
read_line() { [ -f "$1" ] && head -n1 "$1"; }
emit() { echo -n "$1" | tr '\n' '\t'; }

ensure_runtime() {
  mkdir -p "$RUNTIME_DIR"
  [ -f "$LOG_FILE" ] || : > "$LOG_FILE"
  [ -f "$STATE_FILE" ] || echo idle > "$STATE_FILE"
  [ -f "$MESSAGE_FILE" ] || echo "$TEXT_IDLE" > "$MESSAGE_FILE"
  [ -f "$UPDATED_FILE" ] || timestamp > "$UPDATED_FILE"
}

write_state() {
  ensure_runtime
  echo "$1" > "$STATE_FILE"
  echo "$2" > "$MESSAGE_FILE"
  timestamp > "$UPDATED_FILE"
}

write_log() {
  ensure_runtime
  echo "[$(timestamp)] $*" >> "$LOG_FILE"
}

detect_current_slot() {
  case "$(getprop ro.boot.slot_suffix 2>/dev/null)" in
    _a) echo _a ;;
    _b) echo _b ;;
    *) return 1 ;;
  esac
}

other_slot() {
  case "$1" in
    _a) echo _b ;;
    _b) echo _a ;;
    *) return 1 ;;
  esac
}

partition_path() { echo "$BY_NAME_DIR/$1$2"; }

current_pid() {
  [ -f "$PID_FILE" ] || return 1
  pid=$(cat "$PID_FILE" | tr -d '[:space:]')
  kill -0 "$pid" 2>/dev/null && echo "$pid" && return 0
  rm -f "$PID_FILE"
  return 1
}

# The module only stages patched boot.efi under persist; it does not install
# a boot menu or tools submenu.
persist_mounted() { grep -q " $PERSIST_MNT " /proc/mounts; }

# Extract and crack the target-slot ABL and stage boot.efi under persist.
# In debug mode the staged file is written under $RUNTIME_DIR/efisp instead.
update_efisp() {
  abl=$1
  is_debug=$2
  rm -f $RUNTIME_DIR/*
  $MODDIR/bin/extractfv -o $RUNTIME_DIR -v "$abl" >> "$LOG_FILE" 2>&1
  $MODDIR/bin/patch_abl $RUNTIME_DIR/LinuxLoader.efi $RUNTIME_DIR/patched.efi >> $RUNTIME_DIR/patch.log 2>&1
  cat $RUNTIME_DIR/patch.log >> "$LOG_FILE"
  [ -f $RUNTIME_DIR/patched.efi ] || { write_log "$TEXT_PATCH_FAILED"; return 1; }


  if [ "$is_debug" = "yes" ]; then
    write_log "$TEXT_DEBUG_MODE"
    efisp_target=$RUNTIME_DIR/efisp
  else
    efisp_target=$EFISP_DIR
    if ! persist_mounted; then
      write_log "$TEXT_PERSIST_NOT_MOUNTED"
      return 1
    fi
  fi

  mkdir -p "$efisp_target" >> "$LOG_FILE" 2>&1 || { write_log "$TEXT_EFISP_MKDIR_FAILED"; return 1; }

  # Keep the previous boot.efi around as a one-level backup. Skipped in debug,
  # where the staging dir is freshly emptied.
  if [ "$is_debug" != "yes" ] && [ -f "$efisp_target/boot.efi" ]; then
    mv "$efisp_target/boot.efi" "$efisp_target/boot_backup.efi" >> "$LOG_FILE" 2>&1
    write_log "$TEXT_BACKUP_BOOT"
  fi

  if ! cp $RUNTIME_DIR/patched.efi "$efisp_target/boot.efi" >> "$LOG_FILE" 2>&1; then
    write_log "$TEXT_EFISP_WRITE_FAILED"
    return 1
  fi
  sync
  write_log "$TEXT_EFISP_FILES_OK"
  return 0
}
cleanup_lock() { rm -rf "$LOCK_DIR" "$PID_FILE"; }

print_status() {
  ensure_runtime
  current_slot=$(detect_current_slot)
  target_slot=$(other_slot "$current_slot")
  running=0
  pid=$(current_pid)
  [ -n "$pid" ] && running=1
  _state=$(read_line "$STATE_FILE")
  _msg=$(read_line "$MESSAGE_FILE")
  _upd=$(read_line "$UPDATED_FILE")

  out="CURRENT_SLOT=$current_slot
TARGET_SLOT=$target_slot
RUNNING=$running
PID=$pid
STATE=$_state
MESSAGE=$_msg
UPDATED_AT=$_upd
USER_LANG=$LANG"
  emit "$out"
}

run_flash() {
  mode=$1
  debug=no
  if [ "$mode" = "debug" ]; then
    debug=yes
    mode=update-efisp
  fi

  ensure_runtime
  mkdir "$LOCK_DIR" 2>/dev/null || { write_log "$TEXT_BUSY"; exit 1; }
  echo $$ > "$PID_FILE"
  trap cleanup_lock EXIT INT TERM HUP
  : > "$LOG_FILE"

  current_slot=$(detect_current_slot)
  target_slot=$(other_slot "$current_slot")
  [ -z "$current_slot" ] && { write_state error "$TEXT_NO_SLOT"; exit 1; }
  [ -z "$target_slot" ] && { write_state error "$TEXT_NO_TARGET_SLOT"; exit 1; }
  write_state running "$TEXT_FLASHING $target_slot"

  abl=$(partition_path abl "$target_slot")

  if [ "$debug" = "yes" ]; then
    update_efisp "$abl" yes
    if [ $? -eq 0 ]; then
      write_state success "$TEXT_DEBUG_DONE $RUNTIME_DIR"
    else
      write_state error "$TEXT_DEBUG_FAILED"
    fi
    exit 0
  fi

  efisp_fail=0
  if [ "$mode" = "update-efisp" ]; then
    update_efisp "$abl" no
    res=$?
    if [ $res -eq 1 ]; then
      efisp_fail=1
      write_state running "$TEXT_EFISP_WARN"
    fi
  fi

  for part in $IMAGE_NAMES; do
    dst=$(partition_path "$part" "$target_slot")
    src=$(partition_path "$part" "$current_slot")
    blockdev --setrw "$dst" >> "$LOG_FILE" 2>&1 || { write_state error "$TEXT_SET_RW_FAILED"; exit 1; }
    dd if="$src" of="$dst" bs=4M conv=fsync >> "$LOG_FILE" 2>&1 || { write_state error "$TEXT_FLASH_PART failed"; exit 1; }
    sync
    write_log "$TEXT_FLASH_PART $part -> $dst $TEXT_FLASH_OK"
  done

  if [ $efisp_fail -eq 1 ]; then
    write_state warning "BL done, efisp failed"
  elif [ "$mode" = "update-efisp" ]; then
    write_state success "$TEXT_ALL_OK"
  else
    write_state success "$TEXT_ALL_OK_NO_EFISP"
  fi
}

start_flash() {
  ensure_runtime
  [ -n "$(current_pid)" ] && { emit "ALREADY_RUNNING=1"; return; }
  nohup sh "$0" flash "$1" >/dev/null 2>&1 &
  sleep 1
  if [ -n "$(current_pid)" ]; then
    emit "STARTED=1"
  else
    st=$(read_line "$STATE_FILE")
    [ -n "$st" ] && emit "FINISHED=$st" || emit "STARTED=0"
  fi
}

print_log() { cat "$LOG_FILE" | tr '\n' '\t'; }
tail_log() { tail -n200 "$LOG_FILE" | tr '\n' '\t'; }

clear_log() {
  ensure_runtime
  [ -n "$(current_pid)" ] && { emit "BUSY=1"; return; }
  : > "$LOG_FILE"
  write_state idle "$TEXT_LOG_CLEARED"
  emit "CLEARED=1"
}

case "$1" in
  status) print_status ;;
  flash) run_flash "$2" ;;
  start) start_flash "$2" ;;
  log) print_log ;;
  tail) tail_log ;;
  clear-log) clear_log ;;
  *) exit 1 ;;
esac
