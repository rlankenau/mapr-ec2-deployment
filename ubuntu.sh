#!/bin/bash -x

#parameters

# This security group should be already set up, and the key pair added and available on this node.
export MAPR_SECURITY_GROUP=default
export MAPR_KEY_PAIR=russ_aws_head_key

CURL_PRESENT=`which curl | wc -l`
if [[ $CURL_PRESENT -ne 1 ]]; then
  apt-get install curl
fi

PYTHON_PRESENT=`which python | wc -l`
if [[ $PYTHON_PRESENT -ne 1 ]]; then
  apt-get install python
fi

BOTO_PRESENT=`python -c "import boto"`
if [[ $? -ne 0 ]]; then
  PIP_PRESENT=`which pip | wc -l`
  if [[ $PIP_PRESENT -ne 1 ]]; then
    apt-get install python-pip
  fi
  pip install -U boto
fi

AWS_PRESENT=`which aws | wc -l`
if [[ $AWS_PRESENT -ne 1 ]]; then
  curl https://raw.github.com/timkay/aws/master/aws -o aws
  mv aws /bin/aws
  chmod +x /bin/aws
fi

JDK_PRESENT=`ls -1 | egrep "jdk.*linux-x64.bin" | wc -l`
if [[ $JDK_PRESENT -gt 0 ]]; then
  JDK_NAME=`ls -1 | egrep "jdk.*linux-x64.bin"`
  echo "Found JDK: $JDK_NAME"
else
  echo "No JDK installer found.  Please download the 64-bit linux installer from http://www.oracle.com/technetwork/java/javase/downloads/jdk6-downloads-1637591.html"
  exit 1
fi 

if [[ ! -e maprinstall ]]; then
  curl http://package.mapr.com/releases/v2.0.1/maprinstall -o maprinstall
fi

if [[ ! -e ~/.boto ]]; then
  NEED_DOTBOTO=1
fi

if [[ ! -e ~/.awssecret ]]; then
  NEED_DOTAWSSECRET=1
fi

if [[ $NEED_DOTBOTO == 1 || $NEED_DOTAWSSECRET == 1 ]]; then
  echo "Either ~/.boto or ~/.awssecret is missing.  Please enter your credentials"
  echo "Credentials are available at https://portal.aws.amazon.com/gp/aws/securityCredentials"
  echo "*** Hit CTRL-C now if you don't wish to overwrite .boto and .awssecret ***"

  read -p "AWS Access Key ID:" AWSKEY
  read -p "AWS Secret Access Key:" AWSSECRET

  echo "[Credentials]" > ~/.boto
  echo "aws_access_key_id=$AWSKEY" >> ~/.boto
  echo "aws_secret_access_key=$AWSSECRET" >> ~/.boto

  echo "$AWSKEY" > ~/.awssecret
  echo "$AWSSECRET" >> ~/.awssecret
fi

export MAPR_AWS_GROUP="group_$RANDOM"

python - <<EOF

#  This script uses the boto library for EC2
#  To install boto, do the following:
#  # apt-get install python-pip
#  # pip install -U boto
#
#  also, write a file called ~/.boto that looks like this:
#  
#   [Credentials]
#   aws_access_key_id=<KEY>
#   aws_secret_access_key=<SECRET KEY>
#

import boto
import boto.ec2
import sys
import os
import base64
from subprocess import call
import random


# This is a static config for now.  It should be pretty easy to build a menu using aws boto would be simple code but more of it.  

number_of_servers = 16 # This cannot be less than 3
security_group = os.environ["MAPR_SECURITY_GROUP"]
key_pair_name = os.environ["MAPR_KEY_PAIR"]
region = "us-west-1"
region_avail_zone = "us-west-1c"
#ami_id="ami-baba68d3"
#ami_id="ami-1cdd532c"
ami_id="ami-0d153248"
instance_type="m1.large"
groupname = os.environ["MAPR_AWS_GROUP"]

# This makes the call to the amizon api to launch the instances. You will need aws in your path you can install/get it using curl. 
# "curl https://raw.github.com/timkay/aws/master/aws -o aws" you will need to put in your Path some for the call function to work. You also need to create 
#.awssecret similar to the .boto file but now key valuel pair just the keys.  
#  aws_access_key_id
#  aws_secret_access_key  
#aws run -h is useful timkay.com/aws has the full doc.    

call (["aws", "--region", region, "run", ami_id, "-i", instance_type, "-n", str(number_of_servers),
"-g",security_group,"-k",key_pair_name,"-z",region_avail_zone,"-d",groupname,"--wait=10"])

account = boto.ec2.connect_to_region(region)
nodes = open('nodes.{}'.format(groupname), 'w')
internal = []

try:
  for r in account.get_all_instances():
    for i in r.instances:
      if i.state == "running":
        if groupname == base64.b64decode(i.get_attribute("userData")['userData']):
          nodes.write(i.public_dns_name + "\n")
          internal.append(i.private_dns_name)
except Exception, err:
  nodes.close()
  nodes = open('nodes.{}'.format(groupname), 'w')
  internal=[]
  for r in account.get_all_instances():
    for i in r.instances:
      if i.state == "running":
        if instance_type == i.instance_type and key_pair_name == i.key_name:
          nodes.write(i.public_dns_name + "\n")
          internal.append(i.private_dns_name)
nodes.close()

#build the roles file.
roles_map = []
for i in internal:
  new_list = []
  new_list.append("mapr-nfs")
  new_list.append("mapr-fileserver")
  new_list.append("mapr-tasktracker")
  new_list.append("mapr-pig")
  roles_map.append(new_list)

if number_of_servers < 5:
  roles_map[0].append("mapr-zk-internal")
  roles_map[0].append("mapr-zookeeper")
  roles_map[0].append("mapr-cldb")
  roles_map[0].append("mapr-webserver")
  roles_map[0].append("mapr-jobtracker")
elif number_of_servers < 10:
  roles_map[0].append("mapr-zk-internal")
  roles_map[0].append("mapr-zookeeper")
  roles_map[0].append("mapr-webserver")
  roles_map[1].append("mapr-zk-internal")
  roles_map[1].append("mapr-zookeeper")
  roles_map[2].append("mapr-zk-internal")
  roles_map[2].append("mapr-zookeeper")
  roles_map[3].append("mapr-cldb")
  roles_map[4].append("mapr-cldb")
  roles_map[2].append("mapr-jobtracker")
  roles_map[3].append("mapr-jobtracker")
  roles_map[4].append("mapr-jobtracker")
else:
  roles_map[0].append("mapr-zk-internal")
  roles_map[0].append("mapr-zookeeper")
  roles_map[0].append("mapr-webserver")
  roles_map[1].append("mapr-zk-internal")
  roles_map[1].append("mapr-zookeeper")
  roles_map[2].append("mapr-zk-internal")
  roles_map[2].append("mapr-zookeeper")
  roles_map[3].append("mapr-cldb")
  roles_map[4].append("mapr-cldb")
  roles_map[5].append("mapr-jobtracker")
  roles_map[6].append("mapr-jobtracker")
  roles_map[7].append("mapr-jobtracker")

roles = open('./roles.{}'.format(groupname), 'w')
print "Found {} nodes in group {}".format(len(internal), groupname)
for i in range(number_of_servers):
  roles.write("{} {} {}\n".format(internal[i], ",".join(roles_map[i]), "/dev/xvdb"))

roles.close()
 
EOF

read -p "Check that all nodes are up and running (Status checks 2/2), and then hit RETURN"

export NODESFILE="nodes.$MAPR_AWS_GROUP"
export FIRSTNODE=`head -1 $NODESFILE`
export NUMNODES=`wc -l $NODESFILE | cut -f 1 -d' '`

#remove all hosts that we're going to be dealing with from ~/.ssh/known_hosts
for i in `cat $NODESFILE`; do ssh-keygen -R $i ;done

# If your key is in .ssh just leave this blank that should work.  
#KEY_SPEC="-i /home/canyon/Keys/Basic-pair.pem"

# This enables the root login however this will only work un Ubuntu for 2 reasons one is obvious.. The other is Redhat/Cent sshd will not allow remote root by default.    
#It also assumes that you are using your local machine's key in .ssh to access the hosts.  This is not all ways practical.   
for i in `cat $NODESFILE`; do ssh -o StrictHostKeyChecking=no $KEY_SPEC ubuntu@$i 'sudo cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys' ;done

# ssh to first node, generate ssh key
ssh $KEY_SPEC root@$FIRSTNODE 'ssh-keygen -q -N "" -f ~/.ssh/id_rsa'
# copy to all other hosts
scp $KEY_SPEC root@$FIRSTNODE:.ssh/id_rsa ./key.$MAPR_AWS_GROUP
scp $KEY_SPEC root@$FIRSTNODE:.ssh/id_rsa.pub ./key.$MAPR_AWS_GROUP.pub
for i in `tail -$(($NUMNODES-1)) $NODESFILE`; do scp $KEY_SPEC ./key.$MAPR_AWS_GROUP root@$i:.ssh/id_rsa ;done
for i in `tail -$(($NUMNODES-1)) $NODESFILE`; do scp $KEY_SPEC ./key.$MAPR_AWS_GROUP.pub root@$i:.ssh/id_rsa.pub ;done

for i in `cat $NODESFILE`; do ssh root@$i 'cat .ssh/id_rsa.pub >> .ssh/authorized_keys' ;done

# copy maprinstall script this does most of the heavy lifting for the install
scp $KEY_SPEC ./maprinstall root@$FIRSTNODE:
# this fils are generated by the local ec2_prep.py script roles is need by maprinstall nodes is use for all the iterations in shell scripts yes we could probably just use roles with some awk or sed not sure it is worth it.  
scp $KEY_SPEC ./roles.$MAPR_AWS_GROUP root@$FIRSTNODE:roles.txt
scp $KEY_SPEC ./nodes.$MAPR_AWS_GROUP root@$FIRSTNODE:nodes
# Copy over your java install file that you downloaded so that you use local network for copy
scp $KEY_SPEC $JDK_NAME root@$FIRSTNODE:java_install.bin
# this copies over the install script that preps the box for the mapr install. Mostly it adds keys and the repos to the boxes
scp $KEY_SPEC ./ubuntu_remote.sh root@$FIRSTNODE:

#This executes the scripts in order on the head node. 

echo "Beginning final install."
ssh $KEY_SPEC root@$FIRSTNODE ./ubuntu_remote.sh

echo "Install complete!  Check for MCS on https://$FIRSTNODE:8443 to verify install"
