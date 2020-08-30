# Datomic on Cassandra, running on GKE

This tutorial walks you through setting up a on-prem Datomic-on-Cassandra running in a GKE
cluster. This guide is not for people looking for a fully automated command to bring up a
Datomic deployment. If that's you then check out [Datomic Cloud](https://docs.datomic.com/cloud/index.html).

> The results of this tutorial should not be viewed as production ready,
> but rather as a learning tool, and a quick way to get a datomic on-prem staging environment!

## 1. Setting up cluster

### 1.1 Configuring `gcloud`

Assuming you have a Google Cloud account with sufficient credit, setup the project and default region/zone.

```bash
$ export PROJECT_ID=<your_project>
$ export REGION=<your_region> # ex. europe-west1
$ export ZONE=<your_zone> # ex. europe-west1-d
$ gcloud config set core/project $PROJECT_ID
$ gcloud config set compute/region $REGION
$ gcloud config set compute/zone $ZONE
```

### 1.2 Installing `kubectl` and `kpt`

This guide assumes you have installed `kubectl`, but you will need `kpt` as well. Both can be installed using `gcloud`.

```bash
$ gcloud components install kubectl
$ gcloud components install kpt
```

### 1.3 Install a dedicated network for your private cluster

IMHO it's always best to have a cluster in its own subnetwork,
and all clusters within a single network. So create one :)
For the purposes of this guide, the `network_name` shall be `k8s` and `subnet_name`,
the name of our cluster, `datomic-cass`.

```bash
$ export NETWORK=k8s
$ export SUBNETWORK=datomic-cass
$ gcloud compute networks create $NETWORK --project $PROJECT_ID --subnet-mode custom
```

### 1.4 Install the private GKE cluster

Since we are using private clusters, and intend to expose Cassandra and the Datomic transactor through load balancers,
it is necessary to determine what your network is and save it for later authorization. For example:

```bash
$ export AUTHORIZED_NETWORKS=$(curl -4 https://ifconfig.co/)/32
```

Create the cluster using `gcloud` (and modify if necessary).

```bash
$ export CLUSTER_NAME=$SUBNETWORK
$ gcloud container clusters create "$CLUSTER_NAME" \
   --project $PROJECT_ID \
   --addons HorizontalPodAutoscaling,HttpLoadBalancing \
   --cluster-version 1.16.13-gke.1 \
   --create-subnetwork name=$SUBNETWORK \
   --default-max-pods-per-node 110 \
   --disable-default-snat \
   --disk-size 100 \
   --disk-type pd-standard \
   --enable-autorepair \
   --enable-intra-node-visibility \
   --enable-ip-alias \
   --enable-master-authorized-networks \
   --enable-private-nodes \
   --enable-shielded-nodes \
   --enable-vertical-pod-autoscaling \
   --image-type COS \
   --machine-type e2-standard-4 \
   --maintenance-window-start 2020-08-28T00:00:00Z \
   --maintenance-window-end 2020-08-28T04:00:00Z \
   --maintenance-window-recurrence "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU" \
   --master-authorized-networks $AUTHORIZED_NETWORKS \
   --master-ipv4-cidr 192.168.0.0/28 \
   --max-surge-upgrade 1 \
   --max-unavailable-upgrade 0 \
   --metadata disable-legacy-endpoints=true \
   --network "$NETWORK" \
   --no-enable-autoupgrade \
   --no-enable-basic-auth \
   --no-enable-legacy-authorization \
   --no-enable-stackdriver-kubernetes \
   --num-nodes 4 \
   --tags "$CLUSTER_NAME-node" \
   --workload-metadata GKE_METADATA \
   --workload-pool "$PROJECT_ID.svc.id.goog"
Creating cluster datomic-cass in <your_zone>... Cluster is being health-checked (master is healthy)...done.
Created [https://container.googleapis.com/v1/projects/<your_project>/zones/<your_zone>/clusters/datomic-cass].
To inspect the contents of your cluster, go to: https://console.cloud.google.com/kubernetes/workload_/gcloud/<your_zone>/datomic-cass?project=<your_project>
kubeconfig entry generated for datomic-cass.
NAME          LOCATION        MASTER_VERSION  MASTER_IP       MACHINE_TYPE   NODE_VERSION   NUM_NODES  STATUS
datomic-cass  <your_zone>     1.16.13-gke.1   <master_ip>     e2-standard-4  1.16.13-gke.1  4          RUNNING
```

Finally, connect to the cluster and make sure everything is OK :)

```bash
$ gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE --project $PROJECT_ID
$ kubectl get ns
NAME              STATUS   AGE
default           Active   10m
kube-node-lease   Active   10m
kube-public       Active   10m
kube-system       Active   10m
```

### 1.5 Create a router and NAT for node internet access (ingress only)

In order to pull docker images from the internet, a router + nat configuration must be created
since it is a private cluster

```bash
$ export ROUTER_NAME="$NETWORK-internet-router"
$ gcloud compute routers create $ROUTER_NAME \
   --project $PROJECT_ID \
   --region $REGION \
   --network $NETWORK
$ export NAT_IP_ADDR_NAME="$ROUTER_NAME-nat-external-ip"
$ gcloud compute addresses create $NAT_IP_ADDR_NAME \
   --project $PROJECT_ID \
   --region $REGION \
   --description "External IP Address to use for $ROUTER_NAME-nat"
$ gcloud compute routers nats create $ROUTER_NAME-nat \
   --project $PROJECT_ID \
   --router-region $REGION \
   --router $ROUTER_NAME \
   --nat-all-subnet-ip-ranges \
   --nat-external-ip-pool $NAT_IP_ADDR_NAME
```

We can test internet connectivity (pulling public images, connecting to external services),
by running an ephemeral busybox pod and performing some smoke checks.

```bash
$ kubectl run --rm -ti --image busybox busybox
If you don't see a command prompt, try pressing enter.
/ # ping 8.8.8.8
PING 8.8.8.8 (8.8.8.8): 56 data bytes
64 bytes from 8.8.8.8: seq=0 ttl=114 time=1.046 ms
64 bytes from 8.8.8.8: seq=1 ttl=114 time=1.034 ms
64 bytes from 8.8.8.8: seq=2 ttl=114 time=1.143 ms
64 bytes from 8.8.8.8: seq=3 ttl=114 time=0.926 ms
^C
--- 8.8.8.8 ping statistics ---
4 packets transmitted, 4 packets received, 0% packet loss
round-trip min/avg/max = 0.926/1.037/1.143 ms
/ # exit
Session ended, resume using 'kubectl attach busybox -c busybox -i -t' command when the pod is running
pod "busybox" deleted
```
