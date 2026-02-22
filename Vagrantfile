# -*- mode: ruby -*-
# vi: set ft=ruby :

IMAGE_NAME = "bento/ubuntu-22.04"
COUNTER = 2

# Bridge interface: Mac (en0), Linux, Windows. Avoid "nul" on Mac (Gem.win_platform?)
def vbox_in_path?
  return true if system("which VBoxManage > /dev/null 2>&1")
  return system("where VBoxManage > nul 2>&1") if Gem.win_platform?
  false
end
def vbox_null; Gem.win_platform? ? "2>nul" : "2>/dev/null"; end
def get_bridge
  paths = ["VBoxManage", "/Applications/VirtualBox.app/Contents/MacOS/VBoxManage", "/usr/bin/VBoxManage",
           "C:/Program Files/Oracle/VirtualBox/VBoxManage.exe", (ENV["ProgramFiles"] || "C:/Program Files") + "/Oracle/VirtualBox/VBoxManage.exe"].compact.uniq
  vbox = paths.find { |p| p == "VBoxManage" ? vbox_in_path? : (File.exist?(p) && File.executable?(p)) }
  return "en0: Wi-Fi (AirPort)" unless vbox
  out = `"#{vbox}" list bridgedifs #{vbox_null}`
  return "en0: Wi-Fi (AirPort)" unless $?.success?
  ifs = out.split("\n").grep(/^Name:/).map { |l| l.sub(/^Name:\s+/, "").strip }
  return ifs.find { |i| i.include?("en0") } || ifs.first || "en0: Wi-Fi (AirPort)"
rescue
  "en0: Wi-Fi (AirPort)"
end
BRIDGE = get_bridge

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
    master.vm.network "public_network", bridge: BRIDGE, ip: "192.168.86.100"
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
        node.vm.network "public_network", bridge: BRIDGE, ip: "192.168.86.10#{i}"
        node.vm.hostname = "kube-node-#{i}"
        node.vm.provision "shell", :path => File.join(File.dirname(__FILE__),"scripts/local/node.sh"), :args => node.vm.hostname
    end
  end
end

