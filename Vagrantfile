# -*- mode: ruby -*-
# vi: set ft=ruby :

IMAGE_NAME = "bento/ubuntu-22.04"
COUNTER = 2
Vagrant.configure("2") do |config|
  config.vm.box = IMAGE_NAME
  config.ssh.insert_key=false
  # config.vm.provider "virtualbox" do |v|
  #   v.memory = 4096
  #   v.cpus = 2
  # end

  config.vm.define "kube-master" do |master|
    master.vm.box = IMAGE_NAME
    master.vm.provider "virtualbox" do |vb|
      vb.memory = 5096
      vb.cpus = 3
    end
    master.vm.network "public_network", bridge: "en0: Wi-Fi (AirPort)", ip: "192.168.86.100"
    master.vm.hostname = "kube-master"
    master.vm.provision "shell", :path => File.join(File.dirname(__FILE__),"scripts/local/master.sh"), :args => master.vm.hostname
  end

  (1..COUNTER).each do |i|
    config.vm.define "kube-node-#{i}" do |node|
        node.vm.box = IMAGE_NAME
        node.vm.provider "virtualbox" do |vb|
          vb.memory = 3072
          vb.cpus = 2
        end
        node.vm.network "public_network", bridge: "en0: Wi-Fi (AirPort)", ip: "192.168.86.10#{i}"
        node.vm.hostname = "kube-node-#{i}"
        node.vm.provision "shell", :path => File.join(File.dirname(__FILE__),"scripts/local/node.sh"), :args => node.vm.hostname
    end
  end
end

