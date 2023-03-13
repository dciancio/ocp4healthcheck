## Pre-requisites

- OC CLI (https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp). Select the appropriate version and install on your host (e.g. /usr/local/bin).
- OMC (https://github.com/gmeghnag/omc) for reading must-gather reports.  Select the latest release and install on your host (e.g. /usr/local/bin).


## Installation

- Clone this git repo to your host.
- Execute the script as follows:
  ./ocp4healthcheck.sh 

  usage: ocp4healthcheck.sh [--live | --must-gather] [--log]

  Options:

  -  --live         => analyze a running cluster in real-time
  -  --must-gather  => analyze a must-gather
  -  --log          => log the output to a file named ocp4healthcheck.log (created in the current working directory)

