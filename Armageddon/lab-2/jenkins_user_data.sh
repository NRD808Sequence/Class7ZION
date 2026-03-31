#!/bin/bash
set -e

########################################
# Mount persistent EBS volume for Jenkins home
# Device appears as /dev/nvme1n1 on t3 (NVMe) or /dev/xvdf on older types
########################################

for i in $(seq 1 12); do
  if [ -b /dev/nvme1n1 ]; then
    DEVICE=/dev/nvme1n1
    break
  elif [ -b /dev/xvdf ]; then
    DEVICE=/dev/xvdf
    break
  fi
  sleep 5
done

if [ -n "$DEVICE" ]; then
  # Format only if the volume has no filesystem (first launch)
  if ! blkid "$DEVICE" | grep -q "jenkins-data"; then
    mkfs.ext4 -L jenkins-data "$DEVICE"
  fi

  mkdir -p /var/lib/jenkins

  mount -L jenkins-data /var/lib/jenkins

  if ! grep -q "jenkins-data" /etc/fstab; then
    echo "LABEL=jenkins-data /var/lib/jenkins ext4 defaults,nofail 0 2" >> /etc/fstab
  fi
fi

########################################
# Install Jenkins on Amazon Linux 2023 with Java 21
########################################

# AL2023 uses dnf
dnf update -y

# Add Jenkins repo
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

# Java 21 (Jenkins LTS supported, replaces Java 17 which EOLs Mar 31 2026)
dnf install -y java-21-amazon-corretto-headless

# Jenkins + Git
dnf install -y jenkins git

########################################
# Install Terraform (HashiCorp repo)
########################################
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
dnf install -y terraform

systemctl enable jenkins
systemctl start jenkins

timeout 120 bash -c 'until [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; do sleep 3; done'
echo "Jenkins initial admin password: $(cat /var/lib/jenkins/secrets/initialAdminPassword)" >> /var/log/jenkins-setup.log
echo "Jenkins setup complete on Amazon Linux 2023 with Java 21."
