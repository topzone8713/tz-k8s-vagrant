# tz-jenkins

###################################################
## build a jenkins project in EKS
###################################################
```

 - get jenkins url
   => https://jenkins.default.topzone-k8s.topzone.me

 - setting kubernetes plugin
    https://jenkins.default.topzone-k8s.topzone.me/configureClouds/
   - Name: topzone-k8s
   - Kubernetes URL: https://kubernetes.default
   - Kubernetes Namespace: jenkins
    * click Test Connection
   - Jenkins URL: http://jenkins.jenkins.svc.cluster.local
   - Jenkins tunnel: jenkins-agent:50000

 - add github secrets  
    - github-token
      1. get github's personal access token:
        https://github.com/settings/tokens
      2. http://jenkins.default.topzone-k8s.topzone.me/credentials/store/system/domain/_/newCredentials
        Kind: Username with password
        Username: ex) topzone8713@gmail.com
        Password: ex) xxxxxxxxxxxxxxxxxxxxxxxxx
        ID: github-token

    - GITHUP_TOKEN
      1. get github's personal access token:
      2. http://jenkins.default.topzone-k8s.topzone.me/credentials/store/system/domain/_/newCredentials
        Kind: Secret text
        Secret: ex) xxxxxxxxxxxxxxxxxxxxxxxxx
        ID: GITHUP_TOKEN

 - email settings
    http://localhost:53053/manage/configure
    Git plugin
        Global Config user.name Value: 
        Global Config user.email Value: 

    - E-mail
        SMTP Server: smtp.gmail.com
        Use SMTP Authentication
        Username: topzone8713@gmail.com
        Password: xxxxx  => Google "App password"
        Use SSL: false
        Use TLS: yes
        SMTP Port: 587
        Test configuration by sending test e-mail
        Test e-mail recipient

    - Extended E-mail Notification
        SMTP server: smtp.gmail.com
        SMTP Port: 587
        new credential: gmail-smtp
        Use SSL: false
        Use TLS: yes
```

###################################################
## build a demo app
###################################################

github fork: https://github.com/topzone8713/tz-devops-admin.git
https://github.com/aaaaa/tz-devops-admin.git

new project
Name: tz-devops-admin
Pipeline: Pipeline script from SCM
    SCM: Git
    Repository URL: https://github.com/aaaaa/tz-devops-admin.git
    credentials: github-token
    branch: devops
Script Path: k8s/Jenkinsfile

tz-devops-admin/k8s/Jenkinsfile

    environment {
        GITHUP_ID = "topzone8713"               =>
        GIT_URL = "https://github.com/${GITHUP_ID}/tz-devops-admin.git"
        GIT_BRANCH = "devops"                   =>
        GIT_COMMITTER_EMAIL = "topzone8713@gmail.com"   =>

        DOMAIN = "topzone.me"                   =>
        CLUSTER_NAME = "topzone-k8s"

