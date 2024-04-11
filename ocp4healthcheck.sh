#!/bin/bash

OPTIONS=$1

## Report based on a must-gather or live cluster

usage()
{  
  printf "usage: $0 [--live | --must-gather] [--scanaudit] [--log]\n" >&2 && exit 1
  exit 1
}

OPTIONS="live:must-gather:scanaudit:log:"
PARAMS=$*
eval set -- `getopt $OPTIONS -- $PARAMS`
if [ $? -ne 0 ] || [ -z "$PARAMS" ]; then
   usage
fi

for i in $PARAMS
do
  case $i in
       --live) live=true; shift;;
       --must-gather) mustgather=true; shift;;
       --scanaudit) scanaudit=true; shift;;
       --log) log=true; shift;;
       --) shift; break;;
       *) usage;;
  esac
done

if [[ $live ]] && [[ $mustgather ]]; then
  usage
fi

if [[ $live ]]; then
  OCWHOAMI=$(oc whoami 2>/dev/null)
  if [[ -z "$OCWHOAMI" ]]; then
    printf "Live option requires that OC login user context to be set. Ensure the user has cluster-admin permissions.\n" >&2 && exit 1
  fi
  CMD="oc"
  printf "Using this oc login user context:\n" 
  printf "API URL: %s   USER: %s\n" $(oc whoami --show-server) $(oc whoami)
fi

if [[ $mustgather ]]; then
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

if [[ $log ]]; then
  exec &>ocp4healthcheck.log
fi

# OCP cluster info
OCPVER=$($CMD get clusterversion -o=jsonpath={.items[*].status.desired.version})
OCPCLUSTERID=$($CMD get clusterversion -o=jsonpath={.items[*].spec.clusterID})
printf "\nCluster info:\n"
printf "OCP version   :  ${OCPVER}\n"
printf "OCP cluster ID:  ${OCPCLUSTERID}\n"

# OCP node info
printf "\nNode details:\n"
printf "\nMaster nodes:\n"
(echo "NAME|CPU|MEMORY|ROLES"; $CMD get nodes | grep master | awk '{print $1" "$3}' | while read node role;  do echo "$($CMD get node $node -o json | jq -r '(.metadata.name+"|"+.status.capacity.cpu+"|"+.status.capacity.memory)')|$role" ; done ) | column -s"|" -t
$CMD get nodes -l node-role.kubernetes.io/master=  -o json | jq -r '.items[]|(.metadata.name+","+.status.capacity.cpu+","+.status.capacity.memory)' | awk -F"," '{num=num+1;sum+=$2} END {print "Total Nodes:  "num,"      Total CPU:  "sum}'
printf "\nWorker nodes:\n"
(echo "NAME|CPU|MEMORY|ROLES"; $CMD get nodes | grep worker | grep -v infra | awk '{print $1" "$3}' | while read node role;  do echo "$($CMD get node $node -o json | jq -r '(.metadata.name+"|"+.status.capacity.cpu+"|"+.status.capacity.memory)')|$role"; done ) | column -s"|" -t
$CMD get nodes -l node-role.kubernetes.io/worker=  -o json | jq -r '.items[]|(.metadata.name+","+.status.capacity.cpu+","+.status.capacity.memory)' | awk -F"," '{num=num+1;sum+=$2} END {print "Total Nodes:  "num,"      Total CPU:  "sum}'
printf "\nInfra nodes:\n"
(echo "NAME|CPU|MEMORY|ROLES"; $CMD get nodes | grep infra | awk '{print $1" "$3}' | while read node role;  do echo "$($CMD get node $node -o json | jq -r '(.metadata.name+"|"+.status.capacity.cpu+"|"+.status.capacity.memory)')|$role"; done ) | column -s"|" -t
$CMD get nodes -l node-role.kubernetes.io/infra=  -o json | jq -r '.items[]|(.metadata.name+","+.status.capacity.cpu+","+.status.capacity.memory)' | awk -F"," '{num=num+1;sum+=$2} END {print "Total Nodes:  "num,"      Total CPU:  "sum}'

printf "\nSuggested Node Sizing:

               ---- Master Node ----  ---- Worker Node ----  ---- Infra  Node ----
Worker Count   vCPU  RAM-GB  Disk-GB  vCPU  RAM-GB  Disk-GB  vCPU   RAM-GB   Disk-GB
============   ====  ======  =======  ====  ======  =======  =====  ======   =======
<  25           4    16      120/500   2     8      120/500   4      16/ 24  120/500
>= 25           8    32      120/500   4    16      120/500   8      32/ 48  120/500
>= 120         16    64/ 96  120/500   8    32      120/500  16/48   64/ 96  120/500
>= 252         16    96/128  120/500   8    32      120/500  32/48  128/192  120/500

** Column may show 'Min/Recommended' values

\n"

ETCDNS="openshift-etcd"
# ETCD Health
printf "\nETCD state:\n"
if [[ $live ]]; then
  ETCD=( $($CMD -n $ETCDNS get -l k8s-app=etcd pods -o name | tr -s '\n' ' ' | sed 's/pod\///g' ) )
  for i in ${ETCD[@]}; do
    echo -e ""
    echo -e "-[$i]--------------------"
    $CMD exec -n $ETCDNS $i -c etcdctl -- etcdctl endpoint status -w table
  done
fi
if [[ $mustgather ]]; then
  $CMD etcd health
  $CMD etcd status
fi

# ETCD log analysis
for i in $($CMD -n $ETCDNS get pods -l etcd -o name | grep -v NAME)
do
  printf "\nETCD log analysis:\n"
  echo -e ""
  echo -e "-[$i]--------------------"
  if [[ $live ]]; then
    printf "Log timestamp - Start               : %30s\n" $($CMD logs -c etcd -n $ETCDNS $i --timestamps | head -1 | awk '{print $1}') 
    printf "Log timestamp - End                 : %30s\n" $($CMD logs -c etcd -n $ETCDNS $i --timestamps | tail -1 | awk '{print $1}') 
  fi
  if [[ $mustgather ]]; then
    printf "Log timestamp - Start               : %30s\n" $($CMD logs -c etcd -n $ETCDNS $i | head -1 | awk '{print $1}') 
    printf "Log timestamp - End                 : %30s\n" $($CMD logs -c etcd -n $ETCDNS $i | tail -1 | awk '{print $1}') 
  fi
  printf "local node might have slow network         : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "local node might have slow network")
  printf "elected leader                             : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "elected leader")
  printf "leader changed                             : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "leader changed")
  printf "apply request took too long                : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "apply request took too long")
  printf "lost leader                                : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "lost leader")
  printf "wal: sync duration                         : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "wal: sync duration")
  printf "slow fdatasync messages                    : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "slow fdatasync")
  printf "the clock difference against peer          : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "the clock difference against peer")
  printf "lease not found                            : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "lease not found")
  printf "rafthttp: failed to read                   : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "rafthttp: failed to read")
  printf "leader failed to send out heartbeat on time: %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "leader failed to send out heartbeat on time")
  printf "leader is overloaded likely from slow disk : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "leader is overloaded likely from slow disk")
  printf "lost the tcp streaming                     : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "lost the tcp streaming")
  printf "sending buffer is full (heartbeat)         : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "sending buffer is full")
  printf "overloaded network (heartbeat)             : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "overloaded network")
  printf "database space exceeded                    : %10d\n" $($CMD logs -c etcd -n $ETCDNS $i | grep -ic "database space exceeded")
  printf "Recent compaction                          : %10s\n" $($CMD logs -c etcd -n $ETCDNS $i | grep compaction|tail -8|cut -d ',' -f6)

  if [[ $live ]]; then

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

if [[ $scanaudit ]]; then

if [[ $live ]]; then
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

fi

# Monitoring Alerts Firing
printf "\nMonitoring Alerts firing:\n"
if [[ $live ]]; then
  $CMD -n openshift-monitoring exec -c prometheus prometheus-k8s-0 -- curl -s 'http://localhost:9090/api/v1/alerts' | jq -r '.data[]|.[]|select(.state == "firing")|(.labels.alertname+"|"+.annotations.description+"\n")'
fi
if [[ $mustgather ]]; then
  $CMD prometheus alertrule -o json | jq -r '.data[]|select(.state == "firing")|.alerts[]|(.labels.alertname+"|"+.annotations.message+"|"+.annotations.description+"\n")'
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
printf "Non-Ready COs:      %5d\n" $($CMD get co | grep -v NAME | grep -E -v "(.*)${OCPVER}(\s+)True(\s+)False(\s+)False(\s+)" | wc -l)
printf "Resource to investigate:\n"
$CMD get co | grep -v NAME | grep -E -v "(.*)${OCPVER}(\s+)True(\s+)False(\s+)False(\s+)"

# API Services state
printf "\nAPI Services state:\n"
printf "Total API Services:          %5d\t" $($CMD get apiservices | grep -v NAME | wc -l)
printf "Non-Ready API Services:      %5d\n" $($CMD get apiservices | grep -v NAME | grep -E -v "(.*)True(.*)" | wc -l)
printf "Resource to investigate:\n"
$CMD get apiservices | grep -v NAME | grep -E -v "(.*)True(.*)"

# Machine Config Pool state
printf "\nMachine Config Pool state:\n"
printf "Total MCPs:         %5d\t" $($CMD get mcp | grep -v NAME | wc -l)
printf "Non-Ready MCPs:     %5d\n" $($CMD get mcp | grep -v NAME | grep -E -v "(.*)True(\s+)False(\s+)False(.*)" | wc -l)
printf "Resource to investigate:\n"
$CMD get mcp | grep -v NAME | grep -E -v "(.*)True(\s+)False(\s+)False(.*)" 

# Operator state
printf "\nOperator state:\n"
printf "Total CSVs:         %5d\t" $($CMD get csv -A | grep -v NAMESPACE | wc -l)
printf "Failed CSVs:        %5d\n" $($CMD get csv -A | grep -v NAMESPACE | grep -v Succeeded | wc -l)
printf "Resource to investigate:\n"
$CMD get csv -A | grep -v NAMESPACE | grep -v Succeeded

# Pending CSV updates reported in olm-operator pod
printf "\nPending CSV updates reported in olm-operator pod:\n"
$CMD logs $($CMD get pod --no-headers -l app=olm-operator -oname) | grep Pending | sed -n 's/^\(.*\)\(\s\)time="\(.*\)"\(\s\)level=\(.*\)\(\s\)msg="\(.*\)"\(\s\)csv=\(.*\)\(\s\)*id=\(.*\)\(\s\)namespace=\(.*\)\(\s\)phase=\(.*\)$/\3 \9/p' | awk '{print(substr($1,1,10),$2)}' | sort | uniq | column -N "DATE,CSV" -t

# Operator sub
printf "\nOperator subscription channels:\n"
$CMD get sub -A

# Pod state
printf "\nPod state:\n"
printf "Total Running Pods: %5d\t" $($CMD get pods -A | grep -v NAMESPACE | grep Running | wc -l)
printf "Non-Running Pods:   %5d\n" $($CMD get pods -A | grep -v NAMESPACE | grep -v Running | grep -v Completed | wc -l)
printf "Resource to investigate:\n"
$CMD get pods -A | grep -v NAMESPACE | grep -v Running | grep -v Completed

# List installed and available operators
printf "\nOperators Installed and Available Versions:\n"
$CMD get operator -o json | jq -r '.items[]|.metadata.name+" "+(.status.components.refs[]? | select (.kind=="ClusterServiceVersion") | (.name+" "+.namespace))' | while read var1 var2 var3
do
OP=$(echo $var1 | awk -F. '{print $1}')
$CMD get -n openshift-marketplace packagemanifest $OP -o json | jq -r "(.status.channels[]|(.currentCSV+\"|\"+.name+\"|\"+(.currentCSVDesc.annotations|(.\"operatorframework.io/suggested-namespace\"+\"|\"+.\"olm.properties\"+\"|\"+.\"olm.skipRange\"))+\"|\"+(if (.currentCSV==\"$var2\") then \"***installed***\" else \"\" end)))"
done

# Last 5 operator transition events
printf "\nOperator Transition Events (last 5):\n"
for i in $($CMD get crd --no-headers | awk '{print $1}' | grep "\.operator\." ); do
  if [[ $($CMD get $i -A -o json | jq -r '.items[]?|.status.conditions[]?' | wc -l) != 0 ]]; then
    echo -e "--- $i ---\n"
    $CMD get $i -A -o json | jq -r '.items[]?|.status.conditions[]?|(.lastTransitionTime+","+.type+","+.status)' | tail -5 | sort | column -s, -t -N "TRANSITION_TIME,TYPE,STATUS"
    echo
  fi
done

# Report deprecated API Usage
printf "\nReport Deprecated API Usage:\n"
$CMD get apirequestcounts -o json | jq -r '[
  .items[]
  | select(.status.removedInRelease)
  | .metadata.name as $api 
  | {name: .metadata.name, removedInRelease: .status.removedInRelease}
    + (.status.last24h[] | select(has("byNode")) | .byNode[] | select(has("byUser")) | .byUser[] | {username,userAgent,"verb": .byVerb[].verb})
    + {currHour: .status.currentHour.requestCount, last24H: .status.requestCount}
]
| group_by( {name, removedInRelease, username, userAgent} )
| map(first + {verb: map(.verb) | unique})
| .[] | [.removedInRelease, .name, .username, .userAgent, (.verb | join(",")),.currHour, .last24H]
| join("\t")' | sort | column -N "DEPREL,NAME,USERNAME,USERAGENT,VERB,CURRHOUR,LAST24H" -t


# Display expiry dates for all certs (sorted by most recent expiration)
printf "\nCertificate Expiry Dates (Sorted By Most Recent Expiration):\n"
$CMD get secrets -A -o json | jq -r '.items | sort_by(.metadata.namespace,.metadata.name) |.[] |select((.type == "kubernetes.io/tls") or (.type == "SecretTypeTLS"))|.metadata.namespace+" "+.metadata.name+" "+(.data | to_entries[] | select(.key | test("tls.crt"))| .value)' | while read namespace name cert; do echo -n "$namespace,$name,"; echo $cert | base64 -d | openssl x509 -noout -enddate | cut -d"=" -f2 | date +"%Y-%m-%d %T GMT" -f - ; done | sort -t, -k3 | column -s, -t -N "NAMESPACE,NAME,EXPIRYDATE"

# Pod restarts, ordered by highest number of restarts first
printf "\nPod restarts:\n"
$CMD get pods -A -o wide | grep -v NAMESPACE | grep -v Completed | grep -E -v "(.*)Running(\s+)0(.*)" | sort -k5 -n -r

