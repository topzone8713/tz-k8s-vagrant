# tz-k8s-topzone

It supports two version of k8s installation in terraform or local VMs.
to project root directory. 

![Architecture1](./resource/tz-k8s-topzone-env.png)

## -. Features 
```
    -. Prep a build environment
    -. Install k8s master (kubespray.sh)
    -. Add k8s slave nodes (kubespray_add.sh)
    -. Install other applications (k8s_addtion.sh)
    -. Setup jenkins
    -. Build a demo application in jenkins
    -. Deploy the app to k8s 
```

## -. Prep a build environment
```
    -. checkout codes
       git clone https://github.com/topzone8713/tz-k8s-vagrant.git
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

## -. Install k8s master (kubespray.sh) on master machine
``` 
    bash bootstrap.sh M     # master machine
    # bash bootstrap.sh remove
    
    -. After installing k8s on master machine, check k8s master
        cd tz-k8s-vagrant
        vagrant status
        vagrant ssh kube-master
        sudo su
        kubectl get node
``` 

## -. Add k8s slave nodes (kubespray_add.sh)
``` 
    Copy master machine's .ssh folder to each slave machines for ssh key files
    - From: master machine
        tz-k8s-vagrant/.ssh
    - To: slave machines
        tz-k8s-vagrant/.ssh
    
    bash bootstrap.sh S     # slave machine
    # bash bootstrap.sh remove
    
    When slave nodes (Vagrant VMs) are up, run kubespray_add.sh on master machine.
    -. Check slave nodes' IPs
        cat tz-k8s-vagrant/info
    -. Add slave nodes' IPs on inventory_add.ini of master machine.
        tz-k8s-vagrant/resource/kubespray/inventory_add.ini
    -. Check network access on master machine.
        vagrant ssh kube-master
        sudo su
        cd /vagrant
        ansible all -i resource/kubespray/inventory_add.ini -m ping -u root    
        It should be like this,
        kube-slave-1 | SUCCESS => {
            "changed": false,
            "ping": "pong"
        }    
        ...
    -. Add k8s slave nodes on Master Node
        bash /vagrant/scripts/local/kubespray_add.sh
``` 

## -. Install other applications (k8s_addtion.sh)
``` 
    -. Set temporary domains
        vagrant ssh kube-master
        sudo su
        vi /etc/hosts
        ex) 192.168.86.200 is my ingress-nginx's EXTERNAL-IP
            kubectl get svc -n default | grep ingress-nginx-controller        
        
            192.168.86.200   test.default.topzone-k8s.topzone.me consul.default.topzone-k8s.topzone.me vault.default.topzone-k8s.topzone.me
            192.168.86.200   consul-server.default.topzone-k8s.topzone.me argocd.default.topzone-k8s.topzone.me
            192.168.86.200   jenkins.default.topzone-k8s.topzone.me harbor.default.topzone-k8s.topzone.me
            192.168.86.200   grafana.default.topzone-k8s.topzone.me prometheus.default.topzone-k8s.topzone.me alertmanager.default.topzone-k8s.topzone.me

    -. After installing k8s on all machines,
        bash /vagrant/scripts/k8s_addtion.sh
``` 

## -. Build Demo app
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



