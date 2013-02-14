#!/bin/bash

# Add mapr repo
for i in `cat nodes`; do ssh -o StrictHostKeyChecking=no root@$i 'echo "deb http://package.mapr.com/releases/v2.0.1/ubuntu/ mapr optional" >> /etc/apt/sources.list' ;done
for i in `cat nodes`; do ssh root@$i 'echo "deb http://package.mapr.com/releases/ecosystem/ubuntu/ binary/" >> /etc/apt/sources.list' ;done

for i in `cat nodes`; do ssh root@$i 'apt-get update' ;done
# unmount drives
for i in `cat nodes`; do ssh root@$i 'umount /mnt && echo `cat /etc/fstab | grep LABEL` > /etc/fstab' ;done

# remove 127.0.1.1 line in /etc/hosts if it is in there.
for i in `cat nodes`; do ssh root@$i 'sed -i -e "s/127.0.1.1.*//" /etc/hosts' ;done


for i in `cat nodes`; do scp ./java_install.bin root@$i:/tmp/java_install.bin ;done
for i in `cat nodes`; do ssh root@$i 'chmod +x /tmp/java_install.bin' ;done
for i in `cat nodes`; do ssh root@$i 'cd /opt && /tmp/java_install.bin' ;done

REMOTE_JAVA_HOME=/opt/`ls -1 /opt/ | grep jdk | head -1`

for i in `cat nodes`; do ssh root@$i "ln -s $REMOTE_JAVA_HOME /opt/java" ;done
for i in `cat nodes`; do ssh root@$i 'echo "export JAVA_HOME=/opt/java" >> /etc/environment' ;done
for i in `cat nodes`; do ssh root@$i 'echo "export PATH=/opt/java/bin:$PATH" >> /etc/environment' ;done

. /etc/environment

chmod +x ./maprinstall
./maprinstall -f -R ./roles.txt

 ln -s /lib/x86_64-linux-gnu/libpam.so.0 /lib64/libpam.so.0

chpasswd <<EOF
root:mapr
mapr:mapr
EOF

/opt/mapr/adminuiapp/webserver start
