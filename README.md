# tz-k8s-vagrant

It supports two version of k8s installation in terraform or local VMs.
to project root directory. 

![Architecture1](./resource/tz-k8s-vagrant-env.png)

## -. Features 
```
    -. build a vagrant env
    -. install k8s master and nodes
    -. install dashboard
    -. install monitoring (Prometheus, Grafana)
    -. install jenkins
    -. build a test app(youtoube scrawler) in jenkins
    -. deploy the app to k8s 
```

## -. Run VMs with k8s 
``` 
    bash bootstrap.sh
    or
    bash bootstrap.sh S    # slave machine
    or
    bash bootstrap.sh remove
``` 

## -. Refer to README.md for each version.
```
    cf) my vagrant's host server priavte ip: 192.168.0.143

    - build a K8S in local vagrant VMs
        vagrant -> VMs -> k8s -> monitoring -> jenkins -> teat-app build
        scripts/local/README.md
```

## * install kubectl in macbook 
### cf) https://kubernetes.io/docs/tasks/tools/install-kubectl/
``` 
    brew install kubectl
    mkdir -p ~/.kube
    cp tz-k8s-vagrant/config ~/.kube/config
    kubectl get nodes
```



