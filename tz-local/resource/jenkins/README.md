# tz-jenkins

###################################################
## build a jenkins project in EKS
###################################################
```

 - get jenkins url
   => http://jenkins.eks-main.shoptoolstest.co.kr

 - setting kubernetes plugin
    http://jenkins.eks-main.shoptoolstest.co.kr/configureClouds/
   - Name: k8s-aws  
   - Kubernetes URL: https://kubernetes.default
   - Kubernetes Namespace: jenkins
    * click Test Connection
   - Jenkins URL: http://jenkins:8080
   - Jenkins tunnel: jenkins-agent:50000

   - Add Pod Template
     Pod Templates: slave1
     Containers: slave1
     Docker image: doohee323/jenkins-slave

 - add aws & github secrets  
    - github
      1. get github's personal access token: ex) d465eaa43af65cececde0a63e310c2bxxxxxxxx
        https://github.com/settings/tokens
      2. http://jenkins.eks-main.shoptoolstest.co.kr/credentials/store/system/domain/_/newCredentials
        Kind: Username with password
        Username: ex) doohee323@shoptoolstest.co.kr
        Password: ex) d465eaa43af65cececde0a63e310c2bxxxxxxxx
        ID: Github

    - aws
        http://jenkins.eks-main.shoptoolstest.co.kr/credentials/store/system/domain/_/newCredentials
        Kind: Secret text
        Secret: ex) AKIATEMCRY56PRC5xxxxx
        ID: jenkins-aws-secret-key-id

        http://jenkins.eks-main.shoptoolstest.co.kr/credentials/store/system/domain/_/newCredentials
        Kind: Secret text
        Secret: ex) Kotgln3kkPevmfKxxxxxxxxxxxxxxxxxxx
        ID: jenkins-aws-secret-access-key

    - jenkins-aws-secret
      1. get aws access key: ex) 	AKIATEMCRY56PRC5xxxxx
      2. http://jenkins.eks-main.shoptoolstest.co.kr/credentials/store/system/domain/_/newCredentials
        Kind: AWS Credentials
        ID: jenkins-aws-secret
        Access Key ID: ex) AKIATEMCRY56PRC5xxxxx
        Secret Access Key: ex) Kotgln3kkPevmfKxxxxxxxxxxxxxxxxxxx

    - set a sample project (devops-crawler)
        http://jenkins.eks-main.shoptoolstest.co.kr/ 
        - Github
            - Credentials: ex) doohee323@shoptoolstest.co.kr

```

