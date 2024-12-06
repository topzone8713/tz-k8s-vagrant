# tz-jenkins

## jenkins setting
http://dooheehong323:31000/configure
Global properties > Environment variables > Add
ORGANIZATION_NAME: my-fleetman-organization
YOUR_DOCKERHUB_USERNAME: topzone8713

## git clone a test project
mkdir -p tz-k8s-topzone/projects
git clone https://github.com/devinterview-tz/fleetman-api-gateway.git

## make a project in Jenkins
new item
name: api-gateway
type: multibranch Pipeline
Display Name: api-gateway
Branch Sources: GitHub
    Credential: Jenkins
        Username: topzone8713 # github id
        Password: xxxx
            https://docs.github.com/en/free-pro-team@latest/github/authenticating-to-github/creating-a-personal-access-token
        ID: GitHub
    Owener: topzone
    
Repository HTTPS URL: https://github.com/devinterview-tz/fleetman-api-gateway

Run the project

## checking the result 
k get all | grep fleetman
service/fleetman-api-gateway   NodePort    10.97.78.220    <none>        8080:30020/TCP                   19m

curl http://10.97.78.220:8080


