#!/bin/bash
INIT_DIR="init.d"

function dmcm_usage(){
  local usage=$(cat << EOF
Usage: dmcm <action> [options] <service> [resource]

Available actions:
$(dmcm_format_rows ${DMCM_AV_ACTIONS})

Available services:
$(dmcm_format_rows ${DMCM_AV_SERVICES})

Available resources:
$(dmcm_format_rows ${DMCM_AV_RESOURCES})
EOF
)

  dmcm_notify "${usage}"
}

function dmcm_debug(){
  if [[ -z $DMCM_DEBUG ]]; then
    false
  else
    dmcm_error "[DEBUG ${FUNCNAME[1]}] $@"
  fi
}

function dmcm_error(){
  echo "$*" 1>&2
}

function dmcm_notify(){
  printf "$*\n"
}

function dmcm_prompt(){
  true
}

function dmcm_format_rows(){
  local rows
  local row

  for row in "$@"; do
    if [[ -z $rows ]]; then
      rows="$row"
    else
      rows="$rows\n  $row"
    fi
  done

  echo "  $rows"
}

function dmcm_get_function(){
  echo "dmcm_${1}_${2}" | tr -d ' '
}

function dmcm_setup(){
   DMCM_PREFIX=
   DMCM_SERVICE_DIR=
   DMCM_BASE_DIR=
   DMCM_AV_SERVICES=
   DMCM_AV_ACTIONS=
   DMCM_AV_RESOURCES=

  for prefix in dmcm enstratus; do
    [ -z "$DMCM_PREFIX" -a -n "`ls -l ${INIT_DIR}/${prefix}-* 2>/dev/null`" ] && DMCM_PREFIX=$prefix
  done

  if [[ -z $DMCM_PREFIX ]]; then
    DMCM_PREFIX=dmcm
  fi

  for s in `ls ${INIT_DIR}/${DMCM_PREFIX}-*`; do
    sf=`echo \`basename $s\` | sed "s/^${DMCM_PREFIX}-//"`
    DMCM_AV_SERVICES="$DMCM_AV_SERVICES $sf"
  done

  DMCM_SERVICE_DIR="/services"
  DMCM_BASE_DIR="/opt/dmcm-base"
  DMCM_AV_ACTIONS="clear page restart rm set start status stop tail view"
  DMCM_AV_RESOURCES="logs runlogs servicelogs loglevel"
}

function dmcm_set_loglevel(){
  local levels="OFF FATAL ERROR WARN INFO DEBUG TRACE"
  local value=$(echo $DMCM_TOKENS | sed "s/^.*=\(.*\)$/\1/" | tr '[a-z]' '[A-Z]')

  #echo $levels | grep -iw "$value" > /dev/null &&\
  #  dmcm_error "Unknown level: $value" && return

  for level in $levels; do
  done

  echo "Setting loglevel to $value for $DMCM_SERVICE"
}

function dmcm_clear_logs(){
  for file in "$*"; do
    [[ -e $file ]] && > $file && dmcm_notify "truncated $file" || dmcm_notify "unable to truncate $file"
  done
}

function dmcm_page_logs(){
  less $*
}

function dmcm_rm_logs(){
  for file in "$*"; do
    if [[ -e $file ]]; then
      rm -f $file && dmcm_notify "removed $file" || dmcm_notify "unable to remove $file"
    else
      dmcm_notify "no such file $file"
    fi
  done
}

function dmcm_tail_logs(){
  echo $* | xargs tail -f
}

function dmcm_view_logs(){
  case $EDITOR in
  vim)
    vim -O $*
    ;;
  *)
    view $*
  esac
}

function dmcm_run_action_on_logs(){
  local logtype=$1
  local role
  local logname
  local loglist
  local addlog=1

  for service in $DMCM_SERVICE; do
    if [[ "$logtype" = "runlogs" ]]; then
      role=$service
      logname=$service
    else
      case $service in
      assign)
        role=monitor
        logname=$service
        ;;
      publisher|subscriber)
        role=worker
        logname="pubsub"
        ;;
      worker)
        role=worker
        logname=$service
        ;;
      *)
        role=$service
        logname=$service
        ;;
      esac
    fi

    if [[ "$DMCM_ACTION" = "rm" ]]; then
      if [[ -z `dmcm status $service | grep '^down'` ]]; then
        dmcm_notify "must stop $service first"
        addlog=0
      fi
    fi

    if [[ $addlog -eq 1 ]]; then
      local lf
      case $logtype in
      runlogs)
        lf="${DMCM_BASE_DIR}/sv/dmcm-${role}/log/run/main/current"
        ;;
      *)
        lf="${DMCM_SERVICE_DIR}/$role/logs/${logname}.log"
      esac

      loglist="$loglist $lf"
    fi
  done

  dmcm_debug "loglist: $loglist"

  local func=`dmcm_get_function $DMCM_ACTION "logs"`

  $func $loglist
}

function dmcm_run_action_on_resource(){
  local resource
  local func

  for resource in $DMCM_RESOURCE; do
    case $resource in
    logs|runlogs|servicelogs)
      dmcm_run_action_on_logs $resource
      ;;
    *)
      func=$(dmcm_get_function $DMCM_ACTION $DMCM_RESOURCE)
      type $func > /dev/null 2>&1

      dmcm_debug $func

      if [[ $? -ne 0 ]]; then
        dmcm_error "Unknown function: $func, called for resource: $resource"
        return
      else
        $func
      fi
      ;;
    esac
  done
}

function dmcm_run_action_on_service(){
  local action=$DMCM_ACTION
  local cmd
  local stat
  local pid

  for sv in $DMCM_SERVICE; do
    cmd="${INIT_DIR}/${DMCM_PREFIX}-${sv} $action"

    dmcm_notify "$cmd"

    $cmd

    if [ "$action" = "stop" -o "$action" = "restart" ]; then
      stat=$(${INIT_DIR}/${DMCM_PREFIX}-${sv} status)

      echo $stat | egrep "want down, got TERM" &&\
        pid=`echo $stat | awk '{ print $5 }' | cut -d\) -f1` &&\
        echo "force killing $pid" &&\
        sv ${DMCM_PREFIX}-$sv forceshutdown &&\
        dmcm start $sv
    fi
  done
}

function dmcm_run_sentence(){
  if [[ -z "$DMCM_ACTION" || -z "$DMCM_SERVICE" ]]; then
    dmcm_error "Missing action and/or service."
    dmcm_error "Sentence read: '$*'"
    return 1
  fi

  if [[ -z "$DMCM_RESOURCE" ]]; then
    case $DMCM_ACTION in
    page|tail|view)
      DMCM_RESOURCE="logs" && dmcm_run_action_on_resource
      ;;
    restart|status|start|stop)
      dmcm_run_action_on_service
      ;;
    *)
      dmcm_error "Missing resource."
      dmcm_error "Sentence read: '$*'"
      return 1
      ;;
    esac
  else
    dmcm_run_action_on_resource
  fi
}

function dmcm_pretty_print_sentence(){
  local action=$(echo $DMCM_ACTION | tr '[a-z]' '[A-Z]')
  local resource=$(echo $DMCM_RESOURCE | tr '[a-z]' '[A-Z'])
  local service=$(echo $DMCM_SERVICE | sed "s/ /, /g")

  echo "$action $service $resource"
}

function dmcm_print_sentence(){
  echo "$DMCM_ACTION $DMCM_SERVICE $DMCM_RESOURCE"
}

function dmcm_generate_sentence(){
  DMCM_TOKENS=$*
  DMCM_ACTION=
  DMCM_SERVICE=
  DMCM_RESOURCE=
  DMCM_STAR=

  local args=$*
  local count=1
  local arg

  for arg in $args; do

    if [[ -z $DMCM_ACTION ]]; then
      echo "${DMCM_AV_ACTIONS}" | grep -i -w "$arg" > /dev/null &&\
        [[ $? -eq "0" ]] && DMCM_ACTION=$arg
    fi

    echo "${DMCM_AV_SERVICES}" | grep -i -w "$arg" > /dev/null &&\
      [[ $? -eq "0" ]] && DMCM_SERVICE="$DMCM_SERVICE $arg"

    echo "$DMCM_AV_RESOURCES" | grep -i -w "$arg" > /dev/null &&\
      [[ $? -eq "0" ]] && DMCM_RESOURCE="$DMCM_RESOURCE $arg"

    [ "$arg" = "all" ] && DMCM_STAR=true
  done

  [[ -z $DMCM_SERVICE ]] && [[ $DMCM_STAR ]] && DMCM_SERVICE=$DMCM_AV_SERVICES

  dmcm_debug "DMCM_ACTION $DMCM_ACTION"
  dmcm_debug "DMCM_SERVICE $DMCM_SERVICE"
  dmcm_debug "DMCM_RESOURCE $DMCM_RESOURCE"

  [[ -z $DMCM_RESOURCE ]] && dmcm_error "I can't understand \"$*\". Get some --help." && return 1

  DMCM_ACTION=$(echo $DMCM_ACTION | xargs)
  DMCM_SERVICE=$(for s in `echo $DMCM_SERVICE`; do echo $s; done | sort -u | xargs)
  DMCM_RESOURCE=$(echo $DMCM_RESOURCE | xargs)

  [[ -z $DMCM_ACTION || -z $DMCM_SERVICE ]] && dmcm_error "I can't understand \"$*\". Get some --help." && return 1

  DMCM_SENTENCE=$(dmcm_print_sentence)
}

function dmcm(){
  GETOPT="/usr/local/Cellar/gnu-getopt/1.1.5/bin/getopt"

  DMCM_INTERACTIVE=
  DMCM_DEBUG=

  local flag
  local switchflag=0
  local tokens
  local sentence

  local args=`${GETOPT} -o hid -l "help,interactive" -n "dmcm" -- "$@"`

  dmcm_debug $args

  for arg in $args; do
    if [ "$arg" = "--" ]; then
      switchflag=1
    elif [ $switchflag -eq 1 ]; then
      tokens="$tokens $arg"
    else
      case $arg in
      -h|--help)
        dmcm_usage $@
        return
        ;;
      -i|--interactive)
        DMCM_INTERACTIVE=true
        ;;
      -d|--debug)
        DMCM_DEBUG=true
        ;;
      \?)
        dmcm_usage $@
        return
        ;;
      esac
    fi

    flag=$arg
  done

  tokens=$(echo $tokens | sed "s/'//g")

  dmcm_debug "interactive: $DMCM_INTERACTIVE"
  dmcm_debug "tokens: $tokens"

  dmcm_generate_sentence $tokens

  [[ $? -ne "0" ]] && return

  dmcm_debug "sentence: $DMCM_SENTENCE"

  dmcm_run_sentence
  return

  if [[ -n $DMCM_INTERACTIVE ]]; then
    read -p "$(dmcm_pretty_print_sentence)? [y/n] " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
      dmcm_run_sentence
    else
      dmcm_error 'Aborted.'
    fi
  else
    dmcm_run_sentence
  fi
}

dmcm_setup
