# tz-k8s-topzone

It supports two version of k8s installation in terraform or local VMs.
to project root directory. 

![Architecture1](./resource/tz-k8s-topzone-env.png)

## -. Features 
```
    -. Prep a build environment
    -. install k8s master (kubespray.sh)
    -. add k8s slave nodes (kubespray_add.sh)
    -. install other applications (k8s_addtion.sh)
    -. setup jenkins
    -. build a demo application in jenkins
    -. deploy the app to k8s 
```

## -. Prep 
```
    -. checkout codes
       git clone https://dooheehong@github.com/topzone8713/tz-k8s-vagrant.git
       cd tz-k8s-vagrant

    -. copy resources like this,
        tz-k8s-vagrant/resources
            project             # change your project name, it'll be a eks cluster name.
            config.json         # dockerhub auth

    -. project infos
    tz-k8s-vagrant/resources/project
    
    ex)
        project=topzone-k8s
        domain=topzone.me     # temporary local domain
        argocd_id=admin
        admin_password=DevOps!323
        basic_password=Soqn!323
        github_id=topzone8713       # your github_id
        github_token=               # your github token
        docker_url=index.docker.io
        dockerhub_id=topzone8713    # your dockerhub_id
        dockerhub_password=         # your dockerhub_password
        vault=xxxx                  
    
    -. dockerhub auth 
    tz-k8s-vagrant/resources/config.json
        
        {
            "auths": {
                "https://index.docker.io/v1/": {
                    "username":"topzone8713",           # your dockerhub_id
                    "password":"xxxx",                  # your dockerhub_password
                    "email":"topzone8713@gmail.com",    # your email
                    "auth":"xxxxxx"                     # your dockerhub auth token, 
                                                        # After running "docker login" on your pc, 
                                                        # cat ~/.docker/config.json
                }
            }
        }
```

## -. Install / Reload VMs with k8s 
``` 
    bash bootstrap.sh M     # master machine
    or
    bash bootstrap.sh S     # slave machine
    or
    bash bootstrap.sh remove
``` 

## -. Refer to README.md for each version.
```
    cf) my topzone's host server ip: 192.168.86.143

    - build a K8S in local topzone VMs
        topzone -> VMs -> k8s -> monitoring -> jenkins -> demo-app build
        scripts/local/README.md
```

## * install kubectl in macbook 
### cf) https://kubernetes.io/docs/tasks/tools/install-kubectl/
``` 
    brew install kubectl
    mkdir -p ~/.kube
    cp tz-k8s-topzone/config ~/.kube/config
    kubectl get nodes
```



