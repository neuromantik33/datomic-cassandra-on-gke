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

## 2. Installing Cassandra

We're going to keep things simple and straightforward by using a tweaked `kpt` based distribution
based on the [Cassandra Kubernetes](https://github.com/kubernetes/examples/tree/master/cassandra) example.

### 2.1 Reserve a public IP address for the cassandra client

```bash
$ export CASSANDRA_CLIENT_IP_ADDR_NAME=datomic-cass
$ gcloud compute addresses create $CASSANDRA_CLIENT_IP_ADDR_NAME \
   --project $PROJECT_ID \
   --region $REGION \
   --description "External IP Address to use for cassandra"
$ export CASSANDRA_CLIENT_IP_ADDR=$(gcloud compute addresses describe $CASSANDRA_CLIENT_IP_ADDR_NAME \
   --project $PROJECT_ID \
   --region $REGION \
   --format json | jq -r .address)
```

### 2.2 First create the `cassandra` namespace

```bash
$ kubectl create ns cassandra
namespace/cassandra created
```

Configure `kubectl` to point to the correct cluster and namespace (`cassandra` for now)

```bash
$ export GKE_CLUSTER_NAME=gke_"$PROJECT_ID"_"$ZONE"_"$CLUSTER_NAME"
$ kubectl config set-context $GKE_CLUSTER_NAME --namespace cassandra
Context <gke_cluster_name> modified.
$ kubectl config use-context $GKE_CLUSTER_NAME
```

### 2.3 Fetch and configure the cassandra distribution

Then fetch the cassandra distribution, don't forget to set the authorized networks 
and cassandra client IP determined before.

```bash
$ kpt pkg get https://github.com/neuromantik33/datomic-cassandra-on-gke/cassandra cassandra
$ kpt cfg set cassandra authorized-networks $AUTHORIZED_NETWORKS
$ kpt cfg set cassandra cassandra-ip $CASSANDRA_CLIENT_IP_ADDR
```

Any other properties can be set before application. A list can be determined by executing
`kpt cfg list-setters cassandra`.

### 2.4 Install cassandra

```bash
$ kpt live init cassandra
$ kpt live apply --reconcile-timeout 10m --poll-period 5s cassandra
storageclass.storage.k8s.io/ssd created
service/cassandra created
service/cassandra-client created
statefulset.apps/cassandra created
poddisruptionbudget.policy/cassandra created
5 resource(s) applied. 5 created, 0 unchanged, 0 configured
service/cassandra is NotFound: Resource not found
service/cassandra-client is NotFound: Resource not found
statefulset.apps/cassandra is NotFound: Resource not found
poddisruptionbudget.policy/cassandra is NotFound: Resource not found
storageclass.storage.k8s.io/ssd is NotFound: Resource not found
storageclass.storage.k8s.io/ssd is Current: Resource is current
service/cassandra is Current: Service is ready
service/cassandra-client is Current: Service is ready
statefulset.apps/cassandra is InProgress: Replicas: 1/3
poddisruptionbudget.policy/cassandra is Current: AllowedDisruptions has been computed.
statefulset.apps/cassandra is InProgress: Replicas: 1/3
statefulset.apps/cassandra is InProgress: Replicas: 1/3
statefulset.apps/cassandra is InProgress: Replicas: 2/3
statefulset.apps/cassandra is InProgress: Replicas: 2/3
statefulset.apps/cassandra is InProgress: Replicas: 2/3
statefulset.apps/cassandra is InProgress: Ready: 2/3
statefulset.apps/cassandra is InProgress: Ready: 2/3
statefulset.apps/cassandra is InProgress: Ready: 2/3
statefulset.apps/cassandra is Current: All replicas scheduled as expected. Replicas: 3
all resources has reached the Current status
0 resource(s) pruned, 0 skipped
```

Let's perform some simple verifications to make sure everything is OK.

```bash
$ kubectl -n cassandra get all
NAME              READY   STATUS    RESTARTS   AGE
pod/cassandra-0   1/1     Running   0          4m45s
pod/cassandra-1   1/1     Running   0          3m54s
pod/cassandra-2   1/1     Running   0          2m38s

NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                      AGE
service/cassandra          ClusterIP      None            <none>          7000/TCP,7001/TCP,7199/TCP   4m45s
service/cassandra-client   LoadBalancer   10.x.x.x        <cassandra_ip>  9042:30892/TCP               4m45s

NAME                         READY   AGE
statefulset.apps/cassandra   3/3     4m45s
```

Using `nodetool`, make sure all nodes are `UP` (ie. UP/Normal)

```bash
$ kubectl -n cassandra exec -ti cassandra-0 -- bash
root@cassandra-0:/# nodetool status
Datacenter: DC1
===============
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address    Load       Tokens       Owns (effective)  Host ID                               Rack
UN  10.44.3.8  104.55 KiB  32           64.2%             236e3ccc-ab0f-4c9c-a713-3d5ea88a7acb  Rack1
UN  10.44.1.4  103.81 KiB  32           61.1%             82fb0c2b-ac78-4152-aa8e-0f4eaeba42a7  Rack1
UN  10.44.0.6  65.87 KiB  32           74.7%             57520dfe-6d65-4a64-b774-fbb8e2c21fa5  Rack1

root@cassandra-0:/# exit
exit
```

## 3. Installing the Datomic transactor

In order to continue you need to register [here](https://my.datomic.com/account) for a Datomic account in order to get the credentials
required for downloading the datomic-pro binaries.

### 3.1 Downloading the binaries

```bash
$ export DATOMIC_VERSION=1.0.6202
$ export DATOMIC_USER=<your_registered_email>
$ export DATOMIC_PASSWORD=<your_password>
$ curl -L -u "$DATOMIC_USER:$DATOMIC_PASSWORD" \
   https://my.datomic.com/repo/com/datomic/datomic-pro/"$DATOMIC_VERSION"/datomic-pro-"$DATOMIC_VERSION".zip \
   -o datomic/datomic-pro-"$DATOMIC_VERSION".zip
```

### 3.2 Building the base image

You need to be working from this repo (and have a working version of `docker`) in order to build the image:

```bash
$ docker build \
   -t eu.gcr.io/$PROJECT_ID/datomic-pro:$DATOMIC_VERSION \
   --build-arg version=$DATOMIC_VERSION datomic/
$ docker images
REPOSITORY                         TAG      IMAGE ID     CREATED              SIZE
eu.gcr.io/<project_id>/datomic-pro 1.0.6202 a17fd47fc140 About a minute ago   1.34GB
```

### 3.3 Publish it to your local GKE registry

```bash
$ docker push eu.gcr.io/$PROJECT_ID/datomic-pro:1.0.6202 
The push refers to repository [eu.gcr.io/<your_project>/datomic-pro]
xxxxxxxxxxx: Pushed 
xxxxxxxxxxx: Pushed 
xxxxxxxxxxx: Pushed 
xxxxxxxxxxx: Layer already exists 
xxxxxxxxxxx: Layer already exists 
xxxxxxxxxxx: Layer already exists 
xxxxxxxxxxx: Layer already exists 
xxxxxxxxxxx: Layer already exists 
xxxxxxxxxxx: Layer already exists 
1.0.6202: digest: sha256:xxxxxx size: 2220
```

### 3.4 Reserve a public IP address for the datomic transactor

```bash
$ export TRANSACTOR_IP_ADDR_NAME=datomic-transactor
$ gcloud compute addresses create $TRANSACTOR_IP_ADDR_NAME \
   --project $PROJECT_ID \
   --region $REGION \
   --description "External IP Address to use for the datomic transactor"
$ export TRANSACTOR_IP_ADDR=$(gcloud compute addresses describe $TRANSACTOR_IP_ADDR_NAME \
   --project $PROJECT_ID \
   --region $REGION \
   --format json | jq -r .address)
```

### 3.5 Create the `datomic` namespace

```bash
$ kubectl create ns datomic
namespace/datomic created
$ kubectl config set-context $GKE_CLUSTER_NAME --namespace datomic
$ kubectl config use-context $GKE_CLUSTER_NAME
```

### 3.6 Set the required properties

```bash
$ kpt cfg set datomic/transactor/ authorized-networks $AUTHORIZED_NETWORKS
$ kpt cfg set datomic/transactor/ transactor-ip $TRANSACTOR_IP_ADDR
$ kpt cfg set datomic/transactor/ transactor-image eu.gcr.io/$PROJECT_ID/datomic-pro:1.0.6202
```
