FROM doogee323/devops-utils2:latest

ARG k8s_project=xxxxx
ENV k8s_project=${k8s_project}

ARG k8s_domain=xxxxx
ENV k8s_domain=${k8s_domain}

ARG vault_token=xxxxx
ENV vault_token=${vault_token}

EXPOSE 22

COPY init.sh /init.sh
RUN chmod +x init.sh

CMD /bin/bash -c "/init.sh"
