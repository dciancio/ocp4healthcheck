#!/bin/bash

OPTION1=$1
OPTION2=$2

## Report based on a must-gather or live cluster

if [[ "$OPTION1" != "--live" ]] && [[ "$OPTION1" != "--must-gather" ]] && [[ "$OPTION2" != "--log" ]]; then
  printf "usage: $0 [--live | --must-gather] [--log]\n" >&2 && exit 1
fi

if [[ "$OPTION1" = "--live" ]]; then
  OCWHOAMI=$(oc whoami 2>/dev/null)
  if [[ -z "$OCWHOAMI" ]]; then
    printf "Live option requires that OC login user context to be set. Ensure the user has cluster-admin permissions.\n" >&2 && exit 1
  fi
  CMD="oc"
  printf "Using this oc login user context:\n" 
  printf "API URL: %s   USER: %s\n" $(oc whoami --show-server) $(oc whoami)
fi

if [[ "$OPTION1" = "--must-gather" ]]; then
  omc use | grep 'must-gather: ""' && printf "Must-gather option requires configuring a must-gather to use with omc (https://github.com/gmeghnag/omc).\n" >&2 && exit 1
  CMD="omc"
  printf "Using this omc must-gather report:\n" 
  $CMD use
fi

echo ""
read -p "Would you like to continue (Y/y) or set another user context for oc or omc (N/n)? " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 0
fi

if [[ "$OPTION2" = "--log" ]]; then
  exec &>ocp4healthcheck.log
fi

OCPVER=$($CMD get clusterversion -o=jsonpath={.items[*].status.desired.version})

# OCP version
printf "\nOCP version:  ${OCPVER}\n"

ETCDNS="openshift-etcd"
# ETCD Health
printf "\nETCD state:\n"
if [[ "$OPTION1" = "--live" ]]; then
  ETCD=( $($CMD -n $ETCDNS get -l k8s-app=etcd pods -o name | tr -s '\n' ' ' | sed 's/pod\///g' ) )
  for i in ${ETCD[@]}; do
    echo -e ""
    echo -e "-[$i]--------------------"
    $CMD exec -n $ETCDNS $i -c etcdctl -- etcdctl endpoint status -w table
  done
fi
if [[ "$OPTION1" = "--must-gather" ]]; then
  $CMD etcd health
  $CMD etcd status
fi

# ETCD log analysis
for i in $($CMD -n $ETCDNS get pods -l etcd -o name | grep -v NAME)
do
  printf "\nETCD log analysis:\n"
  echo -e ""
  echo -e "-[$i]--------------------"
  if [[ "$OPTION1" = "--live" ]]; then
    printf "Log timestamp - Start               : %30s\n" $($CMD logs -c etcd -n $ETCDNS $i | head -1 | tail -1|cut -d ',' -f2 | cut -d ':' -f2-5| tr -d '"') 
    printf "Log timestamp - End                 : %30s\n" $($CMD logs -c etcd -n $ETCDNS $i | tail -1 | tail -1|cut -d ',' -f2 | cut -d ':' -f2-5| tr -d '"') 
  fi
  if [[ "$OPTION1" = "--must-gather" ]]; then
    printf "Log timestamp - Start               : %30s\n" $($CMD logs -c etcd -n $ETCDNS $i | head -1 | awk '{print $1}') 
    printf "Log timestamp - End                 : %30s\n" $($CMD logs -c etcd -n $ETCDNS $i | tail -1 | awk '{print $1}') 
  fi
  printf "local node might have slow network  : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "local node might have slow network")
  printf "elected leader                      : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "elected leader")
  printf "leader changed                      : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "leader changed")
  printf "took too long                       : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "took too long")
  printf "lost leader                         : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "lost leader")
  printf "wal: sync duration                  : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "wal: sync duration")
  printf "slow fdatasync messages             : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "slow fdatasync")
  printf "the clock difference against peer   : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "the clock difference against peer")
  printf "lease not found                     : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "lease not found")
  printf "rafthttp: failed to read            : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "rafthttp: failed to read")
  printf "server is likely overloaded         : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "overloaded")
  printf "failed to send out heartbeat on time: %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "failed to send out heartbeat on time")
  printf "lost the tcp streaming              : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "lost the tcp streaming")
  printf "sending buffer is full              : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "sending buffer is full")
  printf "database space exceeded             : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "database space exceeded")
  printf "Recent compaction                   : %10s\n" $($CMD logs -c etcd -n $ETCDNS $i | grep compaction|tail -8|cut -d ',' -f6)

  if [[ "$OPTION1" = "--live" ]]; then

  # ETCD object count
  echo -e ""
  echo -e "ETCD object count:"
  echo -e ""
  $CMD exec -n $ETCDNS $i -c etcdctl -n $ETCDNS -- etcdctl get / --prefix --keys-only | sed '/^$/d' | cut -d/ -f3 | sort | uniq -c | sort -rn | head -14
  echo -e ""

  echo -e ""
  echo -e "ETCD objects [most events]:"
  echo -e ""
  $CMD exec -n $ETCDNS $i -c etcdctl -n $ETCDNS -- etcdctl get / --prefix --keys-only | grep event |cut -d/ -f3,4| sort | uniq -c | sort -n --rev| head -10
  echo -e ""

  fi
done

if [[ "$OPTION1" = "--live" ]]; then
  # API top consumers
  echo -e ""
  echo -e "API top consumers kube-apiserver on masters:"
  echo -e ""
  IFS=$'\n'
  for i in $(oc adm node-logs --role=master --path=kube-apiserver|grep "audit-.*.log"); do
    NODE=$(echo $i | awk '{print $1}')
    LOGFN=$(echo $i | awk '{print $2}')
    echo -e "[ Processing NODE: $NODE  LOGFILE: $LOGFN ]"
    oc adm node-logs $NODE --path=kube-apiserver/$LOGFN | jq -r '.user.username' | sort | uniq -c | sort -bgr | head -10 
    echo -e ""
  done

  echo -e ""
  echo -e "API top consumers openshift-apiserver on masters:"
  echo -e ""
  IFS=$'\n'
  for i in $(oc adm node-logs --role=master --path=openshift-apiserver|grep "audit-.*.log"); do
    NODE=$(echo $i | awk '{print $1}')
    LOGFN=$(echo $i | awk '{print $2}')
    echo -e "[ Processing NODE: $NODE  LOGFILE: $LOGFN ]"
    oc adm node-logs $NODE --path=openshift-apiserver/$LOGFN | jq -r '.user.username' | sort | uniq -c | sort -bgr | head -10 
    echo -e ""
  done
fi

# Monitoring Alerts Firing
printf "\nMonitoring Alerts firing:\n"
if [[ "$OPTION1" = "--live" ]]; then
  $CMD -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- curl -s 'http://localhost:9090/api/v1/alerts' | jq -r '.data[]|.[]|select(.state == "firing")|(.labels.alertname+"|"+.annotations.description))'
fi
if [[ "$OPTION1" = "--must-gather" ]]; then
  $CMD alert rule -o json | jq -r '.data[]|select(.state == "firing")|.alerts[]|(.labels.alertname+"|"+.annotations.message+"|"+.annotations.description)'
fi

# Cluster Events
printf "\nCluster Events (Non-Normal):\n"
$CMD get events -A |grep -v Normal

# Node state
printf "\nNode state:\n"
printf "Total Nodes:        %5d\t" $($CMD get nodes | grep -v NAME | wc -l)
printf "Non-Ready Nodes:    %5d\n" $($CMD get nodes | grep -v NAME | grep -vw Ready | wc -l)
printf "Resource to investigate:\n"
$CMD get nodes | grep -v NAME | grep -vw Ready

# Cluster Operator state
printf "\nCluster Operator state:\n"
printf "Total COs:          %5d\t" $($CMD get co | grep -v NAME | wc -l)
printf "Non-Ready COs:      %5d\n" $($CMD get co | grep -v NAME | egrep -v "(.*)${OCPVER}(\s+)True(\s+)False(\s+)False(\s+)" | wc -l)
printf "Resource to investigate:\n"
$CMD get co | grep -v NAME | egrep -v "(.*)${OCPVER}(\s+)True(\s+)False(\s+)False(\s+)"

# API Services state
printf "\nAPI Services state:\n"
printf "Total API Services:          %5d\t" $($CMD get apiservices -o=custom-columns="name:.metadata.name,status:.status.conditions[0].status" | grep -v NAME | wc -l)
printf "Non-Ready API Services:      %5d\n" $($CMD get apiservices -o=custom-columns="name:.metadata.name,status:.status.conditions[0].status" | grep -v NAME | egrep -v "(.*)(\s+)False(\s+)" | wc -l)
printf "Resource to investigate:\n"
$CMD get apiservices -o=custom-columns="name:.metadata.name,status:.status.conditions[0].status" | grep -v NAME | egrep -v "(.*)(\s+)False(\s+)"

# Machine Config Pool state
printf "\nMachine Config Pool state:\n"
printf "Total MCPs:         %5d\t" $($CMD get mcp | grep -v NAME | wc -l)
printf "Non-Ready MCPs:     %5d\n" $($CMD get mcp | grep -v NAME | egrep -v "(.*)True(\s+)False(\s+)False(.*)" | wc -l)
printf "Resource to investigate:\n"
$CMD get mcp | grep -v NAME | egrep -v "(.*)True(\s+)False(\s+)False(.*)" 

# Operator state
printf "\nOperator state:\n"
printf "Total CSVs:         %5d\t" $($CMD get csv -A | grep -v NAMESPACE | wc -l)
printf "Failed CSVs:        %5d\n" $($CMD get csv -A | grep -v NAMESPACE | grep -v Succeeded | wc -l)
printf "Resource to investigate:\n"
$CMD get csv -A | grep -v NAMESPACE | grep -v Succeeded

# Operator sub
printf "\nOperator subscription channels:\n"
$CMD get sub -A

# Pod state
printf "\nPod state:\n"
printf "Total Running Pods: %5d\t" $($CMD get pods -A | grep -v NAMESPACE | grep Running | wc -l)
printf "Non-Running Pods:   %5d\n" $($CMD get pods -A | grep -v NAMESPACE | grep -v Running | grep -v Completed | wc -l)
printf "Resource to investigate:\n"
$CMD get pods -A | grep -v NAMESPACE | grep -v Running | grep -v Completed

# Pod restarts, ordered by highest number of restarts first
printf "\nPod restarts:\n"
$CMD get pods -A | grep -v NAMESPACE | grep -v Completed | egrep -v "(.*)Running(\s+)0(.*)" | sort -k5 -n -r
