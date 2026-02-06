# -*- mode: ruby -*-
# vi: set ft=ruby :

IMAGE_NAME = "bento/ubuntu-22.04"
COUNTER = 2

# Windows only: avoid using "nul" on Mac/Linux (creates a file named "nul")
def vbox_in_path?
  return true if system("which VBoxManage > /dev/null 2>&1")
  return system("where VBoxManage > nul 2>&1") if Gem.win_platform?
  false
end

def vbox_null_redirect
  Gem.win_platform? ? "2>nul" : "2>/dev/null"
end

# Detect network interface: Mac (en0), Linux, or Windows
def get_bridge_interface
  # Find VBoxManage command
  vboxmanage_cmd = nil
  possible_paths = [
    "VBoxManage",
    "/Applications/VirtualBox.app/Contents/MacOS/VBoxManage",
    "/usr/bin/VBoxManage",
    "/usr/local/bin/VBoxManage",
    "C:/Program Files/Oracle/VirtualBox/VBoxManage.exe",
    "C:/Program Files (x86)/Oracle/VirtualBox/VBoxManage.exe",
    (ENV["ProgramFiles"] || "C:/Program Files") + "/Oracle/VirtualBox/VBoxManage.exe"
  ].compact.uniq

  possible_paths.each do |path|
    if path == "VBoxManage"
      if vbox_in_path?
        vboxmanage_cmd = path
        break
      end
    elsif File.exist?(path) && File.executable?(path)
      vboxmanage_cmd = path
      break
    end
  end

  mac_default = "en0: Wi-Fi (AirPort)"
  return mac_default unless vboxmanage_cmd

  begin
    output = `"#{vboxmanage_cmd}" list bridgedifs #{vbox_null_redirect}`
    return mac_default unless $?.success?

    interfaces = output.split("\n").grep(/^Name:/).map do |line|
      line.sub(/^Name:\s+/, "").strip
    end

    # Mac: prefer en0
    if interfaces.include?("en0: Wi-Fi (AirPort)")
      return "en0: Wi-Fi (AirPort)"
    elsif interfaces.any? { |iface| iface.start_with?("en0:") }
      return interfaces.find { |iface| iface.start_with?("en0:") }
    elsif interfaces.include?("en0")
      return "en0"
    end

    # Windows/Linux: use first available interface
    return interfaces.first if interfaces.any?
    mac_default
  rescue
    mac_default
  end
end

BRIDGE_INTERFACE = get_bridge_interface

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
    if BRIDGE_INTERFACE
      master.vm.network "public_network", bridge: BRIDGE_INTERFACE, ip: "192.168.0.100"
    else
      master.vm.network "public_network", ip: "192.168.0.100"
    end
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
        if BRIDGE_INTERFACE
          node.vm.network "public_network", bridge: BRIDGE_INTERFACE, ip: "192.168.0.10#{i}"
        else
          node.vm.network "public_network", ip: "192.168.0.10#{i}"
        end
        node.vm.hostname = "kube-node-#{i}"
        node.vm.provision "shell", :path => File.join(File.dirname(__FILE__),"scripts/local/node.sh"), :args => node.vm.hostname
    end
  end
end

